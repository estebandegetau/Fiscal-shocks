#!/usr/bin/env python3
"""
PDF text extraction using PyMuPDF with OCR support for scanned documents.

This script extracts text from PDFs, automatically detecting whether OCR is needed
for scanned documents. Produces clean text output optimized for LLM consumption.

Usage:
    python pymupdf_extract.py --input <pdf_path> --output <json_output>
    python pymupdf_extract.py --input <pdf_url> --output <json_output>
    python pymupdf_extract.py --input <pdf_path> --output <json_output> --force-ocr

Output JSON structure:
{
    "text": "Full document text...",
    "pages": ["Page 1 text...", "Page 2 text...", ...],
    "n_pages": 300,
    "ocr_used": true,
    "extraction_time_seconds": 120.5,
    "extracted_at": "2026-01-15T00:00:00"
}
"""

import argparse
import json
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from urllib.request import urlretrieve

import pymupdf


def download_pdf(url: str) -> str:
    """Download PDF from URL to temporary file."""
    suffix = ".pdf"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
        temp_path = f.name
    urlretrieve(url, temp_path)
    return temp_path


def is_scanned_document(doc: pymupdf.Document, sample_pages: int = 5) -> bool:
    """
    Detect if PDF is a scanned document that needs OCR.

    Checks if pages have very little text but contain images.
    """
    text_chars = 0
    image_count = 0
    pages_to_check = min(sample_pages, len(doc))

    for i in range(pages_to_check):
        page = doc[i]
        text = page.get_text()
        images = page.get_images()

        # Exclude common watermarks/headers from character count
        clean_text = text.replace("Digitized for FRASER", "").replace("Federal Reserve Bank", "").strip()
        text_chars += len(clean_text)
        image_count += len(images)

    # If average text per page is very low and images are present, it's likely scanned
    avg_chars_per_page = text_chars / pages_to_check
    has_images = image_count > 0

    # Threshold: less than 500 chars average per page with images = scanned
    return avg_chars_per_page < 500 and has_images


def extract_page_with_ocr(args: tuple) -> tuple[int, str]:
    """Extract text from a single page using OCR. Used for parallel processing."""
    pdf_path, page_num, dpi = args
    doc = pymupdf.open(pdf_path)
    page = doc[page_num]

    try:
        tp = page.get_textpage_ocr(language="eng", dpi=dpi, full=True)
        text = page.get_text(textpage=tp)
    except Exception as e:
        text = f"[OCR Error on page {page_num + 1}: {e}]"

    doc.close()
    return page_num, text


def extract_page_text(doc: pymupdf.Document, page_num: int) -> str:
    """Extract text from a single page without OCR."""
    page = doc[page_num]
    return page.get_text()


def extract_pdf(pdf_path: str, force_ocr: bool = False, ocr_dpi: int = 200,
                max_workers: int = 4, progress_callback=None) -> dict:
    """
    Extract text from PDF, using OCR if needed for scanned documents.

    Args:
        pdf_path: Path to PDF file
        force_ocr: Force OCR even for text-based PDFs
        ocr_dpi: DPI for OCR (higher = better quality but slower)
        max_workers: Number of parallel workers for OCR
        progress_callback: Optional callback(current, total) for progress

    Returns:
        Dictionary with extracted text, pages, and metadata
    """
    start_time = time.time()

    doc = pymupdf.open(pdf_path)
    n_pages = len(doc)

    # Detect if OCR is needed
    use_ocr = force_ocr or is_scanned_document(doc)

    if use_ocr:
        print(f"Scanned document detected - using OCR ({n_pages} pages)...", file=sys.stderr)
        doc.close()

        # Use parallel OCR for scanned documents
        pages_text = [""] * n_pages
        args_list = [(pdf_path, i, ocr_dpi) for i in range(n_pages)]

        completed = 0
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {executor.submit(extract_page_with_ocr, args): args[1]
                      for args in args_list}

            for future in as_completed(futures):
                page_num, text = future.result()
                pages_text[page_num] = text
                completed += 1

                if progress_callback:
                    progress_callback(completed, n_pages)
                elif completed % 10 == 0 or completed == n_pages:
                    print(f"  OCR progress: {completed}/{n_pages} pages", file=sys.stderr)
    else:
        print(f"Text-based PDF - extracting directly ({n_pages} pages)...", file=sys.stderr)
        pages_text = []
        for i in range(n_pages):
            pages_text.append(extract_page_text(doc, i))
        doc.close()

    # Combine pages into full text with page separators
    full_text = "\n\n".join(pages_text)

    elapsed = time.time() - start_time

    return {
        "text": full_text,
        "pages": pages_text,
        "n_pages": n_pages,
        "ocr_used": use_ocr,
        "extraction_time_seconds": round(elapsed, 2),
        "extracted_at": datetime.now().isoformat()
    }


def main():
    parser = argparse.ArgumentParser(
        description="Extract text from PDF using PyMuPDF with OCR support"
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
        help="Force OCR even for text-based PDFs"
    )
    parser.add_argument(
        "--ocr-dpi",
        type=int,
        default=200,
        help="DPI for OCR rendering (default: 200)"
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=4,
        help="Number of parallel workers for OCR (default: 4)"
    )

    args = parser.parse_args()

    # Handle URL vs local file
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
            max_workers=args.workers
        )
        print(f"Extracted {result['n_pages']} pages in {result['extraction_time_seconds']}s", file=sys.stderr)
        print(f"OCR used: {result['ocr_used']}", file=sys.stderr)

        # Output result (exclude pages array for stdout to keep it manageable)
        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(result, f, ensure_ascii=False, indent=2)
            print(f"Output written to {args.output}", file=sys.stderr)
        else:
            # For stdout, just output summary without full pages array
            output = {k: v for k, v in result.items() if k != "pages"}
            output["text_preview"] = result["text"][:2000] + "..." if len(result["text"]) > 2000 else result["text"]
            print(json.dumps(output, ensure_ascii=False, indent=2))

    finally:
        # Clean up temp file if we downloaded
        if temp_file and Path(temp_file).exists():
            Path(temp_file).unlink()


if __name__ == "__main__":
    main()
