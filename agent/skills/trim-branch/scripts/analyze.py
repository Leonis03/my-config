#!/usr/bin/env python3
"""Analyze and trim Claude Code conversation JSONL files to resolve branch conflicts.

Usage:
  analyze.py <jsonl_path>                    # Show all branches
  analyze.py <jsonl_path> --extract <line>   # Extract branch containing that line number
  analyze.py <jsonl_path> --extract-tip <N>  # Extract the Nth longest branch (1=longest)
"""

import json
import sys
import argparse
from collections import defaultdict
from pathlib import Path


def load_jsonl(path):
    entries = []
    with open(path) as f:
        for line in f:
            line = line.rstrip()
            if not line:
                continue
            try:
                entries.append((line, json.loads(line)))
            except json.JSONDecodeError:
                entries.append((line, None))
    return entries


def build_index(entries):
    uuid_to_idx = {}
    children = defaultdict(list)
    for i, (raw, obj) in enumerate(entries):
        if obj and "uuid" in obj:
            uuid_to_idx[obj["uuid"]] = i
        if obj and "parentUuid" in obj:
            children[obj["parentUuid"]].append(i)
    return uuid_to_idx, children


def trace_back(entries, uuid_to_idx, start_idx):
    chain = set()
    idx = start_idx
    visited = set()
    while idx is not None and idx >= 0:
        obj = entries[idx][1]
        if obj is None:
            break
        uuid = obj.get("uuid", "")
        if uuid in visited:
            break
        visited.add(uuid)
        chain.add(uuid)
        parent = obj.get("parentUuid", "")
        if parent and parent in uuid_to_idx:
            idx = uuid_to_idx[parent]
        else:
            break
    return chain


def get_content_preview(obj, max_len=80):
    msg_type = obj.get("type", "")
    if msg_type not in ("user", "assistant"):
        return ""
    msg = obj.get("message", {})
    content = msg.get("content", "")
    if isinstance(content, str):
        return content[:max_len]
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text":
                    return item.get("text", "")[:max_len]
                if item.get("type") == "thinking":
                    return "[thinking]"
    return ""


def find_branch_tips(entries, uuid_to_idx, children):
    all_uuids = set(uuid_to_idx.keys())
    parent_uuids = set()
    for i, (raw, obj) in enumerate(entries):
        if obj and "parentUuid" in obj:
            parent_uuids.add(obj["parentUuid"])

    tips = []
    for uuid in all_uuids:
        idx = uuid_to_idx[uuid]
        obj = entries[idx][1]
        if obj is None:
            continue
        msg_type = obj.get("type", "")
        if msg_type not in ("user", "assistant"):
            continue
        if uuid not in parent_uuids or not any(
            entries[c][1] and entries[c][1].get("type") in ("user", "assistant")
            for c in children.get(uuid, [])
        ):
            has_child_msg = False
            for c in children.get(uuid, []):
                cobj = entries[c][1]
                if cobj and cobj.get("type") in ("user", "assistant"):
                    has_child_msg = True
                    break
            if not has_child_msg:
                chain = trace_back(entries, uuid_to_idx, idx)
                depth = len([
                    u for u in chain
                    if entries[uuid_to_idx[u]][1]
                    and entries[uuid_to_idx[u]][1].get("type") in ("user", "assistant")
                ])
                tips.append((idx, depth, uuid))

    tips.sort(key=lambda x: -x[1])
    return tips


def find_branch_points(entries, uuid_to_idx, children):
    points = []
    for parent_uuid, child_indices in children.items():
        msg_children = [
            c for c in child_indices
            if entries[c][1] and entries[c][1].get("type") in ("user", "assistant")
        ]
        if len(msg_children) > 1:
            parent_idx = uuid_to_idx.get(parent_uuid)
            points.append((parent_idx, parent_uuid, msg_children))
    points.sort(key=lambda x: (x[0] if x[0] is not None else -1))
    return points


def extract_branch(entries, uuid_to_idx, chain_uuids):
    output = []
    for i, (raw, obj) in enumerate(entries):
        if obj is None:
            continue
        uuid = obj.get("uuid", "")
        parent = obj.get("parentUuid", "")
        msg_type = obj.get("type", "")
        msg_id = obj.get("messageId", "")

        if uuid in chain_uuids:
            output.append(raw)
        elif msg_type == "system" and parent in chain_uuids:
            output.append(raw)
        elif msg_type == "file-history-snapshot" and msg_id in chain_uuids:
            output.append(raw)
    return output


def analyze(path):
    entries = load_jsonl(path)
    uuid_to_idx, children = build_index(entries)

    branch_points = find_branch_points(entries, uuid_to_idx, children)
    tips = find_branch_tips(entries, uuid_to_idx, children)

    print(f"File: {path}")
    print(f"Total lines: {len(entries)}")
    print(f"Branch points: {len(branch_points)}")
    print(f"Branch tips (leaf nodes): {len(tips)}")
    print()

    if not branch_points:
        print("No branches found — conversation is linear.")
        return

    print("=" * 70)
    print("BRANCH POINTS")
    print("=" * 70)
    for parent_idx, parent_uuid, child_indices in branch_points:
        parent_obj = entries[parent_idx][1] if parent_idx is not None else None
        preview = get_content_preview(parent_obj) if parent_obj else "(root)"
        print(f"\n  L{parent_idx + 1 if parent_idx is not None else '?'}: "
              f"{parent_obj.get('type', '?') if parent_obj else '?'} — {preview}")
        for ci in child_indices:
            cobj = entries[ci][1]
            cpreview = get_content_preview(cobj)
            print(f"    → L{ci + 1}: {cobj.get('type', '')} — {cpreview}")

    print()
    print("=" * 70)
    print("BRANCH TIPS (ordered by depth, deepest first)")
    print("=" * 70)
    for rank, (idx, depth, uuid) in enumerate(tips, 1):
        obj = entries[idx][1]
        preview = get_content_preview(obj)
        msg_type = obj.get("type", "")
        ts = obj.get("timestamp", "")
        print(f"\n  #{rank} L{idx + 1} (depth={depth}, type={msg_type}, ts={ts})")
        print(f"     {preview}")

    print()
    print("=" * 70)
    print("USAGE")
    print("=" * 70)
    print(f"  Extract branch by line:  python3 {sys.argv[0]} {path} --extract <LINE>")
    print(f"  Extract deepest branch:  python3 {sys.argv[0]} {path} --extract-tip 1")


def do_extract(path, target_idx, out_path=None):
    entries = load_jsonl(path)
    uuid_to_idx, children = build_index(entries)

    chain_uuids = trace_back(entries, uuid_to_idx, target_idx)
    output_lines = extract_branch(entries, uuid_to_idx, chain_uuids)

    if out_path is None:
        p = Path(path)
        out_path = str(p.parent / (p.stem + ".trimmed" + p.suffix))

    backup_path = str(Path(path).parent / (Path(path).stem + ".original" + Path(path).suffix))
    import shutil
    if not Path(backup_path).exists():
        shutil.copy2(path, backup_path)
        print(f"Backup: {backup_path}")

    with open(out_path, "w") as f:
        for line in output_lines:
            f.write(line + "\n")

    print(f"Extracted {len(output_lines)} lines (from {len(entries)} total)")
    print(f"Output:  {out_path}")

    tip_obj = entries[target_idx][1]
    preview = get_content_preview(tip_obj)
    print(f"Tip:     L{target_idx + 1} — {preview}")

    return out_path


def main():
    parser = argparse.ArgumentParser(description="Analyze/trim Claude Code JSONL branches")
    parser.add_argument("jsonl", help="Path to JSONL file")
    parser.add_argument("--extract", type=int, metavar="LINE",
                        help="Extract branch containing this line number")
    parser.add_argument("--extract-tip", type=int, metavar="N",
                        help="Extract the Nth longest branch (1=longest)")
    parser.add_argument("--output", "-o", help="Output path (default: <name>.trimmed.jsonl)")
    parser.add_argument("--replace", action="store_true",
                        help="Replace original file (backup created as .original.jsonl)")
    args = parser.parse_args()

    if args.extract is not None:
        target_idx = args.extract - 1
        out_path = do_extract(args.jsonl, target_idx, args.output)
        if args.replace:
            import shutil
            shutil.copy2(out_path, args.jsonl)
            print(f"Replaced: {args.jsonl}")
    elif args.extract_tip is not None:
        entries = load_jsonl(args.jsonl)
        uuid_to_idx, children = build_index(entries)
        tips = find_branch_tips(entries, uuid_to_idx, children)
        n = args.extract_tip
        if n < 1 or n > len(tips):
            print(f"Error: only {len(tips)} branch tips found, requested #{n}")
            sys.exit(1)
        target_idx = tips[n - 1][0]
        out_path = do_extract(args.jsonl, target_idx, args.output)
        if args.replace:
            import shutil
            shutil.copy2(out_path, args.jsonl)
            print(f"Replaced: {args.jsonl}")
    else:
        analyze(args.jsonl)


if __name__ == "__main__":
    main()
