# -*- coding: utf-8 -*-
"""
One-click CJK Font Verification & Smoke Test Script for WSL / Linux.

Tests:
1. Matplotlib single & multi-axis Chinese + math + negative sign rendering (zero-warning mode).
2. Pillow TrueType CJK rendering and monospace table alignment (spacing=0).
3. OpenCV + PIL bridge Chinese overlay.
"""

import os
import sys
import warnings
from pathlib import Path

# Add current directory to path so cjk_font can be imported
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cjk_font import setup_matplotlib_cjk, find_cjk_font, get_pillow_font, draw_cv2_cjk_text

def run_smoke_test(output_dir: str = "/tmp/cjk_smoke_test"):
    os.makedirs(output_dir, exist_ok=True)
    print("=" * 60)
    print("🚀 Running WSL Python CJK Font Smoke Test")
    print("=" * 60)

    # 1. Check Font Discovery
    font_path, font_name = find_cjk_font()
    if not font_path:
        print("❌ ERROR: No CJK font found in standard WSL/Windows paths!")
        print("   Please install fonts-wqy-microhei or mount Windows Fonts directory.")
        sys.exit(1)
        
    print(f"✅ Found Primary CJK Font: '{font_name}'")
    print(f"   Physical Path: {font_path}")

    # 2. Matplotlib Zero-Warning Verification
    print("\n--- 1. Testing Matplotlib & Seaborn Backend ---")
    warnings.filterwarnings("error", category=UserWarning)

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    active_name = setup_matplotlib_cjk()
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4.5), dpi=150)

    # Negative coordinates & LaTeX
    x = np.linspace(-3, 3, 100)
    ax1.plot(x, np.sin(x), label=r"正弦曲线 $y=\sin(x)$", color="#2563eb")
    ax1.plot(x, -np.cos(x), label=r"负余弦基准 $y=-\cos(x)$", color="#dc2626", linestyle="--")
    ax1.set_title(f"【Smoke Test】Matplotlib 中文与负号 ({active_name})", fontsize=11)
    ax1.set_xlabel(r"时间变量 $t \in [-3, 3]$ (秒)")
    ax1.set_ylabel("振幅指标 (dB)")
    ax1.legend()
    ax1.grid(True, linestyle=":", alpha=0.6)

    # Bar chart
    categories = ["算法 A", "算法 B", "优化后 C", "基准 D"]
    scores = [88.5, 91.2, 97.6, 85.0]
    bars = ax2.bar(categories, scores, color=["#60a5fa", "#34d399", "#f59e0b", "#94a3b8"])
    ax2.set_title("【Smoke Test】分类柱状图中文标签", fontsize=11)
    ax2.set_ylabel("综合得分 (分)")
    ax2.set_ylim(70, 105)
    for b in bars:
        ax2.annotate(f"{b.get_height():.1f}", xy=(b.get_x() + b.get_width()/2, b.get_height()),
                     xytext=(0, 2), textcoords="offset points", ha="center", va="bottom", fontsize=9)

    plt.tight_layout()
    mpl_out = os.path.join(output_dir, "smoke_test_matplotlib.png")
    plt.savefig(mpl_out, bbox_inches="tight")
    plt.close(fig)
    print(f"✅ Matplotlib 0-warning test passed: {mpl_out}")

    # 3. Pillow Monospace Table Test
    print("\n--- 2. Testing Pillow Monospace Box-Drawing Table ---")
    from PIL import Image, ImageDraw

    font = get_pillow_font(size=18)
    table_text = """┌──────┬──────────────────────┬────────────┬──────────┐
│ 序号 │ 测试用例名称         │ 响应耗时   │ 验证状态 │
├──────┼──────────────────────┼────────────┼──────────┤
│ 001  │ CJK 字形物理加载     │ 1.2 ms     │ 通过     │
│ 002  │ 负号 '-' 正常渲染    │ 0.8 ms     │ 通过     │
│ 003  │ 多进程 Worker 继承   │ 4.5 ms     │ 通过     │
│ 004  │ 表格竖线无缝闭合     │ 0.5 ms     │ 通过     │
└──────┴──────────────────────┴────────────┴──────────┘"""

    lines = table_text.split("\n")
    max_w = max(font.getlength(l) for l in lines)
    img_w = int(max_w + 50)
    img_h = int(24 * len(lines) + 60)

    img = Image.new("RGB", (img_w, img_h), color="#181825")
    draw = ImageDraw.Draw(img)
    draw.text((25, 15), "⚡ CJK 字符对齐与制表符测试", font=get_pillow_font(size=20), fill="#cdd6f4")
    draw.multiline_text((25, 45), table_text, font=font, fill="#bac2de", spacing=0)

    pil_out = os.path.join(output_dir, "smoke_test_pillow_table.png")
    img.save(pil_out)
    print(f"✅ Pillow Monospace test passed: {pil_out}")

    # 4. OpenCV Bridge Test
    print("\n--- 3. Testing OpenCV Array Bridge ---")
    blank = np.zeros((150, 400, 3), dtype=np.uint8)
    blank[:] = (40, 40, 45)
    res_img = draw_cv2_cjk_text(blank, "OpenCV 图像中文标注正常！", (20, 50), font_size=20, color=(0, 255, 128))
    cv2_out = os.path.join(output_dir, "smoke_test_cv2_bridge.png")
    Image.fromarray(res_img[:, :, ::-1]).save(cv2_out)
    print(f"✅ OpenCV-PIL Bridge test passed: {cv2_out}")

    print("\n" + "=" * 60)
    print("🎉 ALL CJK SMOKE TESTS PASSED CLEANLY WITH ZERO WARNINGS!")
    print(f"📁 Output test figures saved to: {output_dir}")
    print("=" * 60)

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/cjk_smoke_test"
    run_smoke_test(out)
