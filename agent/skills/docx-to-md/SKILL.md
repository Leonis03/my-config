---
name: docx-to-md
description: Convert Word documents (.docx) to high-quality Markdown with precise mathematical formula error correction (LaTeX $...$ and $$...$$), pure standard Markdown syntax (zero HTML tags), relative image links, clean table generation, code block formatting, and visual bounding-box formula recovery.
allowed-tools: Bash Read
argument-hint: "[document.docx] [output.md]"
arguments: [docx_file]
---

# DOCX to Markdown Conversion with Visual Formula Error Correction

Standard conversion tools (`pandoc`, `mammoth`, `markitdown`) fail significantly on academic, mathematical, and scientific `.docx` documents:
- **`pandoc`**: Turns MathType/OLE equations into broken `.wmf` image links (`![](media/imageX.wmf)`), duplicates equation numbering tags, and mangles 3-column borderless equation tables into broken ASCII tables.
- **`mammoth`**: Inlines all images as bloated base64 URIs, drops custom Word heading styles, and completely ignores embedded binary OLE equations.
- **`markitdown`**: Fails on binary OLE objects and leaves dummy strings or missing content.

This skill provides an **OpenXML-aware pipeline + Visual Formula Grounding Pipeline (LibreOffice + PyMuPDF)** to produce **pure standard Markdown** with standard LaTeX math, relative image paths, clean tables, syntax-highlighted code blocks, and isolated high-resolution figures.

---

## 1. Fast Execution via `uv`

### 1.1 Direct Docx to Markdown Conversion
```bash
# Basic conversion (auto-extracts to "figures_<docname>/")
PYTHONUNBUFFERED=1 uv run --python 3.12 --with python-docx python $HOME/.gemini/config/skills/docx-to-md/scripts/convert_docx_to_md.py input.docx output.md

# Conversion with external LaTeX formula mapping and custom figure directory
PYTHONUNBUFFERED=1 uv run --python 3.12 --with python-docx python $HOME/.gemini/config/skills/docx-to-md/scripts/convert_docx_to_md.py input.docx output.md \
    --media-dir figures \
    --formula-map formula_map.json \
    --image-alts image_alts.json
```

### 1.2 High-Res Formula Image Extraction (For Visual Grounding & AI Correction)
Extract 300 DPI full-page formula images and auto-crop individual numbered equation snippets (`eq_5.1-1.png`, etc.) for multimodal AI review:
```bash
PYTHONUNBUFFERED=1 uv run --python 3.12 --with pymupdf python $HOME/.gemini/config/skills/docx-to-md/scripts/extract_formula_images.py input.docx --out-dir pdf_formula_pages
```

---

## 2. Visual Formula Grounding & AI Correction Pipeline

When handling complex MathType equations, piecewise brackets, or matrices in `.docx`, use this **4-step visual correction loop**:

```
[Source document.docx] 
       │ 
       ▼ (1. Headless LibreOffice renders PDF, 100% preserving vector math fonts)
[High-Fidelity document.pdf]
       │
       ▼ (2. PyMuPDF identifies formula pages & auto-crops 300 DPI equation snippets)
[pdf_formula_pages/crops/eq_5.1-1.png, page_10_formula.png]
       │
       ▼ (3. Multimodal Vision AI / VLM transcribes exact LaTeX)
[Standard LaTeX Code: \min K = \sum_{p \in \mathcal{P}} z_p \tag{5.1-1}]
       │
       ▼ (4. Inject into Markdown via --formula-map formula_map.json)
[Clean, Publication-Grade output.md]
```

### 2.1 Why LibreOffice + PyMuPDF is the Gold Standard
1. **Linux Font Compatibility**: Directly extracting `.wmf` fails on Linux/Web environments and missing fonts (`MT Extra`, `Euclid`, `Symbol`) result in tofu/square replacement glyphs.
2. **Vector Integrity**: LibreOffice embeds math symbols as vector paths into PDF. PyMuPDF renders them at 300 DPI (`Matrix(3.0, 3.0)`), producing sharp images where multimodal vision models achieve near-100% recognition accuracy.

### 2.2 Multimodal AI Vision Prompt Template
Pass cropped formula images (`crops/eq_5.1-1.png` or `page_XX_formula.png`) to a vision model:
```markdown
Please transcribe the mathematical formula (including its equation numbering tag) into clean, standard LaTeX code:
- Use $...$ for inline math and $$... \tag{tag} $$ for display equations.
- Ensure all subscripts, superscripts, summation/integral set indices, large brackets, and matrix alignments are strictly preserved.
- Output only the raw LaTeX code without conversational filler.
```

---

## 3. DOCX OpenXML Anatomy & Equation Recovery

### 3.1 Unwrapping the 3-Column Equation Table Trap
In academic Word documents, display equations with right-aligned numbers (e.g., `(5.1-1)`) are typically laid out in borderless 3-column tables:
- **Column 1**: Indentation / blank
- **Column 2**: Mathematical formula (`<o:OLEObject>` or `<m:oMath>`)
- **Column 3**: Equation numbering label, e.g., `（5.1-1）`

**Correction Rule**:
Never render these as Markdown pipe tables. Unwrap them directly into display LaTeX math blocks with dual formula map lookup:
1. **Tag-based matching**: Matches extracted tag `5.1-1` directly against `formula_map["5.1-1"]`.
2. **OLE number matching**: Matches `oleObject19.bin` against `formula_map["19"]` or `formula_map[19]`.

```latex
$$
\min K = \sum_{p \in \mathcal{P}} z_p \tag{5.1-1}
$$
```

### 3.2 Recovering Word Dynamic Numbering (`w:numPr`)
Headings and numbered lists in Word often store numbering dynamically in `word/numbering.xml` instead of raw text. The conversion script parses `abstractNum` and `numId` to reconstruct:
- Chinese sequence counters (`chineseCounting`): `一、`, `二、`, etc.
- Multi-level decimal counters (`decimal`): `1.1`, `5.1.1`, `（1）`, etc.

---

## 4. Defensive Formatting & Anti-Pitfall Guidelines (17大排坑防线)

### 4.1 Python `re.sub` Escape Sequence Trap (`bad escape \c`)
When replacing LaTeX strings containing commands like `\circ`, `\cos`, or `\mathcal` into text, passing the raw string as the second argument to `re.sub` causes Python's regex engine to crash with `re.error: bad escape \c`.
- **Defensive Rule**: Always pass a replacement lambda `lambda m, r=repl: r` instead of raw strings:
  ```python
  # Safe: prevents regex engine from evaluating backslashes
  text = re.sub(pattern, lambda m, r=latex_formula: r, text)
  ```

### 4.2 Side-by-Side Multi-Figure Unbundling
In Word, authors frequently place two or three figures side-by-side in one paragraph with space-separated captions (e.g., `图2-1 ... 图2-2 ...`).
- **Defensive Rule**: Inspect the figure numbers of all images in the group:
  - If they have distinct figure numbers, unbundle them into sequential `![alt](path)\n\n**alt**` cascades.
  - If they are subfigures sharing one figure number (e.g., `图5.2-7 (a)` and `(b)`), keep them co-located and share a single main bold caption.

### 4.3 Ghost Caption Stripping via Lookbehinds
When paragraph runs are bolded (e.g., bold subheading `**（1）证明**`), space-compressing or run-trimming can pull the figure caption from the right column directly against the closing `**`:
```markdown
**（1）直径端点顶点极值性证明** 图5.1-4 旋转卡壳算法流程图
```
- **Defensive Rule**: Strip trailing captions that were already bound to images:
  ```python
  text = re.sub(r'(?<=\*\*)\s*图\s*[\d\.\-]+[^\n]+$', '', text)
  text = re.sub(r'[ \t]{2,}图\s*[\d\.\-]+[^\n]+$', '', text)
  ```

### 4.4 Heading Candidate Guard (Prevent Long Lists from Becoming Headings)
Never promote a paragraph to a Markdown heading purely on style name or initial digit.
- **Defensive Rule**: A paragraph must satisfy:
  1. `len(clean_text) <= 45`
  2. Does NOT end with punctuation: `。`, `：`, `:`
  3. Does NOT end with transition phrases: `如下`, `所示`, `如下表`, `如下图`

### 4.5 DrawingML Image Deduplication
`<w:drawing>` is often a child of `<w:r>`. Querying both `.//w:r` and `.//w:drawing` causes identical images to be extracted and emitted twice.
- **Defensive Rule**: Scope blip extraction directly to `element.findall('.//a:blip', NS)` and deduplicate target filenames within each paragraph block.

### 4.6 Floating OLE Objects (`w:pict`) Contextual Slot-Filling
Word can place MathType `<w:pict>` floating shapes at the very start of a paragraph, leaving wide whitespace gaps in the middle of the body text.
- **Defensive Rule**: Identify detached initial formulas and relocate them to their semantic slots (e.g., `带有...恒定误差边界`, `即...，`).

### 4.7 Lookahead Type Guard on Consecutive Images (连续插图前瞻类型崩溃防线)
When consecutive paragraphs contain images without intervening text, post-processing lookahead inspects subsequent blocks `raw_blocks[i + j]`. If the next block is another `img_group`, its content is a filename list `list` rather than a text `str`. Calling `.strip()` directly triggers `AttributeError: 'list' object has no attribute 'strip'`.
- **Defensive Rule**: Always verify content types before text normalization:
  ```python
  if not isinstance(nxt_content, str):
      continue
  ```

### 4.8 OpenXML Hyperlink Dropping Trap (丢失 `w:hyperlink` 超链接防线)
Word OpenXML stores external hyperlinks inside `<w:hyperlink r:id="...">` wrapper tags around `<w:r>`. Iterating only over `.//w:r` or direct paragraph children drops the hyperlink element entirely, leaving truncated text like `下载：，如果...` with the URL missing.
- **Defensive Rule**: Explicitly traverse `<w:hyperlink>`, extract the relationship ID from `_rels/document.xml.rels`, and render valid Markdown link syntax:
  ```python
  elif tag == f"{{{NS['w']}}}hyperlink":
      hl_id = child.attrib.get(f"{{{NS['r']}}}id")
      url = rel_map.get(hl_id, "")
      link_txt = extract_child_runs(child)
      if url and link_txt:
          runs_parts.append(f"<{url}>" if link_txt == url else f"[{link_txt}]({url})")
  ```

### 4.9 Windows EMF Vector Graphic Rendering Trap (Windows .emf 矢量图转高保真 PNG)
Word frequently pastes application screenshots or vector shapes as Windows Enhanced Metafiles (`.emf`). Modern browsers and Markdown viewers cannot render `.emf` directly, and standard PIL cannot decode them without native C loader libraries, causing broken image links.
- **Defensive Rule**: In the media extraction stage, detect `.emf` files and automatically invoke headless LibreOffice to render high-resolution `.png`, followed by PIL auto-cropping of redundant white margins:
  ```bash
  libreoffice --headless --convert-to png target.emf --outdir <figures_dir>
  ```

### 4.10 Run-Level Fragmented Bold Leakage in Headings (标题碎片化粗体剥除)
When authors compose headings in Word, individual words or phrases may be partitioned into separate bold runs (`<w:rPr><w:b/></w:rPr>`). Direct run parsing produces fragmented Markdown headings like `# **安装** **SQL Server2016** **企业版** **教程**`.
- **Defensive Rule**: When promoting blocks to `#`, `##`, `###`, or `####` headings, automatically strip embedded `**` wrappers to produce clean heading text.

### 4.11 Inline Icon vs. Standalone Image Distinction (行内小图标与独立配图分流)
Word allows inserting small inline icons (such as button captures or executable file icons like `SSMS-Setup-CHS.exe`) within a sentence run. Treating every image as a standalone block `img_group` rips the inline icon out of sentence context and pushes it to the beginning of the paragraph. Conversely, treating all images as inline text glues consecutive screenshots together horizontally without individual captions.
- **Defensive Rule**: Check whether the paragraph contains genuine text nodes (`<w:t>`):
  - **Text + Image**: Render embedded drawings inline at the exact run position: `...压缩包中的文件 ![icon](path)，然后点安装。`
  - **Pure Image Paragraph**: Route to `img_group` for standalone block rendering with centered/bold captions.

### 4.12 Non-Breaking Space & Punctuation Normalization (消除 `\xa0` 与不可见空格)
Word documents (particularly those imported from HTML, Web, or Chinese typesetting) often contain non-breaking spaces `\xa0` (`&nbsp;`) and inconsistent punctuation spacings.
- **Defensive Rule**: Normalize `\xa0` to standard spaces during inline text cleaning before punctuation compaction.

### 4.13 Continuous Bold Runs Merging (连续粗体 Run 粘连合并防线)
When a bold sentence in Word is partitioned across multiple internal runs (`<w:r>`), wrapping each run independently generates fragmented bold tokens like `**在实验一中建立好的** **study** **数据库中...**`.
- **Defensive Rule**: Merge adjacent bold wrappers using safe regex lambda replacements before final rendering:
  ```python
  while re.search(r'\*\*(.*?)\*\*\s*\*\*(.*?)\*\*', text):
      text = re.sub(r'\*\*(.*?)\*\*\s*\*\*(.*?)\*\*', lambda m: f"**{m.group(1).strip()} {m.group(2).strip()}**", text)
  while re.search(r'\*\*(.*?)\*\*\*\*(.*?)\*\*', text):
      text = re.sub(r'\*\*(.*?)\*\*\*\*(.*?)\*\*', lambda m: f"**{m.group(1)}{m.group(2)}**", text)
  ```

### 4.14 CJK-Western & Digit Typography Spacing (盘古之白中西文排版微距规范)
Word natively renders dynamic micro-spacing between Asian and Latin/number text (`<w:autoSpaceDE/>` and `<w:autoSpaceDN/>`), but leaves the underlying OpenXML strings tightly coupled (`SQL程序设计`, `低于1800的`, `70后的`, `substring函数`).
- **Defensive Rule**: While strictly protecting LaTeX formulas (`$...$`), images, and hyperlinks, automatically inject a standard half-width space between CJK characters and Latin letters/digits, and normalize spacing around full-width Chinese punctuation:
  ```python
  parts = re.split(r"(\$[^\$]+?\$|!\[.*?\]\(.*?\)|\*\*.*?\*\*)", text)
  for idx in range(len(parts)):
      p = parts[idx]
      if not p.startswith(("$", "![", "**")):
          p = re.sub(r"([\u4e00-\u9fa5])([a-zA-Z0-9])", r"\1 \2", p)
          p = re.sub(r"([a-zA-Z0-9])([\u4e00-\u9fa5])", r"\1 \2", p)
          p = re.sub(r"（(\d+)）\s+", r"（\1）", p)
          parts[idx] = p
  ```

### 4.15 Section Keyword Heading Detection (经典实验与报告大纲词冒号识别防线)
In Chinese scientific and lab report documents, section headings frequently terminate with a full-width colon (e.g., `实验目标：`, `实验内容：`, `注意事项：`). A strict colon-rejection filter in heading guards accidentally demotes these core outline sections into body paragraphs.
- **Defensive Rule**: Match against standard report section keywords (`实验目标`, `实验内容`, `实验步骤`, `实验要求`, `实验原理`, `思考题`, etc.), strip trailing colons (`：`, `:`), and promote short matching lines ($\le 25$ chars) to level 2 Markdown headings (`## `).

### 4.16 List Item Heading Guard (列表项误升格标题防线)
Never promote numbered items starting with parenthesized Arabic digits (e.g., `（1）`, `(1)`) into `#### ` headings solely based on a short character length ($\le 30$). Doing so arbitrarily turns short exercise items into headings while leaving longer items as body paragraphs, fragmenting the document outline.
- **Defensive Rule**: Restrict `#### ` promotion only to paragraphs with explicit Word heading styles (`Heading 4`), and treat `（一）` as `### `. Numbered items produced by Word dynamic numbering (`w:numPr`) or list sequences must remain cohesive list paragraphs.

### 4.17 Legacy `.doc` Binary Auto-Conversion (旧版 .doc 复合二进制无缝兼容防线)
Word 97-2003 `.doc` files use OLE2/CFBF binary compound file formatting. Attempting to parse them with standard OpenXML Zip engines triggers `BadZipFile` failures.
- **Defensive Rule**: The CLI entrypoint sniffs the `.doc` extension and compound file signature. If a legacy `.doc` is supplied, headless LibreOffice automatically converts it to high-fidelity `.docx` before entering the OpenXML extraction pipeline:
  ```bash
  libreoffice --headless --convert-to docx input.doc --outdir <workdir>
  ```

---

## 5. Layout & Semantic Formatting Rules

### 5.1 Pure Standard Markdown (Strictly Zero HTML)
Do **not** output HTML tags like `<p align="center">`, `<b>`, `</b>`, `</p>`, or `<br>`. Use standard Markdown:
- Image with caption:
  ```markdown
  ![Caption](figures/image.png)

  **Caption**
  ```
- Table caption:
  ```markdown
  **Table Caption**
  ```

### 5.2 Relative Image Paths & Smart Caption Binding
All extracted images from `word/media/` are referenced using **relative paths** (`os.path.relpath`). Adjacent figure captions are automatically bound as the image alt text.

### 5.3 Data Table Sanitizer
Discard completely empty rows and trailing unfinished draft rows (such as rows with a symbol in Column 1 but empty text in Column 2).

### 5.4 Appendix Source Code Fencing
When table cells or appendix sections contain Python keywords (`import `, `def `, `class `, indentation), wrap them into syntax-highlighted ````python ... ```` blocks.

---

## 6. Final Quality Verification Checklist

- [ ] **Zero HTML Tags**: Zero occurrences of `<p>`, `<b>`, `</b>`, `</p>`, `<br>` in output Markdown.
- [ ] **Formulas Mapped to LaTeX**: All display equations mapped to `$$\n ... \tag{...}\n$$` with correct equation numbers.
- [ ] **No Dummy Formula Placeholders**: Zero occurrences of raw `Formula_N` tokens.
- [ ] **Relative Image Links**: All images referenced using relative paths (`![caption](figures/image.png)`).
- [ ] **No 3-Column Pseudo-Tables**: Equation layout tables unwrapped into display math blocks.
- [ ] **No Ghost Captions**: No lingering figure captions at the end of section headings or body paragraphs.
- [ ] **Table Sanitization**: No blank or orphan-symbol draft rows in GFM pipe tables.
- [ ] **Clean Code Blocks**: Appendices formatted with proper syntax-highlighted code fences.
- [ ] **No Raw EMF Files**: Windows EMF files converted to standard PNG for web and Markdown compatibility.
- [ ] **Hyperlink Integrity**: All `w:hyperlink` targets preserved as `<url>` or `[text](url)`.
- [ ] **Clean Heading Syntax**: No fragmented `**` bold tags inside `#` headings.
- [ ] **Inline Icons Preserved**: Inline icons rendered in-place within sentence flow, not detached into standalone blocks.
- [ ] **Cohesive Bold Formatting**: No fragmented `**A** **B**` bold tags in body text.
- [ ] **Balanced CJK-Western Spacing**: Standard pangu micro-spacing between Chinese and Latin/numbers.
- [ ] **Accurate Outline Hierarchy**: Numbered list items (`（1）`, `(1)`) preserved without arbitrary promotion to `####`.
- [ ] **Cross-Version Binary Compatibility**: Transparently converts both `.docx` and legacy `.doc` files.
