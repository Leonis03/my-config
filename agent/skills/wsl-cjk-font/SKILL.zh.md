---
name: wsl-cjk-font
description: 在 WSL 和 Linux 环境下使用 Python（Matplotlib、Seaborn、Pillow、OpenCV）配置和打印出版级中文字体与 Unicode 制表符对齐图片。自动探测 Windows 宿主机字体、用户字体（更纱黑体/微软雅黑）与 Linux 原生中文字体包，确保零 Glyph 警告与严格 2:1 等宽对齐。
allowed-tools: Bash Read
argument-hint: "[smoke-test | table | custom-plot]"
---

# WSL / Linux Python 中文字体打印与图像渲染技能指南

在 WSL / Linux 环境下使用 Python 生成带中文的图表或图像时，通常会遇到以下 4 个典型问题：
1. **字形缺失与豆腐块方框（`UserWarning: Glyph ... missing`）**：Matplotlib 默认字体为 `DejaVu Sans`，不含中文字符。仅设置 `plt.rcParams['font.sans-serif'] = ['SimHei']` 在无 GUI 或 Linux 环境下会静默失效并回退为方块。
2. **负号 `-` 乱码破损**：未设置 `plt.rcParams['axes.unicode_minus'] = False`，导致坐标轴负数符号渲染为方框。
3. **多进程渲染字体丢失**：在 `joblib.Parallel` 或 `multiprocessing` 多进程绘图时，子进程未继承主进程内存中的字体注册状态，导致子进程静默回退到默认字体。
4. **Pillow 制表符断裂与错位**：绘制 Unicode 表格边框（`┌──┬──┐`、`│`）时，由于默认 `spacing` 间距导致垂直竖线断节，且中英文字符宽度未严格按 2:1 计算导致列对齐错位。
5. **盘符路径永远探测不到**：`Path("C:/Windows/Fonts/msyh.ttc").exists()` 在 WSL/Linux 下**恒为 `False`** —— 系统里没有 `C:` 盘，只有 `/mnt/c` 挂载点。在原生 Windows 上写好的代码搬到 WSL 后会找不到字体、静默回退 DejaVu Sans、输出豆腐块，**且完全不报错**。候选路径必须用 `/mnt/c/Windows/Fonts/...`（外加 Linux 本地字体兜底），并且**全部候选都落空时应直接抛异常**而不是返回默认字体 —— 静默回退往往等到图已经贴进论文才被发现。

本技能提供了 WSL 环境下的自动中文字体探测引擎与经过实战检验的标准渲染模版（支持 **Matplotlib、Seaborn、Pillow、OpenCV**）。

---

## 1. 快速验证与命令行工具

### 1.1 一键运行 CJK 字体冒烟测试（零警告验证）
快速验证当前 WSL 环境的 Matplotlib 中文、负号、LaTeX 混排以及 Pillow 制表符渲染：
```bash
uv run --with matplotlib --with pillow --with numpy python $HOME/.gemini/config/skills/wsl-cjk-font/scripts/smoke_test.py
```

### 1.2 将文本表格/代码直接转为高清图片
将任意格式化文本、ASCII 制表符或终端输出渲染为精美 PNG 图片：
```bash
# 从文件渲染
uv run --with pillow python $HOME/.gemini/config/skills/wsl-cjk-font/scripts/table_to_image.py input.txt output.png --title "实验对比结果"

# 从管道标准输入渲染
echo -e "┌──────┬──────────┐\n│ 算法 │ 准确率   │\n├──────┼──────────┤\n│ YOLO │ 98.5%    │\n└──────┴──────────┘" | \
uv run --with pillow python $HOME/.gemini/config/skills/wsl-cjk-font/scripts/table_to_image.py - output.png
```

---

## 2. Matplotlib 与 Seaborn 最佳实践

### 2.1 黄金法则：通过物理路径显式注册字体
绝不依赖单纯的字体别名字符串，始终通过 `fontManager.addfont()` 加载真实存在的字体文件：

```python
import os
import glob
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm

def setup_cjk_font():
    """自动发现并注册最高优先级的可用中文字体"""
    font_candidates = [
        # 1. Windows 用户字体（更纱黑体 / 思源黑体）——用通配符匹配账户名，不要写死：
        #    WSL 里没有 %USERPROFILE%，而猜错账户名的失败方式是静默的（出豆腐块、不抛异常）
        *glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/SarasaTermSC-Regular.ttf"),
        *glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/NotoSansSC-Regular.ttf"),
        # 2. Windows 系统字体
        "/mnt/c/Windows/Fonts/msyh.ttc",            # 微软雅黑
        "/mnt/c/Windows/Fonts/simhei.ttf",          # 中易黑体
        "/mnt/c/Windows/Fonts/simsun.ttc",          # 中易宋体
        # 3. Linux 原生开源中文字体
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
    ]
    
    for path in font_candidates:
        if os.path.exists(path):
            fm.fontManager.addfont(path)
            font_name = fm.FontProperties(fname=path).get_name()
            
            # 全局配置 Matplotlib
            plt.rcParams['font.family'] = 'sans-serif'
            plt.rcParams['font.sans-serif'] = [font_name, 'DejaVu Sans', 'Arial']
            plt.rcParams['axes.unicode_minus'] = False  # 确保负号 '-' 正常渲染
            return font_name
            
    return 'DejaVu Sans'
```

### 2.2 多进程并行绘图中的 Worker 字体初始化 (`joblib` / `multiprocessing`)
多进程并行渲染图表时，**每个 Worker 进程内部必须在绘图前执行 `setup_cjk_font()`**：

```python
from joblib import Parallel, delayed

def render_worker(batch_id, data):
    # 子进程进入后第一时间执行字体初始化
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

## 3. Pillow (PIL) 等宽与制表符无缝对齐

在 Pillow 中绘制 Unicode 制表符表格（`┌─┬─┐`, `│`, `└─┴─┘`）时：
1. **使用严格等宽字体**：选用 `Sarasa Term SC`（更纱黑体），汉字与西文字符宽度严格满足 2:1。
2. **设置行距为 0 (`spacing=0`)**：Pillow 默认的多行间隙会导致表格竖线 `│` 断节，设置 `spacing=0` 后可实现上下垂直无缝闭合。

```python
import glob
from PIL import Image, ImageDraw, ImageFont

matches = glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/SarasaTermSC-Regular.ttf")
if not matches:                       # 直接抛错，不要静默回退
    raise FileNotFoundError("在 /mnt/c/Users/*/AppData/... 下找不到 Sarasa Term SC")
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

# 设置 spacing=0 保证制表符垂直竖线无缝相连
draw.multiline_text((20, 20), table_text, font=font, fill="#cdd6f4", spacing=0)
img.save("table_perfect.png")
```

---

## 4. OpenCV (cv2) 中文绘制桥接

OpenCV 自带的 `cv2.putText` 不支持 CJK 中文，可通过 NumPy 与 Pillow 桥接实现零开销绘制：

```python
import numpy as np
from PIL import Image, ImageDraw, ImageFont

def cv2_draw_chinese(cv2_bgr_img, text, pos, font_size=18, color_bgr=(255, 255, 255), font_path=None):
    # 将 BGR (cv2) 转为 RGB (PIL)
    pil_img = Image.fromarray(cv2_bgr_img[:, :, ::-1])
    draw = ImageDraw.Draw(pil_img)
    
    font = ImageFont.truetype(font_path or "/mnt/c/Windows/Fonts/msyh.ttc", size=font_size)
    draw.text(pos, text, font=font, fill=(color_bgr[2], color_bgr[1], color_bgr[0]))
    
    # 转换回 BGR NumPy 数组
    return np.array(pil_img)[:, :, ::-1]
```

---

## 5. WSL 常用中文字体路径对照表

| 优先级 | 字体名称 | 典型 WSL 物理路径 | 适用场景 |
| :--- | :--- | :--- | :--- |
| **1（最佳等宽）** | **更纱黑体** (`Sarasa Term SC`) | `/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/SarasaTermSC-Regular.ttf` | 严格 2:1 中西文等宽，Unicode 表格对齐首选 |
| **2（现代无衬线）** | **微软雅黑** (`Microsoft YaHei`) | `/mnt/c/Windows/Fonts/msyh.ttc` | 现代清晰 UI 字体，Windows 宿主机默认具备 |
| **3（学术报告）** | **中易黑体 / 宋体** (`SimHei` / `SimSun`) | `/mnt/c/Windows/Fonts/simhei.ttf` / `simsun.ttc` | 论文、数模竞赛标准学术图表字体 |
| **4（Linux 开源）** | **文泉驿微米黑** (`WenQuanYi Micro Hei`) | `/usr/share/fonts/truetype/wqy/wqy-microhei.ttc` | Ubuntu/WSL 基础包 (`fonts-wqy-microhei`) |
| **5（思源系列）** | **思源黑体** (`Noto Sans CJK SC`) | `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc` | 开源高字形覆盖率字体 (`fonts-noto-cjk`) |

### 宿主机根本没有 `simhei.ttf` 时

候选 3 依赖 Windows 侧装着中文字体包。如果这台机器卸过中文语言功能、或做过字体替换，`/mnt/c/Windows/Fonts/simhei.ttf` 会直接不存在——探测落空，和路径写错的表现一模一样。先确认是哪一种：

```bash
ls -la /mnt/c/Windows/Fonts/simhei.ttf /mnt/c/Windows/Fonts/msyh.ttc 2>&1
```

补装要在 **Windows 侧**执行（管理员 PowerShell）：

```powershell
Add-WindowsCapability -Online -Name "Language.Fonts.Hans~~~und-HANS~0.0.1.0"
```

这条要从微软服务器拉，网络不稳时会反复失败。**离线装法**：从 my.visualstudio.com 搜
`Languages and Optional Features for Windows 11` 下对应版本的 ISO，挂载后指定 `-Source`：

```powershell
Add-WindowsCapability -Online `
  -Name "Language.Fonts.Hans~~~und-HANS~0.0.1.0" `
  -Source "<挂载盘符>:\LanguagesAndOptionalFeatures" `
  -LimitAccess
```

`-LimitAccess` 不能省：**不加的话即使给了 `-Source`，它仍会先去连 Windows Update**，离线就白准备了。

装完在 WSL 侧无需重启，drvfs 立即可见；但 matplotlib 有字体缓存，要 `rm -rf ~/.cache/matplotlib` 后重试。

不想动 Windows 的话，直接用候选 4/5 的 Linux 开源字体即可——学术图表用思源黑体完全够。

---

## 6. 输出质量验证检查单

- [ ] **物理文件注册**：使用 `fm.fontManager.addfont(path)` 直接加载已验证存在的 CJK 字体文件。
- [ ] **负号设置**：显式设置 `plt.rcParams['axes.unicode_minus'] = False`。
- [ ] **多进程上下文**：在多进程 Worker 函数中执行字体初始化。
- [ ] **Pillow 表格间距**：绘制制表符时配置 `spacing=0`。
- [ ] **零警告验证**：在 `warnings.filterwarnings('error', category=UserWarning)` 下运行无 Glyph 缺失警告。
