---
name: pdf-to-md-zh
description: 将 PDF 文档（尤其是学术论文、数学建模报告与 WPS/Word 导出的 PDF）高保真转换为 Markdown，包含精准数学公式纠错（LaTeX $...$ 和 $$...$$）、纯净原生 Markdown（零 HTML 标签）、图片相对路径引用、段落平滑无缝连接、GFM 规范表格重构、附录代码块几何缩进提取与 300 DPI 公式视觉真值切片比对。
allowed-tools: Bash Read
argument-hint: "[文档.pdf] [输出.md]"
arguments: [pdf_file]
---

# PDF 转 Markdown 高保真转换与视觉公式纠错指南

将学术、数学与工程类 PDF 文档（尤其是 WPS 或 Word 导出的 PDF）转换为 Markdown 时，普遍面临四大物理级痛点：
1. **公式编码乱码（PUA 字体陷阱）**：MathType 或 Word 公式编辑器在导出 PDF 时，大量使用 **私有使用区（PUA）Unicode 字符**（如 `\uf0ce`、`\uf03d`、`\uf0e5`、`\uf0ea`、`\uf0e9`、`\uf065`、`\uf070`）映射 `Symbol`、`MT Extra` 等数学字体。普通文本提取器解析出来的全是非法字符或方块乱码。
2. **二维公式碎裂与假换行**：分式、求和上下标、积分与矩阵被切碎为上下错位的多行离散字符片段（如 `l w\nLB\nL W\n\uf0ce...`），正文段落句子被无故硬换行切断。
3. **HTML 标签污染与绝对路径硬编码**：粗暴转换器常注入 `<p align="center"><b>...</b></p>` 及系统绝对路径（如 `/home/...`），破坏了 Markdown 的通用性与跨平台可移植性。
4. **矢量图形与多图页面丢失**：流程图等矢量图形被常规位图提取器丢弃，同页多图场景常全部错绑到第一张图。

本 Skill 提供了 **通用 PDF 布局结构逆向重建引擎 + 视觉真值公式纠错流（Visual Formula Grounding）**，一键输出纯净原生 Markdown 文档（无 HTML 标签、全相对路径、平滑段落、标准 LaTeX 公式、GFM 规范表格、语法高亮代码块）。

---

## 1. 基于 `uv` 的一键快速执行

### 1.1 直接执行 PDF 转 Markdown
```bash
# 基础转换（默认使用相对图片路径 "figures_<文件名>/"）
PYTHONUNBUFFERED=1 uv run --python 3.12 --with pymupdf python $HOME/.gemini/config/skills/pdf-to-md/scripts/convert_pdf_to_md.py input.pdf output.md

# 带有外部公式真值字典映射、行内符号字典与自定义相对图片目录的转换
PYTHONUNBUFFERED=1 uv run --python 3.12 --with pymupdf python $HOME/.gemini/config/skills/pdf-to-md/scripts/convert_pdf_to_md.py input.pdf output.md \
    --figures-dir figures \
    --formula-map formula_map.json \
    --inline-map inline_map.json
```

### 1.2 高清公式切片与矢量图提取（用于多模态视觉比对与 AI 纠错）
一键扫描 PDF 中的公式编号与特征区域，导出 300 DPI 超清整页图、单公式小切片（如 `crops/eq_5.1-1.png`）、矢量图切片（`vector_figures/`），并**自动生成公式字典模板** `formula_map.template.json`：
```bash
PYTHONUNBUFFERED=1 uv run --python 3.12 --with pymupdf python $HOME/.gemini/config/skills/pdf-to-md/scripts/extract_pdf_formula_crops.py input.pdf --out-dir pdf_formula_pages
```

---

## 2. 视觉真值公式纠错工作流 (Visual Formula Grounding)

当处理复杂的数学公式、方程组与大括号分段函数时，采用以下**四步视觉纠错闭环**：

```
[原始 document.pdf] 
       │ 
       ▼ (1. 自动截取 300 DPI 公式框，并生成 formula_map.template.json)
[pdf_formula_pages/crops/eq_5.1-1.png, formula_map.template.json]
       │
       ▼ (2. 喂给多模态 AI (Vision API / VLM) 批量填入标准 LaTeX 代码)
[formula_map.json: {"5.1-1": "\\min K = \\sum_{p \\in \\mathcal{P}} z_p"}]
       │
       ▼ (3. 传入 convert_pdf_to_md.py 自动化渲染替换)
[convert_pdf_to_md.py --formula-map formula_map.json]
       │
       ▼ (4. 自动保留推导说明文字，输出出版级 Markdown)
[最终出版级无错 Markdown 文件 (output.md)]
```

### 2.1 常见 PUA 乱码数学符号速查映射表

| PUA Unicode | 原始字体 | 真实数学含义 | 标准 LaTeX 语法 |
| :--- | :--- | :--- | :--- |
| `\uf03d` / `\uff1d` | Symbol | 等号 $=$ | `=` |
| `\uf0ce` | Symbol | 属于符号 $\in$ | `\in` |
| `\uf0e5` | Symbol | 求和符号 $\sum$ | `\sum` |
| `\uf0a3` | Symbol | 小于等于 $\le$ | `\le` |
| `\uf0b3` | Symbol | 大于等于 $\ge$ | `\ge` |
| `\uf0e9` / `\uf0f9` | MT Extra | 向上取整符号 $\lceil \dots \rceil$ | `\lceil \dots \rceil` |
| `\uf0ea` / `\uf0fa` | MT Extra | 向下取整/大括号 $\lfloor \dots \rfloor$ | `\lfloor \dots \rfloor` 或 `\begin{cases}` |
| `\uf02b` | Symbol | 加号 $+$ | `+` |
| `\uf02d` | Symbol | 减号 $-$ | `-` |
| `\uf0b4` / `\u00d7` | Symbol | 乘号 $\times$ | `\times` 或 `\cdot` |
| `\uf022` | Symbol | 任意 $\forall$ | `\forall` |
| `\uf0b0` / `\u00b0` | Symbol | 角度度数 $^{\circ}$ | `^{\circ}` |
| `\uf065` | Symbol | 误差 $\varepsilon$ | `\varepsilon` |
| `\uf070` | Symbol | 置换/脉冲索引 $\pi$ | `\pi` |
| `\uf0b6` | Symbol | 偏导数 $\partial$ | `\partial` |
| `\uf0b9` | Symbol | 不等于 $\neq$ | `\neq` |
| `\uf044` | Symbol | 增量 $\Delta$ | `\Delta` |
| `\uf051` | Symbol | 矩阵状态 $\boldsymbol{\Theta}$ | `\boldsymbol{\Theta}` |
| `\uf071` | Symbol | 角度 $\theta$ | `\theta` |
| `\uf072` | Symbol | 损失函数 $\rho$ | `\rho` |
| `\uf06c` | Symbol | 经度 $\lambda$ | `\lambda` |
| `\uf06a` | Symbol | 纬度 $\varphi$ | `\varphi` |
| `\uf0bc` | Symbol | 省略号 $\cdots$ | `\cdots` |

### 2.2 多模态 AI 读图提示词模板 (Prompt Template)
将裁剪的公式小图（`crops/eq_5.1-1.png`）发送给 Vision 模型：
```markdown
请仔细观察图片中的数学公式（包含右侧公式编号），输出标准、严谨的 LaTeX 代码：
- 行间公式采用：
  $$
  <LaTeX_代码> \tag{编号}
  $$
- 保证上下标、求和/积分下标集合、矩阵与大括号对齐完全正确。
- 仅输出纯净的 LaTeX 代码块，无需冗余解释。
```

---

## 3. PDF 布局与语义重构规范

### 3.1 纯净原生 Markdown 规范（严禁 HTML 标签污染）
输出文档中**严禁使用** `<p align="center">`、`<b>`、`</b>`、`</p>` 等 HTML 标签，统一采用纯粹的 Markdown 语法：
- 插图与图题格式：
  ```markdown
  ![图题](figures/fig_1.jpeg)

  **图题**
  ```
- 表格标题格式：
  ```markdown
  **表题**
  ```

### 3.2 严禁绝对路径，统一采用相对路径
生成的 Markdown 中引用的所有图片资源，必须严格使用相对于当前 `.md` 文件的**相对路径**（如 `figures/fig_p2_1.jpeg`），禁止写入系统根目录绝对路径。

### 3.3 多图邻近几何匹配与矢量图兜底
- 同一页面包含多张插图时，引擎基于垂直几何坐标将图题精准匹配至其正上方的图片，彻底解决多图页面全部错绑首图的问题；
- 当遇到流程图、架构图等无位图的矢量绘制区域时，自动裁剪视口高分辨率切片并注入链接。

### 3.4 公式与前置推导文本自动分离
当同一文本块中同时包含推导文字与块级公式时，引擎自动将前置推导文字（如“由几何关系可得公式如下：”）剥离并作为正文保留，杜绝整块文本被公式一刀切覆盖。

### 3.5 高准度标题守卫（Heading Candidate Guard）
仅当段落满足字符长度 $\le 50$、非句号/冒号结尾、非引出语（“如下”、“所示”）时才允许提升为 Markdown 标题，防止长列表项误判为大纲。

### 3.6 段落平滑连接与英文连字符自动修复
- 句子内部由于换行造成的硬断裂自动无缝融合；
- 跨行被连字符切断的英文单词（如 `optimi-\nzation`）自动还原为完整单词。

### 3.7 GFM 规范表格净化
自动检测表格结构转化为标准 Markdown 管道表格，自动剔除空行与无意义的孤立残缺草稿行。

### 3.8 附录源代码几何缩进与智能围栏
检测到 `### 附录二` 等标题后，利用几何坐标还原算法（`extract_page_lines_with_indent`）自动恢复 Python 4 空格层次缩进，并包裹为语法高亮的 ````python ... ```` 代码块。

---

## 4. 转化质量终审清单 (Checklist)

- [ ] **零 HTML 标签残留**：绝不出现 `<p>`、`<b>`、`</b>`、`</p>` 等任何标签。
- [ ] **图片相对路径**：所有插图引用必须为相对路径（如 `figures/fig_1.jpeg`）。
- [ ] **同页多图零错位**：多图页面中各个图题精准绑定对应图片，无图片遗失或错绑。
- [ ] **段落完整连贯**：句子中间无莫名换行，英文连字符单词还原完整。
- [ ] **公式与文本分离完好**：公式前后的说明文字未被公式块误杀覆盖。
- [ ] **无 PUA 乱码残留**：输出 Markdown 中彻底根除 `\uf0ce`、`\uf03d`、`\uf0e5`、`\uf065`、`\uf070` 等私有区字符。
- [ ] **公式标准 LaTeX 化**：所有行间公式均转化为带编号标签的 `$$\n ... \tag{...}\n$$` 格式。
- [ ] **表格对齐与净化完好**：数据表格全部使用标准 GFM 管道符（`|`）呈现，无残缺空行。
- [ ] **代码高亮可用**：附录源代码包裹在合法的 ````python 代码块中，缩进层次清晰。
