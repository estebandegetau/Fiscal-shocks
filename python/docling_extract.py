"""CLI entrypoint: parse args, run Docling extraction, dump JSON output."""

from __future__ import annotations

import argparse
import json


def _pages_from_export_dict(doc_dict: dict) -> list[str]:
    # Normalize Docling’s dict export so each page becomes a string of text.
    pages = doc_dict.get("pages")
    if not isinstance(pages, list) or not pages:
        return []

    out: list[str] = []
    for page in pages:
        if not isinstance(page, dict):
            continue
        text = page.get("text")
        if isinstance(text, str):
            out.append(text)
            continue
        lines = page.get("lines")
        if isinstance(lines, list):
            line_texts = []
            for line in lines:
                if isinstance(line, dict) and isinstance(line.get("text"), str):
                    line_texts.append(line["text"])
            out.append("\n".join(line_texts))
            continue
        out.append("")
    return out


def _extract_pages_with_docling(pdf_path: str, *, do_table_structure: bool = True) -> list[str]:
    # Late imports keep the CLI lightweight when Docling is unused.
    from docling.backend.pypdfium2_backend import PyPdfiumDocumentBackend
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions
    from docling.document_converter import DocumentConverter, PdfFormatOption

    # Configure the PDF pipeline: OCR off, optional table structure, disable cell matching.
    pipeline_options = PdfPipelineOptions()
    pipeline_options.do_ocr = False
    pipeline_options.do_table_structure = bool(do_table_structure)
    if hasattr(pipeline_options, "table_structure_options"):
        pipeline_options.table_structure_options.do_cell_matching = True

    # Build a converter that forces the PyPDFium backend with the custom options.
    converter = DocumentConverter(
        format_options={
            InputFormat.PDF: PdfFormatOption(
                pipeline_options=pipeline_options, backend=PyPdfiumDocumentBackend
            )
        }
    )

    # Run conversion and get the document object for downstream exports.
    result = converter.convert(pdf_path)
    document = result.document

    # Prefer the dict export so we can stitch page text directly.
    export_dict = None
    export_to_dict = getattr(document, "export_to_dict", None)
    if callable(export_to_dict):
        try:
            export_dict = export_to_dict()
        except Exception:  # noqa: BLE001
            export_dict = None

    if isinstance(export_dict, dict):
        pages = _pages_from_export_dict(export_dict)
        if pages:
            return pages

    # Fall back to Markdown export if the dict path failed.
    export = getattr(document, "export_to_markdown", None)
    if callable(export):
        try:
            exported = export(strict_text=True)
        except TypeError:
            exported = export()
        if isinstance(exported, str) and exported.strip():
            return [exported]

    # Propagate an explicit failure so callers can log/report it.
    raise RuntimeError("Docling produced no extractable text.")


def main() -> int:
    # Parse CLI arguments for input PDF, output JSON, and table-structure toggle.
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--no-table-structure",
        dest="do_table_structure",
        action="store_false",
        default=True,
    )
    args = parser.parse_args()

    # Execute extraction and capture either the page list or the error message.
    payload: dict = {"pages": [], "error": None}
    try:
        payload["pages"] = _extract_pages_with_docling(
            args.input, do_table_structure=args.do_table_structure
        )
    except Exception as exc:  # noqa: BLE001
        payload["error"] = str(exc)

    # Persist the payload as UTF-8 JSON for downstream consumers.
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
