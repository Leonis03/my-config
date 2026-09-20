# -*- coding: utf-8 -*-
"""
CJK Font Utility Module for WSL / Linux Python Environments.

Provides automatic font discovery across WSL Linux native directories and
Windows host mounted font paths, with plug-and-play helpers for:
- Matplotlib & Seaborn
- Pillow (PIL)
- OpenCV (cv2)
- Multi-processing worker font initialization
"""

import os
import sys
import glob
from pathlib import Path
from typing import Optional, Tuple, List, Union

# Ordered list of high-quality CJK font paths (prioritizes Regular/clean fonts)
DEFAULT_FONT_CANDIDATES = [
    # Windows User Fonts - Sarasa Gothic / Noto SC Regular
    *glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/SarasaTermSC-Regular.ttf"),
    *glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/SarasaMonoSC-Regular.ttf"),
    *glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/NotoSansSC-Regular.ttf"),
    *glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/Sarasa*.ttf"),
    *glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/NotoSansSC-*.ttf"),
    # Windows System Fonts
    "/mnt/c/Windows/Fonts/msyh.ttc",            # 微软雅黑 (Microsoft YaHei)
    "/mnt/c/Windows/Fonts/msyhbd.ttc",          # 微软雅黑 Bold
    "/mnt/c/Windows/Fonts/simhei.ttf",          # 中易黑体 (SimHei)
    "/mnt/c/Windows/Fonts/simsun.ttc",          # 中易宋体 (SimSun)
    "/mnt/c/Windows/Fonts/simkai.ttf",          # 中易楷体 (KaiTi)
    "/mnt/c/Windows/Fonts/simfang.ttf",         # 中易仿宋 (FangSong)
    "/mnt/c/Windows/Fonts/HarmonyOS_Sans_SC_Regular.ttf",
    # Linux Native Open-Source Fonts
    "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",          # 文泉驿微米黑
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",            # 文泉驿正黑
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",  # 思源黑体
    "/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc", # 思源宋体
    "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf"
]


def is_valid_cjk_font(font_path: str) -> bool:
    """Check if the font file genuinely contains CJK glyphs ('中' and '国')."""
    if not font_path or not os.path.exists(font_path):
        return False
    try:
        from matplotlib.ft2font import FT2Font
        ft = FT2Font(font_path)
        return (ft.get_char_index(ord('中')) != 0) and (ft.get_char_index(ord('国')) != 0)
    except Exception:
        # Fallback to path name heuristics if matplotlib is not installed
        lower = font_path.lower()
        return any(k in lower for k in ["sarasa", "notosanscjk", "notosanssc", "msyh", "simhei", "simsun", "wqy", "harmonyos", "kai", "fang"])


def find_cjk_font(custom_candidates: Optional[List[str]] = None) -> Tuple[Optional[str], Optional[str]]:
    """
    Search for the first available and verified CJK font file on the system.
    
    Returns:
        (font_path, font_family_name) or (None, None) if no font is found.
    """
    candidates = custom_candidates or DEFAULT_FONT_CANDIDATES
    for path in candidates:
        if path and os.path.exists(path) and is_valid_cjk_font(path):
            try:
                import matplotlib.font_manager as fm
                fm.fontManager.addfont(path)
                prop = fm.FontProperties(fname=path)
                font_name = prop.get_name()
                
                # Also register matching bold font if available in same dir
                base_stem = Path(path).stem.replace("Regular", "Bold")
                bold_cand = str(Path(path).parent / f"{base_stem}.ttf")
                if os.path.exists(bold_cand) and bold_cand != path:
                    try:
                        fm.fontManager.addfont(bold_cand)
                    except Exception:
                        pass
                        
                return path, font_name
            except ImportError:
                # Matplotlib not installed, return filename stem as fallback name
                return path, Path(path).stem
            except Exception:
                continue
    return None, None


def setup_matplotlib_cjk(custom_font_path: Optional[str] = None) -> str:
    """
    Configure global Matplotlib settings for flawless CJK Chinese & math rendering.
    
    Ensures:
    1. CJK font is dynamically registered in fontManager.
    2. 'font.family' and 'font.sans-serif' prioritize the registered font.
    3. 'axes.unicode_minus' is False so negative signs '-' render correctly as minus, not tofu blocks.
    
    Returns:
        The name of the activated font family.
    """
    import matplotlib.pyplot as plt
    import matplotlib.font_manager as fm
    
    if custom_font_path and os.path.exists(custom_font_path) and is_valid_cjk_font(custom_font_path):
        fm.fontManager.addfont(custom_font_path)
        prop = fm.FontProperties(fname=custom_font_path)
        font_name = prop.get_name()
    else:
        path, font_name = find_cjk_font()
        if not font_name:
            font_name = "DejaVu Sans"
            
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = [font_name, "DejaVu Sans", "Arial"]
    plt.rcParams["axes.unicode_minus"] = False
    return font_name


def get_pillow_font(size: int = 16, font_path: Optional[str] = None):
    """
    Return a Pillow ImageFont instance loaded with an available CJK font.
    """
    from PIL import ImageFont
    
    if not font_path:
        path, _ = find_cjk_font()
        font_path = path
        
    if font_path and os.path.exists(font_path):
        return ImageFont.truetype(font_path, size=size)
    return ImageFont.load_default()


def draw_cv2_cjk_text(cv2_img, text: str, pos: Tuple[int, int],
                      font_size: int = 18, color: Tuple[int, int, int] = (255, 255, 255),
                      font_path: Optional[str] = None):
    """
    Draw Chinese text onto an OpenCV / numpy BGR image array using Pillow bridge.
    
    Args:
        cv2_img: Numpy ndarray (BGR or RGB image format)
        text: Chinese/English string to draw
        pos: (x, y) coordinates for top-left of text
        font_size: Font size in pixels
        color: (B, G, R) color tuple
        font_path: Optional custom font file path
    Returns:
        Updated cv2 image ndarray
    """
    import numpy as np
    from PIL import Image, ImageDraw
    
    is_bgr = len(cv2_img.shape) == 3 and cv2_img.shape[2] == 3
    if is_bgr:
        pil_img = Image.fromarray(cv2_img[:, :, ::-1])
        draw_color = (color[2], color[1], color[0])
    else:
        pil_img = Image.fromarray(cv2_img)
        draw_color = color
        
    draw = ImageDraw.Draw(pil_img)
    font = get_pillow_font(size=font_size, font_path=font_path)
    draw.text(pos, text, font=font, fill=draw_color)
    
    res_arr = np.array(pil_img)
    if is_bgr:
        return res_arr[:, :, ::-1]
    return res_arr
