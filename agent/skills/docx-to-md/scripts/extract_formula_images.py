#!/usr/bin/env python3
"""
Automated High-Fidelity Formula Image Extractor for AI Visual Grounding & LaTeX Correction.
Pipeline:
1. Converts .docx -> .pdf using headless LibreOffice (preserves all MathType/Euclid/MT Extra vector fonts).
2. Uses PyMuPDF (fitz) to identify formula-heavy pages and renders them at 300 DPI PNG.
3. Automatically scans equation numbering tags (e.g. (5.1-1), (1), [2.3]) and crops tight formula bounding boxes.
"""

import os
import sys
import re
import argparse
import subprocess
import pymupdf

def docx_to_pdf(docx_path, output_pdf=None):
    if output_pdf is None:
        output_pdf = os.path.splitext(docx_path)[0] + ".pdf"
    
    outdir = os.path.dirname(os.path.abspath(output_pdf)) or "."
    cmd = ["soffice", "--headless", "--convert-to", "pdf", docx_path, "--outdir", outdir]
    print(f"[*] Converting '{docx_path}' to PDF via LibreOffice...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[-] LibreOffice conversion failed:\n{res.stderr}", file=sys.stderr)
        sys.exit(1)
    
    expected_pdf = os.path.join(outdir, os.path.splitext(os.path.basename(docx_path))[0] + ".pdf")
    if expected_pdf != output_pdf and os.path.exists(expected_pdf):
        os.rename(expected_pdf, output_pdf)
    
    print(f"[+] Generated PDF: '{output_pdf}'")
    return output_pdf

def extract_formula_images(pdf_path, out_dir="formula_images", dpi_scale=3.0, crop_equations=True):
    os.makedirs(out_dir, exist_ok=True)
    crops_dir = os.path.join(out_dir, "crops")
    if crop_equations:
        os.makedirs(crops_dir, exist_ok=True)

    doc = pymupdf.open(pdf_path)
    print(f"[*] Analyzing {len(doc)} pages in '{pdf_path}' at {int(dpi_scale*100)} DPI...")

    # Pattern for equation numbering like (1), (5.1-1), （5.1-1）, [1.2]
    eq_pattern = re.compile(r'（(\d+(?:[\.\-]\d+)*)）|\((\d+(?:[\.\-]\d+)*)\)')
    
    # Common math symbols / keywords indicating math-heavy pages
    math_indicators = ['min', 'max', 's.t.', '∑', '∈', '≤', '≥', '∏', '∫', 'lim', '符号说明', '集合划分']

    rendered_pages = 0
    cropped_equations = 0

    for page_idx, page in enumerate(doc):
        text = page.get_text()
        blocks = page.get_text("blocks")
        
        # Check if page contains math indicators or equation numbers
        has_math = any(ind in text for ind in math_indicators) or eq_pattern.search(text)
        
        if has_math:
            # 1. Render full page at 300 DPI
            pix = page.get_pixmap(matrix=pymupdf.Matrix(dpi_scale, dpi_scale))
            page_png = os.path.join(out_dir, f"page_{page_idx+1:02d}_formula.png")
            pix.save(page_png)
            rendered_pages += 1
            print(f"  [+] Page {page_idx+1:02d} rendered -> {page_png}")

        # 2. Crop individual equations if enabled
        if crop_equations:
            for b in blocks:
                block_text = b[4].strip()
                match = eq_pattern.search(block_text)
                if match:
                    tag = match.group(1) or match.group(2)
                    y0, y1 = b[1], b[3]
                    # Expand horizontally across full text margin
                    crop_rect = pymupdf.Rect(40, max(0, y0 - 15), page.rect.width - 40, min(page.rect.height, y1 + 15))
                    crop_pix = page.get_pixmap(clip=crop_rect, matrix=pymupdf.Matrix(dpi_scale, dpi_scale))
                    crop_png = os.path.join(crops_dir, f"eq_{tag}.png")
                    crop_pix.save(crop_png)
                    cropped_equations += 1
                    print(f"      -> Cropped Eq ({tag}) on Page {page_idx+1:02d} -> {crop_png}")

    print(f"\n[✓] Done! Saved {rendered_pages} full formula pages and {cropped_equations} equation crops in '{out_dir}/'.")

def main():
    parser = argparse.ArgumentParser(description="Extract high-res formula images and equation crops from DOCX/PDF for AI LaTeX correction.")
    parser.add_argument("input_file", help="Path to .docx or .pdf file")
    parser.add_argument("--out-dir", default="pdf_formula_pages", help="Output directory for PNG images (default: pdf_formula_pages)")
    parser.add_argument("--dpi", type=float, default=3.0, help="DPI scale factor (3.0 = 300 DPI, default: 3.0)")
    parser.add_argument("--no-crops", action="store_true", help="Skip individual equation bounding-box crops")
    args = parser.parse_args()

    input_file = args.input_file
    if not os.path.exists(input_file):
        print(f"Error: File '{input_file}' not found.", file=sys.stderr)
        sys.exit(1)

    if input_file.lower().endswith(".docx"):
        pdf_path = docx_to_pdf(input_file)
    elif input_file.lower().endswith(".pdf"):
        pdf_path = input_file
    else:
        print(f"Error: Input file must be .docx or .pdf, got '{input_file}'", file=sys.stderr)
        sys.exit(1)

    extract_formula_images(pdf_path, out_dir=args.out_dir, dpi_scale=args.dpi, crop_equations=not args.no_crops)

if __name__ == '__main__':
    main()
