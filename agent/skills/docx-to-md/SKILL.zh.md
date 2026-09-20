---
name: docx-to-md-zh
description: 将 Word 文档 (.docx) 高保真转换为 Markdown，包含精准数学公式纠错（LaTeX $...$ 和 $$...$$）、纯净原生 Markdown 语法（零 HTML 标签）、相对图片路径、整洁 GFM 表格生成、代码块智能排版与视觉切片公式还原。适用于学术论文、数学建模竞赛报告或工程技术文档的无损转换，彻底根除公式乱码、文字多倍重复与 WMF 坏链。
allowed-tools: Bash Read
argument-hint: "[文档.docx] [输出.md]"
arguments: [docx_file]
---

# DOCX 转 Markdown 高保真转换与视觉公式纠错指南

常规转换工具（`pandoc`、`mammoth`、`markitdown`）在处理学术、数学与工程类 `.docx` 文档时存在严重缺陷：
- **`pandoc`**：将 MathType/OLE 公式错误导出为无法正常显示的 `.wmf` 图片链接（`![](media/imageX.wmf)`），导致公式编号重复，并将 3 栏无边框公式排版表格渲染为错乱的 ASCII 表格。
- **`mammoth`**：将所有图片内联为庞大的 base64 字符串，丢失 Word 自定义标题大纲样式，且完全忽略嵌入式二进制 OLE 公式。
- **`markitdown`**：无法解析底层二进制 OLE 对象，导致公式丢失或输出无意义占位符。

本 Skill 提供了 **OpenXML 结构化解析管线 + 基于 LibreOffice 与 PyMuPDF 的视觉真值公式纠错流**，输出**纯净原生 Markdown** 文档（含标准 LaTeX 公式、GFM 规范表格、语法高亮代码块、自动图题绑定与相对路径高清插图）。

---

## 1. 基于 `uv` 的一键快速执行

### 1.1 直接执行 Docx 转 Markdown
```bash
# 基础转换（默认输出图片至相对目录 figures_<docname>/）
PYTHONUNBUFFERED=1 uv run --python 3.12 --with python-docx python $HOME/.gemini/config/skills/docx-to-md/scripts/convert_docx_to_md.py input.docx output.md

# 注入 LaTeX 公式映射字典与自定义图片说明
PYTHONUNBUFFERED=1 uv run --python 3.12 --with python-docx python $HOME/.gemini/config/skills/docx-to-md/scripts/convert_docx_to_md.py input.docx output.md \
    --media-dir figures \
    --formula-map formula_map.json \
    --image-alts image_alts.json
```

### 1.2 高清公式切片提取（用于多模态视觉比对与 AI 纠错）
一键生成 300 DPI 超清公式页面图及自动裁剪的单公式小图（如 `eq_5.1-1.png`），供多模态 AI 审阅纠错：
```bash
PYTHONUNBUFFERED=1 uv run --python 3.12 --with pymupdf python $HOME/.gemini/config/skills/docx-to-md/scripts/extract_formula_images.py input.docx --out-dir pdf_formula_pages
```

---

## 2. 视觉真值公式纠错工作流 (Visual Formula Grounding)

当遇到复杂的 MathType 公式、分段大括号或矩阵排版时，建议采用以下**四步视觉纠错闭环**：

```
[原始 document.docx] 
       │ 
       ▼ (1. LibreOffice 无头模式生成 PDF，100% 固化矢量数学字体)
[高保真 document.pdf]
       │
       ▼ (2. PyMuPDF 自动定位公式页并裁剪 300 DPI 方程切片小图)
[pdf_formula_pages/crops/eq_5.1-1.png, page_10_formula.png]
       │
       ▼ (3. 喂给多模态 AI (Vision API / VLM) 进行零误差 LaTeX 识别)
[标准 LaTeX 代码: \min K = \sum_{p \in \mathcal{P}} z_p \tag{5.1-1}]
       │
       ▼ (4. 注入 formula_map.json 并在转 Markdown 时一键替换)
[最终出版级无错 Markdown 文件 (output.md)]
```

### 2.1 为什么必须采用 LibreOffice + PyMuPDF 方案？
1. **Linux 字体兼容性**：直接提取 `.wmf` 在 Linux 和网页端无法正常显示，且缺少 `MT Extra`、`Euclid`、`Symbol` 字体会导致符号显示为方框或乱码。
2. **矢量路径绝对保真**：LibreOffice 将数学符号作为矢量路径写入 PDF，PyMuPDF 以 300 DPI (`Matrix(3.0, 3.0)`) 渲染为超清 PNG，分式、上下标与大括号分毫毕现，多模态 AI 读图识别率接近 100%。

### 2.2 多模态 AI 读图提示词模板 (Prompt Template)
将裁剪的公式小图（`crops/eq_5.1-1.png` 或 `page_XX_formula.png`）发送给 Vision 模型：
```markdown
请仔细观察图片中的数学公式（包含右侧公式编号），输出标准、严谨的 LaTeX 代码：
- 行内公式使用 $...$，行间独立公式使用 $$... \tag{tag} $$。
- 确保所有上下标、求和/积分求值集合指标、大括号分段与矩阵对齐完全准确。
- 仅输出纯净的 LaTeX 代码块，无需冗余寒暄。
```

---

## 3. DOCX OpenXML 结构与公式解析

### 3.1 3 栏无框公式表格解构 (Unwrapping 3-Column Tables)
学术论文 Word 文档中，带右侧编号（如 `(5.1-1)`）的行间公式通常以 3 列无边框表格排版：
- **第 1 列**：缩进空白
- **第 2 列**：公式实体（`<o:OLEObject>` 或 `<m:oMath>`）
- **第 3 列**：公式编号文本 `（5.1-1）`

**处理准则**：
严禁转换为 Markdown 管道表格，应直接解构为标准行间 LaTeX 公式块，并优先根据公式标签从 `formula_map` 获取 LaTeX 代码（同时支持标签键 `"5.1-1"` 与 OLE 编号键 `"19"` 或 `19`）：
```latex
$$
\min K = \sum_{p \in \mathcal{P}} z_p \tag{5.1-1}
$$
```

### 3.2 恢复 Word 动态编号与多级列表 (`w:numPr`)
Word 中的章节标题与条目编号通常动态存储在 `word/numbering.xml` 中，而非正文文本内部。转换脚本内置计数器状态机，通过解析 `abstractNum` 与 `numId` 自动追踪还原：
- 中文大写序号（`chineseCounting`）：如 `一、`、`二、`
- 多级数字编号（`decimal`）：如 `1.1`、`5.1.1`、`（1）` 等

---

## 4. 防御性排版与排坑指南 (17大排坑防线)

### 4.1 Python `re.sub` 原生转义崩溃防线 (`bad escape \c`)
在将包含 `\circ`（度数）、`\cos`、`\mathcal` 等 LaTeX 宏命令替换回正文时，若直接传给 `re.sub` 第二参数，Python 正则引擎会将 `\c` 误认为非法的反向引用，抛出 `re.error: bad escape \c` 崩溃。
- **防御规范**：所有 LaTeX 替换必须通过 Lambda 回调函数传参：
  ```python
  # 安全写法：彻底杜绝正则引擎对反斜杠的二次转义求值
  text = re.sub(pattern, lambda m, r=latex_formula: r, text)
  ```

### 4.2 并排多图解耦与级联图题绑定
Word 中作者常用大量空格将两张或三张图片并排摆放（如 `图2-1 ... 图2-2 ...`）。
- **防御规范**：检查图片组内各图提取出的图号：
  - 若图号不同（如 `图2-1` 与 `图2-2`），自动解耦为“图片 + 独立图题”的标准纵向瀑布流；
  - 若为同图的子图（如 `图5.2-7 (a)` 与 `(b)`），则保持并列排列并共享主图题。

### 4.3 幽灵图题零宽断言清洗
段落小标题加粗（如 `**（1）证明**`）后，原有空格被缩进压缩，可能导致右侧的图题黏附在闭合的 `**` 之后，生成 `**（1）证明** 图5.1-4 流程图`。
- **防御规范**：通过前向断言正则剥离已绑定的游离图题：
  ```python
  text = re.sub(r'(?<=\*\*)\s*图\s*[\d\.\-]+[^\n]+$', '', text)
  text = re.sub(r'[ \t]{2,}图\s*[\d\.\-]+[^\n]+$', '', text)
  ```

### 4.4 标题候选守卫（防止长列表误升大纲标题）
严禁仅依据 Word 样式名或前缀数字盲目将段落提升为 Markdown 标题。
- **防御规范**：候选段落必须同时满足：
  1. 字符长度 $\le 45$；
  2. 绝不以标点符号结尾：`。`、`：`、`:`；
  3. 绝不以引出词结尾：`如下`、`所示`、`如下表`、`如下图`。

### 4.5 DrawingML 图像节点全局去重
`<w:drawing>` 通常作为 `<w:r>` 的子元素存在，若同时查询两者会导致同一张图片被提取两次并连续输出。
- **防御规范**：将图像探测严格收敛到 `element.findall('.//a:blip', NS)`，并在段落块内按目标文件名执行严格集合去重。

### 4.6 浮动 OLE 对象（`<w:pict>`）语义槽位回填
Word 允许将 MathType 设为浮动对象，这会导致其在 XML 中被存放在段首，正文中则留下连续空格作为留白占位。
- **防御规范**：识别段首孤立脱节的短公式，结合语义模式（如 `带有...恒定误差边界`、`即...，`）精准平移回填至原始留白槽位中。

### 4.7 连续插图前瞻类型崩溃防线 (`isinstance(nxt_content, str)`)
当文档中存在连续多段纯图片（`img_group`）而无正文文本时，后处理阶段的图题前瞻搜索会探测后续块 `raw_blocks[i + j]`。若后续块恰好为下一个图片组，其 `nxt_content` 为文件名列表 `list` 而非文本 `str`，直接调用 `.strip()` 会触发致命异常 `AttributeError: 'list' object has no attribute 'strip'` 导致进程中断。
- **防御规范**：在前瞻图题文本处理前，必须进行显式类型守卫：
  ```python
  if not isinstance(nxt_content, str):
      continue
  ```

### 4.8 丢失 `w:hyperlink` 超链接防线
Word OpenXML 将外部网页超链接封装在 `<w:hyperlink r:id="...">` 独立容器标签中，且其内部嵌套着 `<w:r>`。若仅递归提取 `<w:r>` 或段落直属子元素，整个超链接容器会被完全丢失，导致正文网址被吞噬，残留形如“下载：，如果已经在...”的语法断裂。
- **防御规范**：显式遍历 `<w:hyperlink>` 标签，从 `_rels/document.xml.rels` 中解析对应的真实目标 URL，并结合子 run 文本输出标准 Markdown 链接语法：
  ```python
  elif tag == f"{{{NS['w']}}}hyperlink":
      hl_id = child.attrib.get(f"{{{NS['r']}}}id")
      url = rel_map.get(hl_id, "")
      link_txt = extract_child_runs(child)
      if url and link_txt:
          runs_parts.append(f"<{url}>" if link_txt == url else f"[{link_txt}]({url})")
  ```

### 4.9 Windows EMF 矢量图跨平台转 PNG 防线
Word 粘贴的系统软件截图或矢量图形常被存储为 Windows 增强型图元文件（`.emf`）。现代网页浏览器和绝大多数 Markdown 预览工具（如 VS Code、GitHub）均不支持直接渲染 `.emf`，标准 PIL 库在缺少 C 底层库时也无法解码，造成图片链接普遍“裂开”。
- **防御规范**：在媒体提取阶段，自动探测 `.emf` 格式并调用无头 LibreOffice 转为高保真 `.png`，随后利用 PIL 差分检测自动裁切生成的冗余白边，并在 Markdown 中无缝引用生成的 PNG 文件：
  ```bash
  libreoffice --headless --convert-to png target.emf --outdir <figures_dir>
  ```

### 4.10 标题碎片化粗体剥除防线
Word 中作者撰写标题时，单句常被内部样式切分为多个连续的加粗 Run（如 `<w:rPr><w:b/></w:rPr>`）。若直接将各 Run 的粗体语法简单拼接，会输出形如 `# **安装** **SQL Server2016** **企业版** **教程**` 的碎片化冗余语法。
- **防御规范**：当段落判定为 `#`、`##`、`###` 或 `####` 大纲标题时，自动剥除内部碎片化的 `**` 包裹，输出纯净的原生 Markdown 标题。

### 4.11 行内小图标与独立配图分流防线
Word 允许将行内小图标（如按钮截图、`SSMS-Setup-CHS.exe` 文件名图标）直接混排在文字 Run 内部。若一刀切将所有图片抽离为独立的 `img_group` 块，会把行内图标强行提到段首而破坏原句语意；反之一刀切全按行内渲染，则会导致连续大图被挤在同一行且丢失图题。
- **防御规范**：根据段落是否包含真实正文文本节点（`<w:t>`）进行分流处理：
  - **图文混排段落**：行内图片就地保留在对应 Run 的字符语境中（如 `...压缩包中的文件 ![icon](path)，然后点安装。`）；
  - **纯图片段落**：作为独立 `img_group` 处理，生成大图与居中图题。

### 4.12 消除 `\xa0` 与不可见空格防线
Word 文档（特别是从网页或中文排版软件复制的内容）常充斥着大量不可见的不换行空格 `\xa0`（`&nbsp;`）以及错乱的标点间距，导致分词、搜索及 Markdown 渲染异常。
- **防御规范**：在行内文本清洗第一步，先行将 `\xa0` 统一归一化替换为标准半角空格，再执行标点缩进净化。

### 4.13 正文连续粗体 Run 粘连合并防线
Word 样式将整句粗体分词为多个 Run 时，若逐个包裹粗体标记会生成形如 `**在实验一中建立好的** **study** **数据库中...**` 的碎片化碎裂粗体。
- **防御规范**：利用安全的 Lambda 正则替换，在最终输出前自动合并相邻的粗体包裹标记：
  ```python
  while re.search(r'\*\*(.*?)\*\*\s*\*\*(.*?)\*\*', text):
      text = re.sub(r'\*\*(.*?)\*\*\s*\*\*(.*?)\*\*', lambda m: f"**{m.group(1).strip()} {m.group(2).strip()}**", text)
  while re.search(r'\*\*(.*?)\*\*\*\*(.*?)\*\*', text):
      text = re.sub(r'\*\*(.*?)\*\*\*\*(.*?)\*\*', lambda m: f"**{m.group(1)}{m.group(2)}**", text)
  ```

### 4.14 中西文与数字混排排版微距规范（盘古之白防线）
Word 依赖虚拟字偶排版（`<w:autoSpaceDE/>` 与 `<w:autoSpaceDN/>`），底层 OpenXML 提取的纯文本中中西文及数字紧贴（如 `SQL程序设计`、`低于1800的`、`70后的`、`substring函数`）。
- **防御规范**：在严格隔离保护 LaTeX 公式（`$...$`）、图片与超链接的前提下，自动在汉字与英文字母、数字间注入标准半角空格，并自动收紧全角中文括号题号（如 `（1）`）后的冗余空格：
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

### 4.15 经典实验与报告大纲词冒号识别防线
中文实验指导书与学术报告的大纲标题习惯在末尾加全角冒号（如 `实验目标：`、`实验内容：`、`注意事项：`）。若标题守卫机械排除所有冒号结尾段落，会导致核心章节大纲全部降级为普通正文。
- **防御规范**：预设常见实验与技术报告核心词库（`实验目标`、`实验内容`、`实验步骤`、`实验要求`、`实验原理`、`思考题` 等），检测到短文本（$\le 25$ 字符）时自动裁剪尾部冒号并规范提升为二级大纲标题（`## `）。

### 4.16 列表项误升格标题防线
严禁对带括号阿拉伯数字 `（1）`、`(1)` 仅凭字符长度 $\le 30$ 就升格为 `####` 标题。这会导致题目列表中短题目变成标题、长题目留在正文，造成文档大纲严重破碎。
- **防御规范**：带括号阿拉伯数字 `（1）` 仅在 Word 显式使用了 `Heading 4` 等大纲样式时才升格；普通段落样式（`Normal`）及由 Word 动态编号（`w:numPr`）生成的条目保持统一的列表项段落。中文大写序数 `（一）` 保持提升为三级标题。

### 4.17 旧版 `.doc` 复合二进制无缝兼容防线
Word 97-2003 `.doc` 文件采用 OLE2/CFBF 复合二进制格式，直接交给 OpenXML 解包器会触发 `BadZipFile` 异常中断。
- **防御规范**：入口嗅探 `.doc` 扩展名与二进制头特征，自动调用无头 LibreOffice 进行无损转换生成 `.docx`，再送入 OpenXML 高保真解析管线：
  ```bash
  libreoffice --headless --convert-to docx input.doc --outdir <workdir>
  ```

---

## 5. 纯净 Markdown 与排版规范

### 5.1 纯净原生 Markdown（严格零 HTML 标签）
严禁输出 `<p align="center">`、`<b>`、`</b>`、`</p>`、`<br>` 等 HTML 标签。统一使用标准 Markdown 语法：
- 图题：
  ```markdown
  ![图题](figures/image.png)

  **图题**
  ```
- 表题：
  ```markdown
  **表 5.1-1 示例**
  ```

### 5.2 图片相对路径与图题智能绑定
所有图片提取至指定目录后，Markdown 内一律使用**相对路径**（`os.path.relpath`），并自动绑定对应图题。

### 5.3 数据表格净化过滤
自动清洗过滤完全为空的废弃行，以及两栏表格中第二栏说明为空的草稿孤立行。

### 5.4 附录源代码智能围栏
当检测到表格单元格包含 `import `、`def `、`class ` 等 Python 关键字时，自动包装为 ````python ... ```` 代码块。

---

## 6. 转化质量终审清单 (Checklist)

- [ ] **零 HTML 标签**：全文无 `<p>`、`<b>`、`</b>`、`</p>`、`<br>` 标签残留。
- [ ] **公式完整映射**：所有编号行间公式均转换为 `$$\n ... \tag{...}\n$$`，且无 `Formula_N` 占位符。
- [ ] **图片相对路径**：所有插图引用均基于当前 Markdown 的相对路径。
- [ ] **无 3 栏伪表格**：行间编号公式均解包为独立 LaTeX 公式。
- [ ] **无幽灵图题残留**：各级标题与段落末尾无遗留的游离图题。
- [ ] **表格对齐与净化完好**：数据表格全部使用标准 GFM 管道符（`|`）呈现，无残缺空行。
- [ ] **附录代码高亮可用**：代码完整且包含合法语法高亮标识。
- [ ] **无裸露 EMF 格式**：所有 Windows EMF 矢量图均已转为跨平台兼容的高清 PNG。
- [ ] **超链接完整还原**：Word 中所有 `w:hyperlink` 超链接均完整转换为 `<url>` 或 `[文本](url)`。
- [ ] **标题纯净规范**：各级 Markdown 标题内无碎片化的 `**` 加粗标记残留。
- [ ] **行内图标语境保留**：正文句中的行内小图标精准就地渲染，未被粗暴脱离为独立块。
- [ ] **正文粗体连贯自然**：全文无 `**A** **B**` 碎片化粗体粘连残留。
- [ ] **中西文混排视觉工整**：汉字与英文字母/数字间符合盘古之白微距规范。
- [ ] **列表与大纲层次清晰**：普通有序题号未被截断误升为 `####` 标题。
- [ ] **双格式兼容稳定**：原生直接支持 `.docx` 与旧版 `.doc` 复合文档。
