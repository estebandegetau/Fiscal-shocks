"""AWS Lambda handler for Docling PDF extraction.

This handler is designed to run in AWS Lambda and extract text from PDFs using Docling.
It downloads a PDF from a URL, extracts text page-by-page, and uploads the result to S3.

Environment Variables:
    S3_BUCKET: S3 bucket name for output (default: fiscal-shocks-pdfs)
    DO_TABLE_STRUCTURE: Enable table structure extraction (default: true)

Lambda Configuration:
    Runtime: Python 3.11
    Memory: 3GB
    Timeout: 300 seconds (5 minutes)
    Handler: lambda_handler.handler
"""

from __future__ import annotations

import json
import os
import tempfile
import urllib.request
from pathlib import Path

# Set cache directories to /tmp for Lambda's read-only filesystem
# Must be done BEFORE importing libraries that use these
os.environ.setdefault("HOME", "/tmp")
os.environ.setdefault("HF_HOME", "/tmp/hf_cache")
os.environ.setdefault("TRANSFORMERS_CACHE", "/tmp/hf_cache")
os.environ.setdefault("TORCH_HOME", "/tmp/torch_cache")
os.environ.setdefault("XDG_CACHE_HOME", "/tmp/cache")

# Import boto3 for S3 (available in Lambda runtime)
try:
    import boto3
except ImportError:
    boto3 = None


def _pages_from_export_dict(doc_dict: dict) -> list[str]:
    """Extract page text from Docling's dict export format.

    Args:
        doc_dict: Docling document.export_to_dict() output

    Returns:
        List of page text strings
    """
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


def _extract_tables_from_document(document) -> list[dict]:
    """Extract structured table data from Docling document.

    Args:
        document: Docling document object

    Returns:
        List of table dictionaries with structure:
        {
            "page": int,
            "table_id": str,
            "markdown": str,  # Table as markdown for LLM consumption
            "cells": [{"row": int, "col": int, "text": str, "is_header": bool}],
            "num_rows": int,
            "num_cols": int
        }
    """
    tables = []

    # Try to get tables from document
    try:
        # Docling stores tables in document.tables or via iterate_items
        doc_tables = getattr(document, "tables", None)
        if doc_tables is None:
            # Try alternative access via iterate_items
            iterate_items = getattr(document, "iterate_items", None)
            if callable(iterate_items):
                doc_tables = [
                    item for item in iterate_items()
                    if hasattr(item, "__class__") and "table" in item.__class__.__name__.lower()
                ]

        if not doc_tables:
            return []

        for idx, table in enumerate(doc_tables):
            table_data = {
                "table_id": f"table_{idx}",
                "page": getattr(table, "page_no", None) or getattr(table, "page", None),
                "markdown": "",
                "cells": [],
                "num_rows": 0,
                "num_cols": 0,
            }

            # Try to export table as markdown (best for LLM consumption)
            export_md = getattr(table, "export_to_markdown", None)
            if callable(export_md):
                try:
                    table_data["markdown"] = export_md()
                except Exception:
                    pass

            # Try to get structured cell data
            table_cells = getattr(table, "cells", None) or getattr(table, "data", None)
            if table_cells:
                cells = []
                max_row, max_col = 0, 0
                for cell in table_cells:
                    if isinstance(cell, dict):
                        row = cell.get("row", cell.get("row_idx", 0))
                        col = cell.get("col", cell.get("col_idx", 0))
                        text = cell.get("text", cell.get("content", ""))
                        is_header = cell.get("is_header", cell.get("header", False))
                    else:
                        row = getattr(cell, "row", getattr(cell, "row_idx", 0))
                        col = getattr(cell, "col", getattr(cell, "col_idx", 0))
                        text = getattr(cell, "text", getattr(cell, "content", ""))
                        is_header = getattr(cell, "is_header", getattr(cell, "header", False))

                    cells.append({
                        "row": row,
                        "col": col,
                        "text": str(text) if text else "",
                        "is_header": bool(is_header)
                    })
                    max_row = max(max_row, row)
                    max_col = max(max_col, col)

                table_data["cells"] = cells
                table_data["num_rows"] = max_row + 1
                table_data["num_cols"] = max_col + 1

            # Only include tables with actual content
            if table_data["markdown"] or table_data["cells"]:
                tables.append(table_data)

    except Exception:  # noqa: BLE001
        # Table extraction is best-effort; don't fail the whole document
        pass

    return tables


def _extract_pages_with_docling(pdf_path: str, *, do_table_structure: bool = True) -> dict:
    """Extract text and tables from PDF using Docling.

    Args:
        pdf_path: Local path to PDF file
        do_table_structure: Enable table structure extraction

    Returns:
        Dictionary with:
        - "pages": List of page text strings
        - "tables": List of structured table dictionaries (for Model C)

    Raises:
        RuntimeError: If extraction fails
    """
    # Late imports to keep Lambda cold start fast
    from docling.backend.pypdfium2_backend import PyPdfiumDocumentBackend
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions
    from docling.document_converter import DocumentConverter, PdfFormatOption

    # Configure pipeline: no OCR, optional table structure, enable cell matching
    pipeline_options = PdfPipelineOptions()
    pipeline_options.do_ocr = False
    pipeline_options.do_table_structure = bool(do_table_structure)
    if hasattr(pipeline_options, "table_structure_options"):
        pipeline_options.table_structure_options.do_cell_matching = True

    # Build converter with PyPDFium backend
    converter = DocumentConverter(
        format_options={
            InputFormat.PDF: PdfFormatOption(
                pipeline_options=pipeline_options, backend=PyPdfiumDocumentBackend
            )
        }
    )

    # Convert PDF
    result = converter.convert(pdf_path)
    document = result.document

    # Extract structured tables (for Model C - information extraction)
    tables = []
    if do_table_structure:
        tables = _extract_tables_from_document(document)

    # Prefer dict export for page-by-page text
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
            return {"pages": pages, "tables": tables}

    # Fallback to markdown export
    export = getattr(document, "export_to_markdown", None)
    if callable(export):
        try:
            exported = export(strict_text=True)
        except TypeError:
            exported = export()
        if isinstance(exported, str) and exported.strip():
            return {"pages": [exported], "tables": tables}

    raise RuntimeError("Docling produced no extractable text.")


def handler(event, context):
    """AWS Lambda handler function.

    Expected event format:
    {
        "pdf_url": "https://example.com/document.pdf",
        "output_key": "extracted/2024/budget/document.json",  # S3 key for output
        "do_table_structure": true  # Optional, defaults to true
    }

    Returns:
    {
        "statusCode": 200,
        "body": {
            "pages": ["page 1 text...", "page 2 text..."],
            "tables": [  # Structured tables for Model C (information extraction)
                {
                    "table_id": "table_0",
                    "page": 45,
                    "markdown": "| Year | Revenue |...",
                    "cells": [{"row": 0, "col": 0, "text": "Year", "is_header": true}],
                    "num_rows": 10,
                    "num_cols": 5
                }
            ],
            "n_pages": 2,
            "n_tables": 1,
            "s3_key": "extracted/2024/budget/document.json",
            "error": null
        }
    }
    """
    # Get parameters from event
    pdf_url = event.get("pdf_url")
    output_key = event.get("output_key")
    do_table_structure = event.get("do_table_structure", True)
    s3_bucket = os.environ.get("S3_BUCKET", "fiscal-shocks-pdfs")

    if not pdf_url or not output_key:
        return {
            "statusCode": 400,
            "body": json.dumps({
                "error": "Missing required parameters: pdf_url and output_key"
            })
        }

    # Initialize response payload
    payload = {
        "pages": [],
        "tables": [],
        "n_pages": 0,
        "n_tables": 0,
        "error": None,
        "s3_key": output_key
    }

    try:
        # Download PDF to temporary file
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as temp_pdf:
            temp_pdf_path = temp_pdf.name

        try:
            urllib.request.urlretrieve(pdf_url, temp_pdf_path)

            # Extract text and tables using Docling
            result = _extract_pages_with_docling(temp_pdf_path, do_table_structure=do_table_structure)
            payload["pages"] = result["pages"]
            payload["tables"] = result["tables"]
            payload["n_pages"] = len(result["pages"])
            payload["n_tables"] = len(result["tables"])

        finally:
            # Clean up temp file
            if os.path.exists(temp_pdf_path):
                os.unlink(temp_pdf_path)

    except Exception as exc:  # noqa: BLE001
        payload["error"] = str(exc)
        payload["n_pages"] = 0
        payload["n_tables"] = 0
        payload["pages"] = []
        payload["tables"] = []

    # Upload result to S3
    if boto3 is not None:
        try:
            s3_client = boto3.client("s3")
            s3_client.put_object(
                Bucket=s3_bucket,
                Key=output_key,
                Body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                ContentType="application/json"
            )
        except Exception as s3_exc:  # noqa: BLE001
            # If S3 upload fails, include in error but still return payload
            if payload["error"]:
                payload["error"] += f"; S3 upload failed: {s3_exc}"
            else:
                payload["error"] = f"S3 upload failed: {s3_exc}"

    return {
        "statusCode": 200 if not payload["error"] else 500,
        "body": json.dumps(payload)
    }


if __name__ == "__main__":
    # Local testing
    import sys
    if len(sys.argv) < 3:
        print("Usage: python lambda_handler.py <pdf_url> <output_key>")
        sys.exit(1)

    test_event = {
        "pdf_url": sys.argv[1],
        "output_key": sys.argv[2],
        "do_table_structure": True
    }

    result = handler(test_event, None)
    print(json.dumps(result, indent=2))
