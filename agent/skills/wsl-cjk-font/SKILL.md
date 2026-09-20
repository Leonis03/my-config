---
name: wsl-cjk-font
description: Configure and render publication-grade Chinese (CJK) text and Unicode box-drawing tables in images via Python (Matplotlib, Seaborn, Pillow, OpenCV) in WSL and Linux environments. Automatically discovers Windows host fonts, user fonts (Sarasa Gothic, Microsoft YaHei), and Linux native CJK packages with zero glyph warnings and strict 2:1 monospace alignment.
allowed-tools: Bash Read
argument-hint: "[smoke-test | table | custom-plot]"
---

# WSL / Linux Python CJK Font Rendering Skill Guide

Rendering Chinese (CJK) text and Unicode diagrams into images in WSL/Linux environments frequently encounters four notorious failures:
1. **Missing Glyphs & Tofu Squares (`UserWarning: Glyph ... missing`)**: Matplotlib defaults to `DejaVu Sans` which contains zero CJK glyphs. Merely setting `plt.rcParams['font.sans-serif'] = ['SimHei']` fails silently in headless Linux because the font alias is not indexed in fontconfig.
2. **Minus Sign Broken (`-` rendered as square)**: Missing `plt.rcParams['axes.unicode_minus'] = False`, causing negative axis coordinates and labels to corrupt.
3. **Multi-Processing Font Reset**: In `joblib.Parallel` or `multiprocessing`, child worker processes do not inherit the parent's in-memory font cache, causing headless child workers to silently revert to DejaVu Sans.
4. **Pillow Table Disconnection & Misalignment**: Unicode box-drawing characters (`┌──┬──┐`, `│`) break into dashed vertical gaps due to default line `spacing`, and columns misalign due to inaccurate half-width vs full-width (2:1) character calculations.
5. **Drive-letter paths silently resolve to nothing**: `Path("C:/Windows/Fonts/msyh.ttc").exists()` is *always* `False` under WSL/Linux — there is no `C:` drive, only the `/mnt/c` mount. Code written on native Windows and moved to WSL therefore finds no font, falls back to DejaVu Sans, and emits tofu squares **without raising**. Always probe `/mnt/c/Windows/Fonts/...` (and a Linux-native fallback), and **raise if every candidate misses** rather than returning a default — a silent fallback is usually discovered only after the figures are already in the paper.

This skill provides an automated font discovery engine and battle-tested rendering patterns for **Matplotlib, Seaborn, Pillow, and OpenCV** in WSL / Linux.

---

## 1. Quick Verification & Tools via `uv`

### 1.1 Run Full CJK Smoke Test (Zero-Warning Verification)
Run an instant diagnostic to verify font loading, minus signs, LaTeX math, and PIL tables:
```bash
uv run --with matplotlib --with pillow --with numpy python $HOME/.gemini/config/skills/wsl-cjk-font/scripts/smoke_test.py
```

### 1.2 Convert Text Table to High-Res Image
Render any formatted table, ASCII chart, or terminal text into a styled PNG:
```bash
# From file
uv run --with pillow python $HOME/.gemini/config/skills/wsl-cjk-font/scripts/table_to_image.py input.txt output.png --title "实验对比结果"

# From pipe
echo -e "┌──────┬──────────┐\n│ 算法 │ 准确率   │\n├──────┼──────────┤\n│ YOLO │ 98.5%    │\n└──────┴──────────┘" | \
uv run --with pillow python $HOME/.gemini/config/skills/wsl-cjk-font/scripts/table_to_image.py - output.png
```

---

## 2. Matplotlib & Seaborn Standard Recipes

### 2.1 The Golden Pattern: Physical Font Path Registration
Never rely on bare font names. Always locate the font file and register via `fm.fontManager.addfont()`:

```python
import os
import glob
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm

def setup_cjk_font():
    """Discover and register the highest quality available CJK font."""
    font_candidates = [
        # 1. Windows User Fonts (Sarasa Gothic / Noto SC) -- glob the account
        #    name, never hardcode it: WSL has no %USERPROFILE%, and a wrong
        #    guess fails the silent way (tofu squares, no exception).
        *glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/SarasaTermSC-Regular.ttf"),
        *glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/NotoSansSC-Regular.ttf"),
        # 2. Windows System Fonts
        "/mnt/c/Windows/Fonts/msyh.ttc",            # Microsoft YaHei
        "/mnt/c/Windows/Fonts/simhei.ttf",          # SimHei
        "/mnt/c/Windows/Fonts/simsun.ttc",          # SimSun
        # 3. Linux Native Fonts
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
    ]
    
    for path in font_candidates:
        if os.path.exists(path):
            fm.fontManager.addfont(path)
            font_name = fm.FontProperties(fname=path).get_name()
            
            # Configure Matplotlib globally
            plt.rcParams['font.family'] = 'sans-serif'
            plt.rcParams['font.sans-serif'] = [font_name, 'DejaVu Sans', 'Arial']
            plt.rcParams['axes.unicode_minus'] = False  # CRITICAL for negative numbers
            return font_name
            
    return 'DejaVu Sans'
```

### 2.2 Multi-Processing Worker Font Setup (`joblib` / `multiprocessing`)
When generating plots in parallel, **each worker process must execute `setup_cjk_font()`**:

```python
from joblib import Parallel, delayed

def render_worker(batch_id, data):
    # Must initialize in worker process context
    setup_cjk_font()
    
    fig, ax = plt.subplots(figsize=(6, 4), dpi=150)
    ax.plot(data['x'], data['y'], label="测试曲线")
    ax.set_title(f"批次 #{batch_id:02d} 排样方案")
    ax.set_xlabel("坐标 X (mm)")
    ax.set_ylabel("坐标 Y (mm)")
    
    plt.tight_layout()
    plt.savefig(f"figures/batch_{batch_id:02d}.png", bbox_inches='tight')
    plt.close(fig)

Parallel(n_jobs=4)(delayed(render_worker)(i, d) for i, d in enumerate(batches))
```

---

## 3. Pillow (PIL) Monospace & Unicode Table Alignment

When rendering Unicode box tables (`┌─┬─┐`, `│`, `└─┴─┘`) in Pillow:
1. **Use True Monospace CJK Fonts**: Use `Sarasa Term SC` or `Sarasa Mono SC` (Chinese characters strictly occupy 2 ASCII width units).
2. **Zero Spacing (`spacing=0`)**: The default line spacing leaves blank pixel gaps between rows, breaking vertical table lines `│`.

```python
import glob
from PIL import Image, ImageDraw, ImageFont

matches = glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/SarasaTermSC-Regular.ttf")
if not matches:                       # raise -- do NOT fall back silently
    raise FileNotFoundError("Sarasa Term SC not found under /mnt/c/Users/*/AppData/...")
font = ImageFont.truetype(matches[0], size=18)

table_text = """┌──────┬──────────────────┬────────────┐
│ 序号 │ 算法模型         │ 准确率     │
├──────┼──────────────────┼────────────┤
│ 001  │ ResNet-50        │ 94.8%      │
│ 002  │ Vision Transf.   │ 96.3%      │
└──────┴──────────────────┴────────────┘"""

lines = table_text.split("\n")
max_w = max(font.getlength(line) for line in lines)
line_h = int(18 * 1.35)

img = Image.new("RGB", (int(max_w + 40), int(line_h * len(lines) + 40)), color="#181825")
draw = ImageDraw.Draw(img)

# Set spacing=0 to ensure seamless vertical table lines
draw.multiline_text((20, 20), table_text, font=font, fill="#cdd6f4", spacing=0)
img.save("table_perfect.png")
```

---

## 4. OpenCV (cv2) Chinese Text Bridge

OpenCV's `cv2.putText` cannot render non-ASCII characters. Use the numpy-PIL bridge:

```python
import numpy as np
from PIL import Image, ImageDraw, ImageFont

def cv2_draw_chinese(cv2_bgr_img, text, pos, font_size=18, color_bgr=(255, 255, 255), font_path=None):
    # Convert BGR (cv2) to RGB (PIL)
    pil_img = Image.fromarray(cv2_bgr_img[:, :, ::-1])
    draw = ImageDraw.Draw(pil_img)
    
    font = ImageFont.truetype(font_path or "/mnt/c/Windows/Fonts/msyh.ttc", size=font_size)
    draw.text(pos, text, font=font, fill=(color_bgr[2], color_bgr[1], color_bgr[0]))
    
    # Convert RGB back to BGR ndarray
    return np.array(pil_img)[:, :, ::-1]
```

---

## 5. WSL Font Discovery Hierarchy Reference

| Priority | Font Name | Typical WSL Path | Characteristics |
| :--- | :--- | :--- | :--- |
| **1 (Best Monospace)** | **Sarasa Term SC** (更纱黑体) | `/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/SarasaTermSC-Regular.ttf` | Perfect 2:1 CJK-to-ASCII width, flawless box drawing |
| **2 (Best UI Font)** | **Microsoft YaHei** (微软雅黑) | `/mnt/c/Windows/Fonts/msyh.ttc` | Clean modern sans-serif, universal on Windows host |
| **3 (Academic Standard)** | **SimHei** (黑体) / **SimSun** (宋体) | `/mnt/c/Windows/Fonts/simhei.ttf` / `simsun.ttc` | Classic standard fonts for papers and reports |
| **4 (Linux OpenSource)** | **WenQuanYi Micro Hei** (文泉驿) | `/usr/share/fonts/truetype/wqy/wqy-microhei.ttc` | Standard Ubuntu/Debian CJK package (`fonts-wqy-microhei`) |
| **5 (Linux Google)** | **Noto Sans CJK SC** (思源黑体) | `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc` | High coverage open-source font (`fonts-noto-cjk`) |

---

## 6. Verification Checklist

- [ ] **Physical Path Registered**: Used `fm.fontManager.addfont(path)` with a verified CJK `.ttf` or `.ttc` file.
- [ ] **Unicode Minus Enabled**: `plt.rcParams['axes.unicode_minus'] = False` is set.
- [ ] **Worker Context Initialized**: Multi-process workers invoke the font setup function on startup.
- [ ] **PIL Monospace Spacing**: `draw.multiline_text(..., spacing=0)` configured for box-drawing tables.
- [ ] **Zero Glyph Warnings**: Running with `warnings.filterwarnings('error', category=UserWarning)` completes without missing glyph warnings.
