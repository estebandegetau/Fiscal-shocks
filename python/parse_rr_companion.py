"""Parse the Romer & Romer (2010) companion paper into structured JSON.

Reads /tmp/rr_companion.txt and extracts:
  1. Structured shock data (act name, date, quarterly revenue changes, categories)
  2. Evidence/label data (quoted passages, attributions, dates)

Outputs:
  /tmp/parsed_shocks.json  — structured act data
  /tmp/parsed_labels.json  — evidence passages per act
"""

import json
import re
import sys
from pathlib import Path

INPUT_FILE = Path("/tmp/rr_companion.txt")
OUT_SHOCKS = Path("/tmp/parsed_shocks.json")
OUT_LABELS = Path("/tmp/parsed_labels.json")

RE_SIGNED = re.compile(r"^(Signed|Date|Effective):\s+(.+)$")
RE_PAGE_NUM = re.compile(r"^\d{1,3}$")
RE_QUARTER = re.compile(r"(\d{4})Q(\d)")
RE_AMOUNT = re.compile(r"([+\u2013\u2014\u2212−–-])\$?([\d,.]+)\s+billion")
RE_CATEGORY = re.compile(
    r"\((Endogenous|Exogenous)[;:,]\s*(Spending-driven|Countercyclical|Deficit-driven|Long-run)\)"
)


def parse_date_signed(raw: str) -> str:
    m = re.search(r"(\d{1,2})/(\d{1,2})/(\d{2,4})", raw)
    if not m:
        return raw.strip()
    month, day, year = int(m.group(1)), int(m.group(2)), m.group(3)
    if len(year) == 2:
        yr = int(year)
        year_full = 1900 + yr if yr >= 45 else 2000 + yr
    else:
        year_full = int(year)
    return f"{year_full}-{month:02d}-{day:02d}"


def qstr(year: int, q: int) -> str:
    return f"{year}-{q:02d}"


def parse_sign(s: str) -> float:
    if s in ("-", "\u2013", "\u2014", "−", "–", "\u2212"):
        return -1.0
    return 1.0


def is_structural(line: str) -> bool:
    """Check if a line is part of the structured header."""
    s = line.strip()
    if not s:
        return True  # blank lines are neutral
    if RE_PAGE_NUM.match(s):
        return True  # page numbers are neutral (skip but don't end)
    if "Change in Liabilities" in s:
        return True
    if s.startswith("Present Value"):
        return True
    q_match = RE_QUARTER.search(s)
    if q_match and (len(s) < 80 or q_match.start() < 5):
        return True
    a_match = RE_AMOUNT.search(s)
    if a_match and (len(s) < 80 or a_match.start() < 5):
        return True
    if RE_CATEGORY.search(s) and s.startswith("("):
        return True
    if s[0] in ("+", "-", "–", "—", "−", "\u2013", "\u2014", "\u2212"):
        return True
    return False


# ---------------------------------------------------------------------------
# Find act blocks - work with raw text
# ---------------------------------------------------------------------------
def find_act_blocks(text: str) -> list[dict]:
    lines = text.split("\n")

    part2 = 0
    for i, line in enumerate(lines):
        if "II. ACT-BY-ACT SUMMARY" in line:
            part2 = i
            break

    signed_indices = []
    for i in range(part2, len(lines)):
        m = RE_SIGNED.match(lines[i].strip())
        if m:
            signed_indices.append(i)

    acts = []
    for idx, si in enumerate(signed_indices):
        # Act name
        nl = si - 1
        while nl > 0 and not lines[nl].strip():
            nl -= 1
        name = lines[nl].strip()
        if RE_PAGE_NUM.match(name):
            nl -= 1
            while nl > 0 and not lines[nl].strip():
                nl -= 1
            name = lines[nl].strip()

        signed_raw = lines[si].strip()
        date_part = RE_SIGNED.match(signed_raw).group(2)

        # End of block
        if idx + 1 < len(signed_indices):
            next_si = signed_indices[idx + 1]
            next_nl = next_si - 1
            while next_nl > 0 and not lines[next_nl].strip():
                next_nl -= 1
            if RE_PAGE_NUM.match(lines[next_nl].strip()):
                next_nl -= 1
                while next_nl > 0 and not lines[next_nl].strip():
                    next_nl -= 1
            end = next_nl
        else:
            end = len(lines)
            for i in range(si, len(lines)):
                if lines[i].strip() == "REFERENCES":
                    end = i
                    break

        acts.append({
            "act_name": name,
            "signed_raw": date_part.strip(),
            "date_signed": parse_date_signed(date_part),
            "raw_lines": lines[si + 1:end],
        })

    return acts


# ---------------------------------------------------------------------------
# Clean header: strip page numbers and footnotes from header area only
# ---------------------------------------------------------------------------
def clean_header_area(raw_lines: list[str]) -> tuple[list[str], int]:
    """Extract clean header lines and find narrative start.

    Returns (header_lines, narrative_start_index_in_raw).

    The companion paper has footnotes and page breaks in the header area.
    We scan ahead broadly to find any remaining structural data.
    """
    header = []
    i = 0

    while i < len(raw_lines):
        line = raw_lines[i].strip()

        # Skip blank lines
        if not line:
            i += 1
            continue

        # Skip page numbers (range 17-95 covers all pages in Part II)
        if RE_PAGE_NUM.match(line) and 17 <= int(line) <= 95:
            i += 1
            continue

        # Skip small standalone numbers that are footnote markers
        if RE_PAGE_NUM.match(line) and int(line) <= 30:
            i += 1
            continue

        # Check if structural
        if is_structural(line):
            header.append(line)
            i += 1
            continue

        # Not structural - could be footnote text or narrative
        # Scan ahead broadly (up to 30 lines) to find structural data
        has_future = False
        for j in range(i + 1, min(i + 30, len(raw_lines))):
            fl = raw_lines[j].strip()
            if not fl:
                continue
            if RE_PAGE_NUM.match(fl):
                continue
            if ("Change in Liabilities" in fl or "Present Value" in fl or
                RE_QUARTER.search(fl) or RE_AMOUNT.search(fl)):
                has_future = True
                break
            if RE_CATEGORY.search(fl) and fl.startswith("("):
                has_future = True
                break
            # Count long non-structural text lines
            # If we see 3+ consecutive long text lines, it's narrative
            # (footnotes are usually 1-3 lines)

        if has_future:
            # This is footnote text - skip it
            i += 1
            continue
        else:
            # This is the start of the narrative
            return header, i

    return header, len(raw_lines)


# ---------------------------------------------------------------------------
# Parse structured header
# ---------------------------------------------------------------------------
def parse_header(header_lines: list[str]) -> dict:
    standard = []
    retroactive = []
    present_value = []

    section = None
    last_q = None
    pending_qs = []
    _deferred_std_qs = []  # std quarters whose amounts come after PV header

    for line in header_lines:
        # Section detection
        if "Change in Liabilities (excluding retroactive" in line:
            section = "std"
            pending_qs = []
            continue
        if "Change in Liabilities (including retroactive" in line:
            section = "retro"
            pending_qs = []
            continue
        if re.match(r"Change in Liabilities:?\s*$", line):
            section = "std"
            pending_qs = []
            continue
        if line.startswith("Present Value:") or line == "Present Value:":
            # If we have pending quarters from the std section, the amounts
            # that follow belong to std, not PV. This happens with the
            # Crude Oil Windfall Profit Tax Act due to column-style layout
            # where std quarters appear before PV header but their amounts
            # appear after it, interleaved with PV quarters and amounts.
            _deferred_std_qs = list(pending_qs) if (pending_qs and section == "std") else []
            rest = line[len("Present Value:"):].strip() if ":" in line else ""
            section = "pv"
            pending_qs = []
            if rest:
                line = rest
            else:
                continue

        if section is None:
            continue

        q_m = RE_QUARTER.search(line)
        a_m = RE_AMOUNT.search(line)
        c_m = RE_CATEGORY.search(line)

        target = {"std": standard, "retro": retroactive, "pv": present_value}[section]

        if q_m and a_m:
            year, q = int(q_m.group(1)), int(q_m.group(2))
            qs = qstr(year, q)
            val = parse_sign(a_m.group(1)) * float(a_m.group(2).replace(",", ""))
            last_q = qs
            pending_qs = []
            target.append({
                "quarter": qs, "amount": val,
                "category": c_m.group(2) if c_m else None,
                "exogeneity": c_m.group(1) if c_m else None,
            })
        elif q_m and not a_m:
            year, q = int(q_m.group(1)), int(q_m.group(2))
            pending_qs.append(qstr(year, q))
            last_q = qstr(year, q)
        elif a_m and not q_m:
            val = parse_sign(a_m.group(1)) * float(a_m.group(2).replace(",", ""))
            # Deferred std quarters get priority over PV pending quarters
            if _deferred_std_qs:
                qs = _deferred_std_qs.pop(0)
                standard.append({
                    "quarter": qs, "amount": val,
                    "category": c_m.group(2) if c_m else None,
                    "exogeneity": c_m.group(1) if c_m else None,
                })
            else:
                qs = pending_qs.pop(0) if pending_qs else last_q
                target.append({
                    "quarter": qs, "amount": val,
                    "category": c_m.group(2) if c_m else None,
                    "exogeneity": c_m.group(1) if c_m else None,
                })
        elif c_m:
            # Apply category to the first uncategorized entry in order:
            # standard → retroactive → present_value
            applied = False
            for lst in (standard, retroactive, present_value):
                for entry in lst:
                    if entry["category"] is None:
                        entry["category"] = c_m.group(2)
                        entry["exogeneity"] = c_m.group(1)
                        applied = True
                        break
                if applied:
                    break

    return {"standard": standard, "retroactive": retroactive, "present_value": present_value}


# ---------------------------------------------------------------------------
# Narrative and label extraction
# ---------------------------------------------------------------------------
def extract_narrative(raw_lines: list[str], start: int) -> str:
    parts = []
    for line in raw_lines[start:]:
        s = line.strip()
        if not s:
            continue
        if RE_PAGE_NUM.match(s) and 17 <= int(s) <= 95:
            continue
        parts.append(s)
    return re.sub(r"\s+", " ", " ".join(parts)).strip()


def extract_labels(narrative: str) -> list[dict]:
    labels = []
    for m in re.finditer(r'["\u201c]([^"\u201d]+)["\u201d]', narrative):
        quote = m.group(1).strip()
        if len(quote) < 15:
            continue
        preceding = narrative[max(0, m.start() - 300):m.start()]
        source = ""
        date = ""
        src_m = re.search(
            r"(?:in (?:his|her|the|a) )?([\w\s]+?)\s*(?:stated|said|reported|announced|noted|wrote)"
            r"|(\d{4}\s+(?:Economic Report|Budget|Treasury))",
            preceding[-200:],
        )
        if src_m:
            source = (src_m.group(1) or src_m.group(2) or "").strip()
        date_m = re.search(r"(\d{1,2}/\d{1,2}/\d{2,4})", preceding[-150:])
        if date_m:
            date = date_m.group(1)
        labels.append({"motivation": quote, "source": source, "date": date})
    return labels


def primary_classification(entries):
    for e in entries:
        if e["category"] and e["exogeneity"]:
            return e["category"], e["exogeneity"]
    return "", ""


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    text = INPUT_FILE.read_text(encoding="utf-8")
    acts = find_act_blocks(text)
    print(f"Found {len(acts)} acts")

    shocks = []
    all_labels = []

    for act in acts:
        header_lines, narr_start = clean_header_area(act["raw_lines"])
        header = parse_header(header_lines)
        narrative = extract_narrative(act["raw_lines"], narr_start)

        std = header["standard"]
        retro = header["retroactive"]
        pv = header["present_value"]

        shocks.append({
            "act_name": act["act_name"],
            "date_signed": act["date_signed"],
            "signed_raw": act["signed_raw"],
            "standard_entries": std,
            "retroactive_entries": retro,
            "present_value_entries": pv,
            "narrative": narrative,
        })

        labels = extract_labels(narrative)
        cat, exo = primary_classification(std or retro)
        for lab in labels:
            all_labels.append({
                "act_name": act["act_name"],
                "exogeneity": exo,
                "category": cat,
                **lab,
            })

    OUT_SHOCKS.write_text(json.dumps(shocks, indent=2, ensure_ascii=False))
    OUT_LABELS.write_text(json.dumps(all_labels, indent=2, ensure_ascii=False))

    print(f"Wrote {len(shocks)} acts to {OUT_SHOCKS}")
    print(f"Wrote {len(all_labels)} labels to {OUT_LABELS}")

    for s in shocks:
        n_std = len(s["standard_entries"])
        n_ret = len(s["retroactive_entries"])
        n_pv = len(s["present_value_entries"])
        print(f"  {s['act_name']}: std={n_std}, retro={n_ret}, pv={n_pv}")


if __name__ == "__main__":
    main()
