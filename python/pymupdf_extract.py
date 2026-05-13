#!/usr/bin/env python3
"""
PDF text extraction using PyMuPDF with per-page OCR rescue for scanned pages.

The pipeline first extracts native text for every page (cheap; microseconds
per page). Pages where native text is shorter than `ocr_min_chars` AND that
contain at least one embedded image are flagged for OCR rescue and re-extracted
via Tesseract through `page.get_textpage_ocr`. This handles mixed-content
PDFs — common in emerging-market fiscal archives — where some pages are
text-extractable and others are scanned image inserts.

Usage:
    python pymupdf_extract.py --input <pdf_path> --output <json_output>
    python pymupdf_extract.py --input <pdf_url> --output <json_output>
    python pymupdf_extract.py --input <pdf_path> --output <json_output> --force-ocr

Output JSON structure:
{
    "text": "Full document text...",
    "pages": ["Page 1 text...", "Page 2 text...", ...],
    "pages_ocr": [false, false, true, true, ..., false],
    "n_pages": 300,
    "n_pages_ocr": 42,
    "ocr_used": true,
    "extraction_time_seconds": 120.5,
    "extracted_at": "2026-01-15T00:00:00"
}
"""

import argparse
import json
import shutil
import sys
import tempfile
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from urllib.request import urlretrieve

import pymupdf


OCR_MIN_CHARS_DEFAULT = 100


def download_pdf(url: str) -> str:
    """Download PDF from URL to temporary file."""
    suffix = ".pdf"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
        temp_path = f.name
    urlretrieve(url, temp_path)
    return temp_path


def _clean_native_text(text: str) -> str:
    """Strip known boilerplate watermarks before measuring page text density."""
    return (
        text.replace("Digitized for FRASER", "")
            .replace("Federal Reserve Bank", "")
            .strip()
    )


def should_rescue_page(page: pymupdf.Page, native_text: str,
                       ocr_min_chars: int) -> bool:
    """
    Decide whether a single page needs OCR rescue.

    A page qualifies when native extraction returned almost no text AND the
    page contains at least one embedded image — the signature of a scanned
    insert (chart, plate, photograph of a printed page) embedded inside an
    otherwise text-extractable document.

    Cosmetic short pages with no image (covers, chapter dividers) are skipped:
    they have no extractable content for OCR to recover.
    """
    clean = _clean_native_text(native_text)
    return len(clean) < ocr_min_chars and len(page.get_images()) > 0


def extract_page_with_ocr(args: tuple) -> tuple[int, str, bool]:
    """
    OCR a single page; return (page_num, ocr_text, ocr_failed).

    On Tesseract / Leptonica error, returns (page_num, native_fallback, True)
    so the caller can preserve the original native text instead of writing an
    error sentinel into the document.
    """
    pdf_path, page_num, dpi, native_fallback = args
    doc = pymupdf.open(pdf_path)
    page = doc[page_num]

    try:
        tp = page.get_textpage_ocr(language="eng+msa", dpi=dpi, full=True)
        text = page.get_text(textpage=tp)
        ocr_failed = False
    except Exception as e:
        print(f"  OCR failed on page {page_num + 1}: {e}", file=sys.stderr)
        text = native_fallback
        ocr_failed = True

    doc.close()
    return page_num, text, ocr_failed


def extract_page_text(doc: pymupdf.Document, page_num: int) -> str:
    """Extract text from a single page without OCR."""
    page = doc[page_num]
    return page.get_text()


def extract_pdf(pdf_path: str, force_ocr: bool = False, ocr_dpi: int = 200,
                max_workers: int = 4, ocr_min_chars: int = OCR_MIN_CHARS_DEFAULT,
                progress_callback=None) -> dict:
    """
    Extract text from PDF with per-page OCR rescue.

    Step 1: cheap serial pass — native text extraction for every page.
    Step 2: identify pages needing OCR rescue (short native text + has image,
            or all pages if force_ocr=True).
    Step 3: run OCR in parallel over only the rescue pages, replacing native
            text on success; preserving native text on per-page OCR failure.

    Args:
        pdf_path: Path to PDF file
        force_ocr: Force OCR rescue on every page (overrides per-page predicate)
        ocr_dpi: DPI for OCR rendering (higher = better quality but slower)
        max_workers: Number of parallel workers for OCR
        ocr_min_chars: Per-page native-text threshold below which OCR rescue
                       is considered (only fires if the page also has images)
        progress_callback: Optional callback(current, total) for OCR progress

    Returns:
        Dictionary with extracted text, per-page text, per-page OCR flags,
        and metadata. `ocr_used` is the document-level summary (any page OCR'd).
    """
    start_time = time.time()

    doc = pymupdf.open(pdf_path)
    n_pages = len(doc)

    if n_pages == 0:
        doc.close()
        return {
            "text": "",
            "pages": [],
            "pages_ocr": [],
            "n_pages": 0,
            "n_pages_ocr": 0,
            "ocr_used": False,
            "extraction_time_seconds": round(time.time() - start_time, 2),
            "extracted_at": datetime.now().isoformat(),
        }

    # Step 1: serial native-text pass (microseconds per page)
    pages_text = [extract_page_text(doc, i) for i in range(n_pages)]

    # Step 2: identify rescue pages
    if force_ocr:
        rescue_indices = list(range(n_pages))
    else:
        rescue_indices = [
            i for i in range(n_pages)
            if should_rescue_page(doc[i], pages_text[i], ocr_min_chars)
        ]

    pages_ocr = [False] * n_pages

    # Step 3: OCR rescue (only if any page qualifies)
    if rescue_indices:
        if shutil.which("tesseract") is None:
            doc.close()
            print(
                f"ERROR: OCR rescue required for {len(rescue_indices)} page(s) "
                f"of {pdf_path} but `tesseract` is not on PATH. Install "
                "tesseract-ocr + tesseract-ocr-eng + tesseract-ocr-msa and "
                "set TESSDATA_PREFIX.",
                file=sys.stderr,
            )
            sys.exit(2)

        print(
            f"OCR rescue: {len(rescue_indices)}/{n_pages} pages of {pdf_path}",
            file=sys.stderr,
        )
        doc.close()

        args_list = [
            (pdf_path, i, ocr_dpi, pages_text[i]) for i in rescue_indices
        ]
        completed = 0
        with ProcessPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(extract_page_with_ocr, args): args[1]
                for args in args_list
            }
            for future in as_completed(futures):
                page_num, text, ocr_failed = future.result()
                pages_text[page_num] = text
                # Count only successful OCRs in pages_ocr — failures preserved
                # the native text, so it's misleading to mark them as OCR'd.
                pages_ocr[page_num] = not ocr_failed
                completed += 1

                if progress_callback:
                    progress_callback(completed, len(rescue_indices))
                elif completed % 10 == 0 or completed == len(rescue_indices):
                    print(
                        f"  OCR progress: {completed}/{len(rescue_indices)} pages",
                        file=sys.stderr,
                    )
    else:
        print(
            f"Native extraction only: 0/{n_pages} pages needed OCR rescue "
            f"({pdf_path})",
            file=sys.stderr,
        )
        doc.close()

    full_text = "\n\n".join(pages_text)
    n_pages_ocr = sum(pages_ocr)
    elapsed = time.time() - start_time

    return {
        "text": full_text,
        "pages": pages_text,
        "pages_ocr": pages_ocr,
        "n_pages": n_pages,
        "n_pages_ocr": n_pages_ocr,
        "ocr_used": n_pages_ocr > 0,
        "extraction_time_seconds": round(elapsed, 2),
        "extracted_at": datetime.now().isoformat(),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Extract text from PDF using PyMuPDF with per-page OCR rescue"
    )
    parser.add_argument(
        "--input", "-i",
        required=True,
        help="Path to PDF file or URL"
    )
    parser.add_argument(
        "--output", "-o",
        help="Output JSON file path (default: stdout)"
    )
    parser.add_argument(
        "--force-ocr",
        action="store_true",
        help="Force OCR rescue on every page (overrides per-page predicate)"
    )
    parser.add_argument(
        "--ocr-dpi",
        type=int,
        default=200,
        help="DPI for OCR rendering (default: 200)"
    )
    parser.add_argument(
        "--ocr-min-chars",
        type=int,
        default=OCR_MIN_CHARS_DEFAULT,
        help=(
            "Per-page native-text threshold below which OCR rescue is "
            f"considered, when the page also has images (default: {OCR_MIN_CHARS_DEFAULT})"
        ),
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=4,
        help="Number of parallel workers for OCR (default: 4)"
    )

    args = parser.parse_args()

    pdf_path = args.input
    temp_file = None

    if pdf_path.startswith(("http://", "https://")):
        print(f"Downloading PDF from {pdf_path}...", file=sys.stderr)
        temp_file = download_pdf(pdf_path)
        pdf_path = temp_file

    if not Path(pdf_path).exists():
        print(f"Error: File not found: {pdf_path}", file=sys.stderr)
        sys.exit(1)

    try:
        print(f"Extracting text from {pdf_path}...", file=sys.stderr)
        result = extract_pdf(
            pdf_path,
            force_ocr=args.force_ocr,
            ocr_dpi=args.ocr_dpi,
            max_workers=args.workers,
            ocr_min_chars=args.ocr_min_chars,
        )
        print(
            f"Extracted {result['n_pages']} pages "
            f"({result['n_pages_ocr']} OCR-rescued) "
            f"in {result['extraction_time_seconds']}s",
            file=sys.stderr,
        )

        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(result, f, ensure_ascii=False, indent=2)
            print(f"Output written to {args.output}", file=sys.stderr)
        else:
            output = {k: v for k, v in result.items() if k != "pages"}
            output["text_preview"] = (
                result["text"][:2000] + "..."
                if len(result["text"]) > 2000
                else result["text"]
            )
            print(json.dumps(output, ensure_ascii=False, indent=2))

    finally:
        if temp_file and Path(temp_file).exists():
            Path(temp_file).unlink()


if __name__ == "__main__":
    main()
