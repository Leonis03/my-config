# -*- coding: utf-8 -*-
"""
Render Monospace / CJK Tables & Text directly to high-res PNG image.

Usage:
  uv run --with pillow python table_to_image.py input.txt output.png
  echo -e "┌──────┬──────┐\n│ 中文 │ 100% │\n└──────┴──────┘" | uv run --with pillow python table_to_image.py - output.png
"""

import sys
import os
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cjk_font import get_pillow_font, find_cjk_font

def render_table_to_image(text: str, output_path: str,
                          title: str = "", font_size: int = 18,
                          bg_color: str = "#181825", text_color: str = "#cdd6f4",
                          title_color: str = "#89b4fa", padding: int = 30):
    font = get_pillow_font(size=font_size)
    title_font = get_pillow_font(size=font_size + 4)
    
    lines = text.strip("\r\n").split("\n")
    max_line_w = max((font.getlength(l) for l in lines), default=200)
    line_h = int(font_size * 1.35)
    
    title_h = int((font_size + 4) * 1.8) if title else 0
    img_w = int(max_line_w + padding * 2)
    img_h = int(line_h * len(lines) + title_h + padding * 2)
    
    img = Image.new("RGB", (img_w, img_h), color=bg_color)
    draw = ImageDraw.Draw(img)
    
    y = padding
    if title:
        draw.text((padding, y), title, font=title_font, fill=title_color)
        y += title_h
        
    draw.multiline_text((padding, y), "\n".join(lines), font=font, fill=text_color, spacing=0)
    
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    img.save(output_path)
    print(f"✅ Table image successfully generated: {output_path} ({img_w}x{img_h})")

def main():
    parser = argparse.ArgumentParser(description="Render CJK monospace table to image")
    parser.add_argument("input", help="Path to input text file or '-' for stdin")
    parser.add_argument("output", help="Path to output PNG image")
    parser.add_argument("--title", default="", help="Optional table title")
    parser.add_argument("--font-size", type=int, default=18, help="Font size in pixels")
    parser.add_argument("--theme", choices=["dark", "light"], default="dark", help="Color theme")
    
    args = parser.parse_args()
    
    if args.input == "-":
        content = sys.stdin.read()
    else:
        with open(args.input, "r", encoding="utf-8") as f:
            content = f.read()
            
    if args.theme == "light":
        bg, text, title_c = "#ffffff", "#1e293b", "#0f172a"
    else:
        bg, text, title_c = "#181825", "#cdd6f4", "#89b4fa"
        
    render_table_to_image(content, args.output, title=args.title, font_size=args.font_size,
                          bg_color=bg, text_color=text, title_color=title_c)

if __name__ == "__main__":
    main()
