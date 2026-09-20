#!/usr/bin/env python3
"""
clean_transcript.py: Utility to clean video transcript files.
Removes timestamps (e.g. 00:00, 00:00:00, [00:00:00]) and optionally merges subtitle lines into fluent paragraphs.
"""

import argparse
import re
import sys
from pathlib import Path


TIMESTAMP_PATTERN = re.compile(r"^\s*(\[?\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?\]?)\s*")


def clean_line_timestamps(text: str) -> str:
    """Strip leading timestamps from each line while preserving line structure."""
    lines = text.splitlines()
    cleaned = [TIMESTAMP_PATTERN.sub("", line) for line in lines]
    return "\n".join(cleaned)


def merge_to_paragraphs(text: str) -> str:
    """
    Strip timestamps and merge short fragmented subtitle lines into continuous paragraphs.
    Paragraph breaks are preserved when there are explicit empty lines or major punctuation breaks.
    """
    cleaned_text = clean_line_timestamps(text)
    raw_lines = [line.strip() for line in cleaned_text.splitlines()]

    paragraphs = []
    current_para = []

    for line in raw_lines:
        if not line:
            if current_para:
                paragraphs.append("".join(current_para))
                current_para = []
            continue

        # Check if previous ended with terminal punctuation (Chinese or English)
        if current_para and current_para[-1][-1] in "。！？!?…\n":
            paragraphs.append("".join(current_para))
            current_para = [line]
        else:
            current_para.append(line)

    if current_para:
        paragraphs.append("".join(current_para))

    return "\n\n".join(paragraphs) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Clean video transcript markdown files.")
    parser.add_argument("input_file", type=Path, help="Path to transcript markdown file.")
    parser.add_argument("-o", "--output", type=Path, default=None, help="Output file path (default: stdout or overwrite if -i).")
    parser.add_argument("-i", "--inplace", action="store_true", help="Modify file in-place.")
    parser.add_argument("-p", "--paragraphs", action="store_true", help="Merge subtitle fragments into flowing paragraphs.")

    args = parser.parse_args()

    if not args.input_file.exists():
        print(f"Error: File {args.input_file} does not exist.", file=sys.stderr)
        sys.exit(1)

    content = args.input_file.read_text(encoding="utf-8")

    if args.paragraphs:
        result = merge_to_paragraphs(content)
    else:
        result = clean_line_timestamps(content) + "\n"

    if args.inplace:
        args.input_file.write_text(result, encoding="utf-8")
        print(f"Successfully cleaned timestamps in-place: {args.input_file}")
    elif args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(result, encoding="utf-8")
        print(f"Successfully wrote cleaned transcript to: {args.output}")
    else:
        sys.stdout.write(result)


if __name__ == "__main__":
    main()

