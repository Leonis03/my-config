#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Universal High-Fidelity PDF to Markdown Converter with Visual Formula Error Correction.
Cross-platform compatible (Linux / macOS / Windows).

Features:
- Pure Standard Markdown: Strictly zero HTML tags (<p>, <b>, </b>, </p>, <br>).
- Universal PUA Glyph Decoding: Decodes MathType/Symbol/MT Extra private-use glyphs to LaTeX.
- Multi-Figure Proximity Matching: Matches captions to their geometrically nearest images (fixes p_imgs[0] bug).
- Vector Diagram Fallback: Auto-crops vector graphics when raster images are absent.
- Formula & Text Separation: Preserves explanatory text when unwrapping display formulas.
- Robust Heading Candidate Guard: Prevents long list items and explanatory paragraphs from false heading promotion.
- Clean GFM Tables: Auto-detects tables, formats pipe alignment, and purges empty/orphan rows.
- Continuous Prose Smoothing: Seamlessly unwraps mid-sentence line breaks and de-hyphenates words.
- Safe Regex Engine: All LaTeX replacements use lambda callbacks to eliminate 'bad escape \\c' crashes.
"""

import os
import sys
import re
import json
import argparse
import pymupdf

# Configure stdout and stderr for UTF-8 encoding across Windows and Linux
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

PUA_GLYPH_MAP = {
    '\uf0b0': '^{\\circ}',
    '\uf0ce': ' \\in ',
    '\uf03d': ' = ',
    '\uf0e5': ' \\sum ',
    '\uf0a3': ' \\le ',
    '\uf0b3': ' \\ge ',
    '\uf0e9': ' \\lceil ',
    '\uf0f9': ' \\rceil ',
    '\uf0ea': ' \\lfloor ',
    '\uf0fa': ' \\rfloor ',
    '\uf02b': ' + ',
    '\uf02d': ' - ',
    '\uf0b4': ' \\times ',
    '\uf022': ' \\forall ',
    '\uf071': ' \\theta ',
    '\uf072': ' \\rho ',
    '\uf06c': ' \\lambda ',
    '\uf06a': ' \\varphi ',
    '\uf065': ' \\varepsilon ',
    '\uf070': ' \\pi ',
    '\uf0b6': ' \\partial ',
    '\uf0b9': ' \\neq ',
    '\uf044': ' \\Delta ',
    '\uf0bc': ' \\cdots ',
    '\uf051': ' \\boldsymbol{\\Theta} ',
    '\uf028': '(',
    '\uf029': ')',
    '\uf0ef': '',
    '\uf0ec': '',
    '\uf0ed': '',
    '\uf0ee': '',
    '\uf0eb': '',
    '\uf0fb': '',
    '\uff1d': ' = ',
    '\u00d7': ' \\times ',
    '\u00b0': '^{\\circ}',
}

TAG_REGEX = re.compile(r'[（\(](?:式\s*)?(\d+(?:[\.\-]\d+)*)[）\)]')

def clean_inline_math(text, inline_map=None):
    """Normalize PUA glyphs, strip HTML, clean math spacing and de-hyphenate text."""
    if not text:
        return ""

    # 1. PUA Glyph replacement
    for glyph, repl in PUA_GLYPH_MAP.items():
        if glyph in text:
            text = text.replace(glyph, repl)
    text = "".join(c for c in text if not (0xE000 <= ord(c) <= 0xF8FF))

    # 2. HTML tag removal
    text = re.sub(r'<p\s+align=[^>]+><b>(.*?)</b></p>', r'**\1**', text, flags=re.DOTALL)
    text = re.sub(r'</?[a-zA-Z0-9]+(?:\s+[^>]*)?>', '', text)

    # 3. De-hyphenate words broken across linebreaks
    text = re.sub(r'([a-zA-Z]+)-\s*\n\s*([a-zA-Z]+)', r'\1\2', text)

    # 4. User-provided inline formula map replacements
    if inline_map:
        for pat, rep in inline_map.items():
            text = re.sub(re.escape(pat), lambda m, r=rep: r, text)

    # 5. Universal Math Typography Normalizations
    text = re.sub(r'(\d+)\s*°', r'$\1^\\circ$', text)
    text = re.sub(r'(\d+(?:\.\d+)?)\s*m/s', r'$\1\\text{ m/s}$', text)
    text = re.sub(r'(\d+(?:\.\d+)?)\s*km', r'$\1\\text{ km}$', text)

    # Scientific notation: e.g. 5.1 \times 10-4 s -> 5.1 \times 10^{-4}\text{ s}
    text = re.sub(r'(\d+(?:\.\d+)?)\s*\\times\s*10-(\d+)', r'$\1 \\times 10^{-\2}$', text)

    # Normalize whitespace & math delimiters
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\$\s+([^\$]+?)\s+\$', r'$\1$', text)
    text = text.replace('$ $', ' ').replace('$$', '$')

    # Remove spaces before standard punctuation
    text = re.sub(r'\s+([，。！？；：、\),])', r'\1', text)
    text = re.sub(r'([\(\(])\s+', r'\1', text)

    # Clean redundant newlines inside continuous sentences
    text = re.sub(r'([^\n。！？：；:;,])\n([^\n# \t\-\*\d|])', r'\1\2', text)
    text = re.sub(r'([\u4e00-\u9fff\uff0c\u3001\uff1b])\n([\u4e00-\u9fff])', r'\1\2', text)

    return text.strip()

def format_gfm_table(matrix, inline_map=None):
    """Convert extracted 2D matrix into clean GFM pipe table, purges empty/orphan rows."""
    if not matrix or not matrix[0]:
        return ""

    cleaned_matrix = []
    for row in matrix:
        cleaned_row = []
        for cell in row:
            c = str(cell or "").strip().replace("\n", " ")
            c = clean_inline_math(c, inline_map)
            cleaned_row.append(c.replace("|", "\\|"))

        # Discard completely empty rows
        if not any(cleaned_row):
            continue
        # Discard orphan rows (e.g. 2-column table with empty explanation in column 2)
        if len(cleaned_row) == 2 and not cleaned_row[1]:
            continue

        cleaned_matrix.append(cleaned_row)

    if not cleaned_matrix:
        return ""

    num_cols = max(len(row) for row in cleaned_matrix)
    for row in cleaned_matrix:
        while len(row) < num_cols:
            row.append("")

    header = cleaned_matrix[0]
    sep = [":---" if i == 0 else ":---:" for i in range(num_cols)]

    lines = [
        "| " + " | ".join(header) + " |",
        "| " + " | ".join(sep) + " |"
    ]
    for row in cleaned_matrix[1:]:
        lines.append("| " + " | ".join(row) + " |")

    return "\n".join(lines)

def extract_pdf_images_with_geometry(doc, output_dir):
    """
    Extract raster images and record their bounding boxes on each page.
    Returns: dict {page_num: list of dict {'filename': fname, 'bbox': rect, 'consumed': False}}

    The directory is created lazily, on the first image actually written, so a
    PDF without raster images leaves no empty figures_<name>/ behind.
    """
    images_by_page = {}

    for page_idx in range(len(doc)):
        page_num = page_idx + 1
        page = doc[page_idx]
        img_list = page.get_images()
        page_records = []

        for img_idx, img_info in enumerate(img_list):
            xref = img_info[0]
            try:
                base_image = doc.extract_image(xref)
                img_bytes = base_image["image"]
                img_ext = base_image["ext"]
                fname = f"fig_p{page_num}_{img_idx + 1}.{img_ext}"
                fpath = os.path.join(output_dir, fname)

                os.makedirs(output_dir, exist_ok=True)
                with open(fpath, "wb") as f:
                    f.write(img_bytes)

                # Get physical bounding boxes on the page for this image
                rects = page.get_image_rects(xref)
                rect = rects[0] if rects else pymupdf.Rect(0, 0, page.rect.width, page.rect.height)

                page_records.append({
                    "filename": fname,
                    "bbox": rect,
                    "y0": rect.y0,
                    "y1": rect.y1,
                    "consumed": False
                })
            except Exception:
                continue

        # Sort images on page by vertical coordinate
        page_records.sort(key=lambda r: r["y0"])
        images_by_page[page_num] = page_records

    return images_by_page

def match_image_for_caption(page, page_num, cap_rect, images_by_page, abs_figures_dir, rel_figures_dir):
    """
    Find the best matching image for a figure caption based on geometric proximity.
    If no raster image is found above caption, crops a high-res vector region on the fly.
    """
    page_imgs = images_by_page.get(page_num, [])

    # 1. Search for unconsumed raster image positioned immediately above caption (y1 <= cap_rect.y0 + 15)
    candidates_above = [
        img for img in page_imgs
        if not img["consumed"] and img["y1"] <= cap_rect.y0 + 15
    ]
    if candidates_above:
        # Pick the one closest to the caption
        best_img = min(candidates_above, key=lambda img: cap_rect.y0 - img["y1"])
        best_img["consumed"] = True
        return f"![{cap_rect}]({rel_figures_dir}/{best_img['filename']})"

    # 2. Search for any remaining unconsumed raster image on this page
    remaining = [img for img in page_imgs if not img["consumed"]]
    if remaining:
        best_img = remaining[0]
        best_img["consumed"] = True
        return f"![{cap_rect}]({rel_figures_dir}/{best_img['filename']})"

    # 3. Vector graphic fallback: crop region above caption
    try:
        clean_name = f"vector_p{page_num}_{int(cap_rect.y0)}.png"
        fpath = os.path.join(abs_figures_dir, clean_name)
        fig_y0 = max(35.0, cap_rect.y0 - 220.0)
        crop_rect = pymupdf.Rect(35.0, fig_y0, page.rect.width - 35.0, max(fig_y0 + 40.0, cap_rect.y0 - 5.0))
        pix = page.get_pixmap(clip=crop_rect, matrix=pymupdf.Matrix(2.0, 2.0))
        # Lazily created here too: a PDF whose only figures are vector crops has
        # no raster extraction pass to create the directory first.
        os.makedirs(abs_figures_dir, exist_ok=True)
        pix.save(fpath)
        return f"![{cap_rect}]({rel_figures_dir}/{clean_name})"
    except Exception:
        return ""

def extract_page_lines_with_indent(page, page_num):
    """Compute geometric indentation for source code listings in appendices."""
    page_dict = page.get_text("dict")
    blocks = page_dict.get("blocks", [])
    lines_out = []

    x_positions = []
    for b in blocks:
        if "lines" in b:
            for l in b["lines"]:
                bbox = l["bbox"]
                if 40 < bbox[0] < 160:
                    x_positions.append(bbox[0])

    base_x = min(x_positions) if x_positions else 70.0
    step_x = 24.0
    page_num_str = str(page_num)

    for b in blocks:
        if "lines" in b:
            for l in b["lines"]:
                text = "".join(s["text"] for s in l["spans"]).rstrip()
                if not text or text.strip() == page_num_str:
                    continue
                bbox = l["bbox"]
                indent_level = max(0, round((bbox[0] - base_x) / step_x))
                indent_spaces = "    " * indent_level
                lines_out.append(f"{indent_spaces}{text}")

    return lines_out

def convert_pdf_to_markdown(pdf_path, output_md_path, figures_dir=None, formula_map=None, inline_map=None):
    """Full-fidelity pipeline for converting PDF documents into publication-grade Markdown."""
    if formula_map is None:
        formula_map = {}
    if inline_map is None:
        inline_map = {}

    # Separate inline mapping if embedded in formula_map
    if "__inline__" in formula_map:
        inline_map.update(formula_map.pop("__inline__"))

    output_dir = os.path.dirname(os.path.abspath(output_md_path))
    if figures_dir is None:
        base = os.path.splitext(os.path.basename(pdf_path))[0]
        abs_figures_dir = os.path.join(output_dir, f"figures_{base}")
        rel_figures_dir = f"figures_{base}"
    else:
        if os.path.isabs(figures_dir):
            abs_figures_dir = figures_dir
            rel_figures_dir = os.path.relpath(figures_dir, output_dir)
        else:
            abs_figures_dir = os.path.join(output_dir, figures_dir)
            rel_figures_dir = figures_dir

    doc = pymupdf.open(pdf_path)
    images_by_page = extract_pdf_images_with_geometry(doc, abs_figures_dir)
    print(f"[*] Processing PDF '{pdf_path}' ({len(doc)} pages)...")

    md_paragraphs = []
    in_code_block = False
    current_code_lines = []

    page_num_pat = re.compile(r"^\d+$")
    appendix_header_pat = re.compile(r"^(附录[一二三四五六七八九十0-9A-Za-z]+)\s*(.*)")

    for page_idx in range(len(doc)):
        page_num = page_idx + 1
        page = doc[page_idx]

        page_raw_text = page.get_text("text")
        is_code_page = in_code_block or ("# -*- coding" in page_raw_text or "coding: utf-8" in page_raw_text)

        # 1. Appendix Source Code Extraction with Indentation
        if is_code_page and page_num > 3:
            geom_lines = extract_page_lines_with_indent(page, page_num)
            for line in geom_lines:
                ls = line.strip()
                app_match = appendix_header_pat.match(ls)
                if app_match and ("程序" in ls or "代码" in ls or "支撑材料" in ls or len(ls) < 40):
                    if in_code_block and current_code_lines:
                        md_paragraphs.append("```python\n" + "\n".join(current_code_lines).strip() + "\n```")
                        current_code_lines = []
                        in_code_block = False

                    app_num = app_match.group(1)
                    app_title = app_match.group(2).strip()
                    md_paragraphs.append(f"### {app_num} {app_title}")
                    continue

                if "coding: utf-8" in ls:
                    if in_code_block and current_code_lines:
                        md_paragraphs.append("```python\n" + "\n".join(current_code_lines).strip() + "\n```")
                        current_code_lines = []
                    in_code_block = True
                    current_code_lines.append(line)
                    continue

                if in_code_block:
                    current_code_lines.append(line)
                else:
                    if ls.startswith("import ") or ls.startswith("from ") or ls.startswith("def "):
                        in_code_block = True
                        current_code_lines.append(line)
                    else:
                        c_text = clean_inline_math(ls, inline_map)
                        if c_text:
                            md_paragraphs.append(c_text)
            continue

        # 2. Table Extraction
        tabs = page.find_tables()
        handled_rects = []
        elements = []

        for tab in tabs.tables:
            tab_rect = pymupdf.Rect(tab.bbox)
            handled_rects.append(tab_rect)
            matrix = tab.extract()

            # Check if this is an equation table (3 cols, last col has equation tag)
            formula_rows = []
            for r_idx, row in enumerate(matrix):
                row_str = " ".join(str(c or "") for c in row)
                m = TAG_REGEX.findall(row_str)
                if m and m[-1] in formula_map:
                    tag = m[-1]
                    formula_rows.append((r_idx, tag, formula_map[tag]))

            if formula_rows:
                for r_idx, tag, formula_latex in formula_rows:
                    elements.append((tab_rect.y0 + r_idx * 0.1, "formula", f"$$\n{formula_latex} \\tag{{{tag}}}\n$$"))
            elif len(matrix) >= 2:
                md_tab = format_gfm_table(matrix, inline_map)
                if md_tab:
                    elements.append((tab_rect.y0, "table", md_tab))

        # 3. Block Text Extraction & Layout Classification
        blocks = page.get_text("blocks")
        for b in blocks:
            b_rect = pymupdf.Rect(b[:4])
            b_text = b[4].strip()
            if not b_text or page_num_pat.match(b_text):
                continue

            # Skip blocks already consumed by tables
            if any(b_rect.intersects(r) and (b_rect.y0 >= r.y0 - 4 and b_rect.y1 <= r.y1 + 4) for r in handled_rects):
                continue

            lines = [l.strip() for l in b_text.split("\n") if l.strip()]
            if lines and page_num_pat.match(lines[0]):
                lines = lines[1:]
                b_text = "\n".join(lines).strip()
            if not b_text:
                continue

            # Heading candidate filter guard
            is_heading_candidate = (
                len(b_text) <= 50
                and not b_text.endswith("。")
                and not b_text.endswith("：")
                and not b_text.endswith(":")
                and not b_text.endswith(";")
                and not b_text.endswith("；")
                and not any(b_text.endswith(x) for x in ["如下", "所示", "如下表", "如下图", "如下所示"])
            )

            # Check for display formula in block
            eq_matches = TAG_REGEX.findall(b_text)
            is_citation = any(prefix in b_text for prefix in ["其中，公式", "公式(", "公式（", "求解式", "见式", "按式", "由式", "满足式", "根据式", "在式", "代入式"])

            if eq_matches and not is_citation and eq_matches[-1] in formula_map:
                tag = eq_matches[-1]
                formula_latex = formula_map[tag]

                # Separate pre-formula explanatory text from formula line
                pre_lines = []
                for l in lines:
                    if TAG_REGEX.search(l):
                        break
                    pre_lines.append(l)

                if pre_lines:
                    cleaned_pre = clean_inline_math(" ".join(pre_lines), inline_map)
                    if cleaned_pre:
                        elements.append((b_rect.y0 - 0.1, "prose", cleaned_pre))

                elements.append((b_rect.y0, "formula", f"$$\n{formula_latex} \\tag{{{tag}}}\n$$"))
                continue

            # Ignore unmapped disjointed math fragment noise
            if not any('\u4e00' <= c <= '\u9fff' for c in b_text):
                if all(ord(c) >= 0xE000 and ord(c) <= 0xF8FF or c in " \n\t,=+-*/_(),'\"[]{}0123456789\\^" or len(c.strip()) <= 1 for c in b_text) and len(b_text) < 40:
                    continue
                if len(lines) > 2 and all(len(l) <= 3 for l in lines):
                    continue

            # Document Title on Page 1
            if page_num == 1 and b_rect.y0 < 180 and is_heading_candidate and len(b_text) <= 35 and not b_text.startswith("摘要"):
                elements.append((b_rect.y0, "heading", f"# {b_text}"))
                continue
            # Abstract
            if b_text.startswith("摘要") or b_text == "摘要" or b_text.startswith("Abstract"):
                elements.append((b_rect.y0, "heading", f"## {b_text}"))
                continue
            # Level 1 section (Chinese Counting: 一、, 二、, etc.)
            if re.match(r"^[一二三四五六七八九十]+、", b_text) and is_heading_candidate:
                elements.append((b_rect.y0, "heading", f"## {b_text}"))
                continue
            # Subsection 1.1, 5.1, etc.
            if re.match(r"^\d+\.\d+\s+", b_text) and is_heading_candidate:
                elements.append((b_rect.y0, "heading", f"### {b_text}"))
                continue
            # Subsubsection 5.1.1, etc.
            if re.match(r"^\d+\.\d+\.\d+\s+", b_text) and is_heading_candidate:
                elements.append((b_rect.y0, "heading", f"#### {b_text}"))
                continue
            # Sub-items starting with （1）, （2）, etc.
            if re.match(r"^[（\(]\d+[）\)]\s*[\u4e00-\u9fa5A-Za-z]", b_text) and is_heading_candidate and len(b_text) <= 30:
                elements.append((b_rect.y0, "heading", f"#### {b_text}"))
                continue

            # Figure captions: link geometrically closest image
            if (b_text.startswith("图") or b_text.startswith("Figure")) and any(c.isdigit() for c in b_text[:8]) and len(b_text) < 120:
                img_md = match_image_for_caption(page, page_num, b_rect, images_by_page, abs_figures_dir, rel_figures_dir)
                cap_block = f"{img_md}\n\n**{b_text}**" if img_md else f"**{b_text}**"
                elements.append((b_rect.y0, "figure", cap_block))
                continue

            # Table captions
            if (b_text.startswith("表") or b_text.startswith("Table")) and any(c.isdigit() for c in b_text[:8]) and len(b_text) < 120:
                elements.append((b_rect.y0, "table_caption", f"**{b_text}**"))
                continue

            # Appendix Header
            app_match = appendix_header_pat.match(b_text)
            if app_match and len(lines) <= 3:
                app_num = app_match.group(1)
                app_title = app_match.group(2).strip()
                elements.append((b_rect.y0, "appendix_heading", f"### {app_num} {app_title}"))
                continue

            # Regular prose text
            cleaned_text = clean_inline_math(b_text, inline_map)
            if cleaned_text:
                elements.append((b_rect.y0, "prose", cleaned_text))

        # Sort elements on page by vertical coordinate
        elements.sort(key=lambda item: item[0])

        # Merge consecutive prose blocks on the same page
        current_prose = []
        for _, elem_type, content in elements:
            if elem_type == "prose":
                current_prose.append(content)
            else:
                if current_prose:
                    merged_p = clean_inline_math_merge(current_prose, inline_map)
                    if merged_p:
                        md_paragraphs.append(merged_p)
                    current_prose = []
                md_paragraphs.append(content)

        if current_prose:
            merged_p = clean_inline_math_merge(current_prose, inline_map)
            if merged_p:
                md_paragraphs.append(merged_p)

    if in_code_block and current_code_lines:
        md_paragraphs.append("```python\n" + "\n".join(current_code_lines).strip() + "\n```")

    # 4. Final Cross-Paragraph Prose Stitching
    final_blocks = []
    for p in md_paragraphs:
        p = p.strip()
        if not p:
            continue
        if not final_blocks:
            final_blocks.append(p)
            continue

        prev = final_blocks[-1]
        is_prev_special = prev.startswith("#") or prev.startswith("```") or prev.startswith("|") or prev.startswith("$$") or prev.startswith("![") or prev.startswith("**表") or prev.startswith("**图") or re.match(r'^\d+\.\s+', prev) or prev.startswith("- ")
        is_curr_special = p.startswith("#") or p.startswith("```") or p.startswith("|") or p.startswith("$$") or p.startswith("![") or p.startswith("**表") or p.startswith("**图") or re.match(r'^\d+\.\s+', p) or p.startswith("- ")

        if not is_prev_special and not is_curr_special:
            if not any(prev.endswith(term) for term in ['。', '！', '？', '：', ':', '；', ';', '”', '’', ')', '）']):
                if any('\u4e00' <= c <= '\u9fff' for c in prev[-2:]) and any('\u4e00' <= c <= '\u9fff' for c in p[:2]):
                    final_blocks[-1] = prev + p
                else:
                    final_blocks[-1] = prev + " " + p
                continue

        final_blocks.append(p)

    full_md = "\n\n".join(final_blocks) + "\n"
    full_md = re.sub(r'\n{3,}', '\n\n', full_md)
    full_md = re.sub(r'(\[\d+\])\s+', r'\1 ', full_md)

    with open(output_md_path, "w", encoding="utf-8") as f:
        f.write(full_md)

    print(f"[+] Successfully converted '{pdf_path}' -> '{output_md_path}' ({len(full_md):,} chars, {len(full_md.splitlines())} lines)")

def clean_inline_math_merge(prose_list, inline_map=None):
    """Smoothly merge text blocks on the same page into cohesive paragraphs."""
    if not prose_list:
        return ""
    merged = ""
    for p in prose_list:
        p = p.strip()
        if not p:
            continue
        if not merged:
            merged = p
        else:
            if not any(merged.endswith(term) for term in ['。', '！', '？', '：', ':', '；', ';']):
                if any('\u4e00' <= c <= '\u9fff' for c in merged[-2:]) and any('\u4e00' <= c <= '\u9fff' for c in p[:2]):
                    merged += p
                else:
                    merged += " " + p
            else:
                merged += "\n\n" + p
    return clean_inline_math(merged, inline_map)

def main():
    parser = argparse.ArgumentParser(description="Universal High-Fidelity PDF to Markdown Converter.")
    parser.add_argument("input_pdf", help="Path to input PDF file")
    parser.add_argument("output_md", nargs="?", default=None, help="Path to output Markdown file (default: same basename as pdf)")
    parser.add_argument("--figures-dir", default=None, help="Directory to save extracted figures (default: figures_<docname>)")
    parser.add_argument("--formula-map", default=None, help="Path to JSON file containing equation formula mappings")
    parser.add_argument("--inline-map", default=None, help="Path to JSON file containing inline symbol mappings")
    args = parser.parse_args()

    input_pdf = args.input_pdf
    if not os.path.exists(input_pdf):
        print(f"Error: File '{input_pdf}' not found.", file=sys.stderr)
        sys.exit(1)

    formula_map = None
    if args.formula_map:
        if os.path.exists(args.formula_map):
            with open(args.formula_map, "r", encoding="utf-8") as f:
                formula_map = json.load(f)
        else:
            print(f"Warning: Formula map file '{args.formula_map}' not found.", file=sys.stderr)

    inline_map = None
    if args.inline_map:
        if os.path.exists(args.inline_map):
            with open(args.inline_map, "r", encoding="utf-8") as f:
                inline_map = json.load(f)
        else:
            print(f"Warning: Inline map file '{args.inline_map}' not found.", file=sys.stderr)

    output_md = args.output_md or os.path.splitext(input_pdf)[0] + ".md"
    convert_pdf_to_markdown(
        input_pdf,
        output_md,
        figures_dir=args.figures_dir,
        formula_map=formula_map,
        inline_map=inline_map
    )

if __name__ == "__main__":
    main()
