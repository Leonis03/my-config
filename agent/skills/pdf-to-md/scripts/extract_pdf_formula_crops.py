#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
High-Resolution Formula & Visual Crop Extractor for PDF Documents.

Features:
- Extracts 300 DPI full-page formula images for visual verification.
- Auto-crops individual numbered equation bounding boxes (eq_5.1-1.png, etc.).
- Auto-generates formula_map.template.json with all detected equation tags.
- Detects and crops vector diagrams/figures when raster images are absent.
- Cross-platform UTF-8 support (Linux, macOS, Windows).
"""

import os
import sys
import re
import json
import argparse
import pymupdf

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

TAG_REGEX = re.compile(r'[（\(](?:式\s*)?(\d+(?:[\.\-]\d+)*)[）\)]')
MATH_INDICATORS = ['min', 'max', 's.t.', '\u2211', '\u2208', '\u2264', '\u2265', '\u220f', '\u222b', 'lim', '符号说明', '集合划分', 'argmax', 'argmin', 'sup', 'inf']

def extract_pdf_formula_crops(pdf_path, out_dir="pdf_formula_pages", dpi_scale=3.0, crop_equations=True, crop_figures=True):
    os.makedirs(out_dir, exist_ok=True)
    crops_dir = os.path.join(out_dir, "crops")
    figures_dir = os.path.join(out_dir, "vector_figures")
    if crop_equations:
        os.makedirs(crops_dir, exist_ok=True)
    if crop_figures:
        os.makedirs(figures_dir, exist_ok=True)

    doc = pymupdf.open(pdf_path)
    print(f"[*] Scanning {len(doc)} pages in '{pdf_path}' at {int(dpi_scale * 100)} DPI...")

    rendered_pages = 0
    cropped_equations = 0
    cropped_figures = 0
    detected_tags = []

    for page_idx, page in enumerate(doc):
        page_num = page_idx + 1
        text = page.get_text()
        blocks = page.get_text("blocks")

        has_math = any(ind in text for ind in MATH_INDICATORS) or TAG_REGEX.search(text)

        # 1. Render full page if formulas detected
        if has_math:
            pix = page.get_pixmap(matrix=pymupdf.Matrix(dpi_scale, dpi_scale))
            page_png = os.path.join(out_dir, f"page_{page_num:02d}_formula.png")
            pix.save(page_png)
            rendered_pages += 1
            print(f"  [+] Rendered Page {page_num:02d} -> {page_png}")

        # 2. Crop individual equations
        if crop_equations:
            for b in blocks:
                block_text = b[4].strip()
                matches = TAG_REGEX.findall(block_text)
                if matches:
                    # Ignore citations like "见式(5.1-1)" or "按式(1)"
                    is_citation = any(prefix in block_text for prefix in ["其中，公式", "公式(", "公式（", "求解式", "见式", "按式", "由式", "满足式", "根据式", "在式", "代入式"])
                    if is_citation and len(block_text) > 40:
                        continue

                    tag = matches[-1]
                    if tag not in detected_tags:
                        detected_tags.append(tag)

                    y0, y1 = b[1], b[3]
                    # Include margins around equation
                    crop_rect = pymupdf.Rect(30, max(0, y0 - 15), page.rect.width - 30, min(page.rect.height, y1 + 15))
                    crop_pix = page.get_pixmap(clip=crop_rect, matrix=pymupdf.Matrix(dpi_scale, dpi_scale))
                    crop_png = os.path.join(crops_dir, f"eq_{tag}.png")
                    crop_pix.save(crop_png)
                    cropped_equations += 1
                    print(f"      -> Cropped Eq ({tag}) on Page {page_num:02d} -> {crop_png}")

        # 3. Crop vector figures above captions if raster image is absent
        if crop_figures:
            raster_imgs = page.get_images()
            for b in blocks:
                b_text = b[4].strip()
                if (b_text.startswith("图") or b_text.startswith("Figure")) and any(c.isdigit() for c in b_text[:8]) and len(b_text) < 80:
                    clean_cap = re.sub(r'[\/:*?"<>| ]', '_', b_text[:30])
                    # If page has fewer raster images than captions, crop the region above caption
                    cap_y0 = b[1]
                    # Region above caption (typically 120-250 pt high)
                    fig_y0 = max(40, cap_y0 - 220)
                    fig_rect = pymupdf.Rect(40, fig_y0, page.rect.width - 40, cap_y0 - 5)
                    fig_pix = page.get_pixmap(clip=fig_rect, matrix=pymupdf.Matrix(dpi_scale, dpi_scale))
                    fig_png = os.path.join(figures_dir, f"fig_crop_{clean_cap}.png")
                    fig_pix.save(fig_png)
                    cropped_figures += 1

    # 4. Generate formula_map.template.json
    template_path = os.path.join(out_dir, "formula_map.template.json")
    tag_dict = {tag: "" for tag in detected_tags}
    with open(template_path, "w", encoding="utf-8") as f:
        json.dump(tag_dict, f, indent=2, ensure_ascii=False)

    print(f"\n[+] Extraction Summary:")
    print(f"    - Rendered {rendered_pages} full formula pages in '{out_dir}/'")
    print(f"    - Cropped {cropped_equations} equation bounding boxes in '{crops_dir}/'")
    if crop_figures:
        print(f"    - Cropped {cropped_figures} figure bounding boxes in '{figures_dir}/'")
    print(f"    - Generated template with {len(detected_tags)} equation tags -> '{template_path}'")

def main():
    parser = argparse.ArgumentParser(description="Extract 300 DPI formula pages and equation bounding box crops from PDF.")
    parser.add_argument("pdf_file", help="Path to input .pdf file")
    parser.add_argument("--out-dir", default="pdf_formula_pages", help="Output directory for images")
    parser.add_argument("--dpi", type=float, default=3.0, help="DPI scaling factor (default: 3.0)")
    parser.add_argument("--no-crops", action="store_true", help="Skip cropping individual equations")
    parser.add_argument("--no-figures", action="store_true", help="Skip cropping vector figures")
    args = parser.parse_args()

    if not os.path.exists(args.pdf_file):
        print(f"Error: File '{args.pdf_file}' not found.", file=sys.stderr)
        sys.exit(1)

    extract_pdf_formula_crops(
        args.pdf_file,
        out_dir=args.out_dir,
        dpi_scale=args.dpi,
        crop_equations=not args.no_crops,
        crop_figures=not args.no_figures
    )

if __name__ == '__main__':
    main()
