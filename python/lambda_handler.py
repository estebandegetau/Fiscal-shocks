"""AWS Lambda handler for PyMuPDF PDF extraction with OCR.

This handler extracts text from PDFs using PyMuPDF with Tesseract OCR for scanned documents.
It downloads a PDF from a URL, extracts text page-by-page, and uploads the result to S3.

Environment Variables:
    S3_BUCKET: S3 bucket name for output (default: fiscal-shocks-pdfs)

Lambda Configuration:
    Runtime: Python 3.11
    Memory: 3GB (recommended for OCR)
    Timeout: 900 seconds (15 minutes - max for Lambda)
    Handler: lambda_handler.handler
"""

from __future__ import annotations

import json
import os
import tempfile
import urllib.request

import boto3
import pymupdf

# Set Tesseract data path for Lambda environment
# EPEL installs tessdata to /usr/share/tesseract/tessdata
if not os.environ.get("TESSDATA_PREFIX"):
    for tessdata_path in ["/usr/share/tesseract/tessdata", "/usr/share/tessdata"]:
        if os.path.exists(tessdata_path):
            os.environ["TESSDATA_PREFIX"] = tessdata_path
            break


def is_scanned_page(page: pymupdf.Page, min_text_chars: int = 100) -> bool:
    """Check if a page is scanned (image-based) and needs OCR.

    Args:
        page: PyMuPDF page object
        min_text_chars: Minimum characters to consider page as text-based

    Returns:
        True if page appears to be scanned and needs OCR
    """
    # Get text without OCR
    text = page.get_text()

    # Filter out common watermarks
    clean_text = text
    for watermark in ["Digitized for FRASER", "Federal Reserve Bank"]:
        clean_text = clean_text.replace(watermark, "")
    clean_text = clean_text.strip()

    # If very little text but page has images, it's likely scanned
    has_images = len(page.get_images()) > 0

    return len(clean_text) < min_text_chars and has_images


def extract_page_text(page: pymupdf.Page, use_ocr: bool = False, ocr_dpi: int = 200) -> str:
    """Extract text from a single page.

    Args:
        page: PyMuPDF page object
        use_ocr: Whether to use OCR
        ocr_dpi: DPI for OCR rendering

    Returns:
        Extracted text string
    """
    if use_ocr:
        try:
            tp = page.get_textpage_ocr(language="eng", dpi=ocr_dpi, full=True)
            return page.get_text(textpage=tp)
        except Exception as e:
            return f"[OCR Error: {e}]"
    else:
        return page.get_text()


def extract_pdf(pdf_path: str, ocr_dpi: int = 200) -> dict:
    """Extract text from PDF, using OCR for scanned pages.

    Args:
        pdf_path: Path to PDF file
        ocr_dpi: DPI for OCR rendering

    Returns:
        Dictionary with pages list and metadata
    """
    doc = pymupdf.open(pdf_path)
    n_pages = len(doc)

    # Check first few pages to determine if document is scanned
    sample_size = min(5, n_pages)
    scanned_count = sum(1 for i in range(sample_size) if is_scanned_page(doc[i]))
    is_scanned_doc = scanned_count >= sample_size / 2

    pages = []
    for i in range(n_pages):
        page = doc[i]
        # Use OCR for scanned documents or individual scanned pages
        use_ocr = is_scanned_doc or is_scanned_page(page)
        text = extract_page_text(page, use_ocr=use_ocr, ocr_dpi=ocr_dpi)
        pages.append(text)

    doc.close()

    return {
        "pages": pages,
        "n_pages": n_pages,
        "ocr_used": is_scanned_doc
    }


def handler(event, context):
    """AWS Lambda handler function.

    Expected event format:
    {
        "pdf_url": "https://example.com/document.pdf",
        "output_key": "extracted/2024/budget/document.json",
        "ocr_dpi": 200  # Optional, defaults to 200
    }

    Returns:
    {
        "statusCode": 200,
        "body": {
            "pages": ["page 1 text...", "page 2 text..."],
            "n_pages": 2,
            "ocr_used": true,
            "s3_key": "extracted/2024/budget/document.json",
            "error": null
        }
    }
    """
    # Get parameters from event
    pdf_url = event.get("pdf_url")
    output_key = event.get("output_key")
    ocr_dpi = event.get("ocr_dpi", 200)
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
        "n_pages": 0,
        "ocr_used": False,
        "error": None,
        "s3_key": output_key
    }

    try:
        # Download PDF to temporary file
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as temp_pdf:
            temp_pdf_path = temp_pdf.name

        try:
            urllib.request.urlretrieve(pdf_url, temp_pdf_path)

            # Extract text using PyMuPDF with OCR
            result = extract_pdf(temp_pdf_path, ocr_dpi=ocr_dpi)
            payload["pages"] = result["pages"]
            payload["n_pages"] = result["n_pages"]
            payload["ocr_used"] = result["ocr_used"]

        finally:
            # Clean up temp file
            if os.path.exists(temp_pdf_path):
                os.unlink(temp_pdf_path)

    except Exception as exc:
        payload["error"] = str(exc)
        payload["n_pages"] = 0
        payload["pages"] = []

    # Upload result to S3
    try:
        s3_client = boto3.client("s3")
        s3_client.put_object(
            Bucket=s3_bucket,
            Key=output_key,
            Body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            ContentType="application/json"
        )
    except Exception as s3_exc:
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
        "output_key": sys.argv[2]
    }

    result = handler(test_event, None)
    print(json.dumps(json.loads(result["body"]), indent=2))
