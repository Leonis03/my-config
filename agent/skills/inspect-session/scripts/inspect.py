#!/usr/bin/env python3
"""inspect.py - Multi-agent conversation transcript inspector and audit tool.

Supports:
- Claude Code session JSONL files (~/.claude/projects/.../*.jsonl)
- Antigravity / Gemini CLI transcript JSONL files (~/.gemini/.../transcript.jsonl)

Capabilities:
- Audit Git operations (commits, push, diff, branch, status)
- Audit File modifications (Write, Edit, Patch) with line and diff context
- Reconstruct DAG branch topology and trace specific branch lineages
- Compare divergent branches (--diff-branches A B)
- Chronological timeline inspection (--timeline)
- Filter failed commands and tool errors (--errors)
- Full-text keyword search (--search / --grep)
- Export to structured Markdown or JSON
"""

import argparse
import json
import os
import re
import signal
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# Handle broken pipes gracefully when piped to head/tail/less
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):
    pass


class ToolRecord:
    def __init__(
        self,
        tool_id: str,
        name: str,
        category: str,
        summary: str,
        details: Dict[str, Any],
        is_error: bool = False,
        output: str = "",
        line_num: int = 0,
    ):
        self.tool_id = tool_id
        self.name = name
        self.category = category  # 'git', 'file_write', 'file_read', 'shell', 'web', 'other'
        self.summary = summary
        self.details = details
        self.is_error = is_error
        self.output = output
        self.line_num = line_num

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tool_id": self.tool_id,
            "name": self.name,
            "category": self.category,
            "summary": self.summary,
            "details": self.details,
            "is_error": self.is_error,
            "output_preview": self.output[:300] if self.output else "",
            "line_num": self.line_num,
        }


class TranscriptMessage:
    def __init__(
        self,
        index: int,
        role: str,
        text: str = "",
        uuid: Optional[str] = None,
        parent_uuid: Optional[str] = None,
        timestamp: Optional[str] = None,
        raw_obj: Optional[Dict[str, Any]] = None,
    ):
        self.index = index
        self.role = role  # 'user', 'assistant', 'system', 'meta'
        self.text = text
        self.uuid = uuid
        self.parent_uuid = parent_uuid
        self.timestamp = timestamp
        self.tools: List[ToolRecord] = []
        self.raw_obj = raw_obj or {}

    def to_dict(self) -> Dict[str, Any]:
        return {
            "index": self.index,
            "role": self.role,
            "uuid": self.uuid,
            "parent_uuid": self.parent_uuid,
            "timestamp": self.timestamp,
            "text": self.text,
            "tools": [t.to_dict() for t in self.tools],
        }


def parse_git_command(cmd: str) -> Optional[Dict[str, Any]]:
    """Parse git commands from shell strings."""
    if not cmd or "git" not in cmd:
        return None
    # Match git commands (handling subshells, cd ... && git ..., etc.)
    git_pattern = re.compile(
        r"(?:^|[;&|\s])git(?:\s+-[A-Za-z0-9_-]+(?:\s+[^\s;&|]+)?)*\s+([a-z-]+)(.*?)(?=[;&|\n]|$)"
    )
    match = git_pattern.search(cmd)
    if not match:
        return None
    subcmd = match.group(1).strip()
    args = match.group(2).strip()
    return {
        "full_command": cmd.strip(),
        "subcommand": subcmd,
        "args": args,
    }


def categorize_tool(
    name: str, args: Dict[str, Any], output: str = "", is_error: bool = False
) -> Tuple[str, str, Dict[str, Any]]:
    """Categorize tool and generate human-friendly summary."""
    category = "other"
    summary = name
    details: Dict[str, Any] = {}

    name_lower = name.lower()

    # Claude Code Bash / Gemini run_command
    if name_lower in ("bash", "run_command"):
        cmd = args.get("command") or args.get("CommandLine") or ""
        desc = args.get("description") or args.get("toolSummary") or ""
        details["command"] = cmd
        details["description"] = desc

        git_info = parse_git_command(cmd)
        if git_info:
            category = "git"
            sub = git_info["subcommand"]
            sub_args = git_info["args"]
            summary = f"git {sub}" + (f" {sub_args[:60]}" if sub_args else "")
            details["git_subcommand"] = sub
            details["git_args"] = sub_args
        else:
            category = "shell"
            first_line = cmd.strip().split("\n")[0]
            summary = first_line[:80] if first_line else desc[:80]

    # File writes / edits
    elif name_lower in ("write", "filewrite", "write_to_file"):
        category = "file_write"
        path = args.get("file_path") or args.get("TargetFile") or ""
        content = args.get("content") or args.get("CodeContent") or ""
        details["file_path"] = path
        details["content_length"] = len(content)
        summary = f"Write {Path(path).name} ({len(content)} bytes)"

    elif name_lower in ("edit", "fileedit", "replace_file_content"):
        category = "file_write"
        path = args.get("file_path") or args.get("TargetFile") or ""
        details["file_path"] = path
        old_s = args.get("old_string") or args.get("TargetContent") or ""
        new_s = args.get("new_string") or args.get("ReplacementContent") or ""
        details["old_lines"] = old_s.count("\n") + 1 if old_s else 0
        details["new_lines"] = new_s.count("\n") + 1 if new_s else 0
        summary = f"Edit {Path(path).name} (-{details['old_lines']}/+{details['new_lines']} lines)"

    # File reads
    elif name_lower in ("read", "fileread", "view_file"):
        category = "file_read"
        path = args.get("file_path") or args.get("AbsolutePath") or ""
        details["file_path"] = path
        summary = f"Read {Path(path).name}"

    elif name_lower in ("grep", "glob", "ls"):
        category = "search"
        pattern = args.get("pattern") or args.get("path") or ""
        summary = f"{name} {pattern}"
        details["pattern"] = pattern

    elif "search" in name_lower or "web" in name_lower:
        category = "web"
        query = args.get("query") or args.get("Url") or ""
        summary = f"Web {query[:60]}"
        details["query"] = query

    return category, summary, details


class TranscriptParser:
    def __init__(self, file_path: str):
        self.file_path = str(Path(file_path).resolve())
        self.raw_records: List[Tuple[int, Dict[str, Any]]] = []
        self.format: str = "unknown"  # 'claude' or 'gemini'
        self.session_id: str = ""
        self.ai_title: str = ""
        self.messages: List[TranscriptMessage] = []
        self.uuid_to_msg: Dict[str, TranscriptMessage] = {}
        self.children: Dict[str, List[TranscriptMessage]] = defaultdict(list)
        self.branch_tips: List[Tuple[TranscriptMessage, int]] = []
        self.branch_points: List[Tuple[TranscriptMessage, List[TranscriptMessage]]] = []
        self._load_file()

    def _load_file(self):
        if not os.path.exists(self.file_path):
            raise FileNotFoundError(f"Transcript file not found: {self.file_path}")

        with open(self.file_path, "r", encoding="utf-8", errors="replace") as f:
            for idx, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    self.raw_records.append((idx, obj))
                except json.JSONDecodeError:
                    continue

        if not self.raw_records:
            return

        # Detect format
        first_objs = [r[1] for r in self.raw_records[:10]]
        if any("step_index" in o or o.get("source") in ("USER_EXPLICIT", "MODEL") for o in first_objs):
            self.format = "gemini"
            self._parse_gemini()
        else:
            self.format = "claude"
            self._parse_claude()

        self._build_branch_indices()

    def _parse_claude(self):
        tool_results: Dict[str, Tuple[bool, str]] = {}

        # First pass: collect tool results and metadata
        for idx, obj in self.raw_records:
            t = obj.get("type")
            if t == "ai-title":
                self.ai_title = obj.get("aiTitle", "")
                self.session_id = obj.get("sessionId", "")
            elif t == "user":
                msg = obj.get("message", {})
                content = msg.get("content", [])
                if isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            tid = b.get("tool_use_id", "")
                            is_err = b.get("is_error", False)
                            res_content = b.get("content", "")
                            if isinstance(res_content, list):
                                res_text = "".join(
                                    x.get("text", "") for x in res_content if isinstance(x, dict)
                                )
                            else:
                                res_text = str(res_content)
                            tool_results[tid] = (is_err, res_text)

        # Second pass: build messages and tool calls
        for idx, obj in self.raw_records:
            t = obj.get("type")
            if t not in ("user", "assistant", "system"):
                continue

            uuid = obj.get("uuid")
            parent_uuid = obj.get("parentUuid")
            ts = obj.get("timestamp")
            msg = obj.get("message", {})
            content = msg.get("content", "")

            text_parts = []
            tools: List[ToolRecord] = []

            if isinstance(content, str):
                text_parts.append(content)
            elif isinstance(content, list):
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    btype = b.get("type")
                    if btype == "text":
                        text_parts.append(b.get("text", ""))
                    elif btype == "thinking":
                        pass  # Skip raw CoT from display text
                    elif btype == "tool_use":
                        tid = b.get("id", "")
                        tname = b.get("name", "")
                        tinput = b.get("input", {}) or {}
                        is_err, tout = tool_results.get(tid, (False, ""))
                        cat, summ, det = categorize_tool(tname, tinput, tout, is_err)
                        tools.append(
                            ToolRecord(
                                tool_id=tid,
                                name=tname,
                                category=cat,
                                summary=summ,
                                details=det,
                                is_error=is_err,
                                output=tout,
                                line_num=idx,
                            )
                        )

            # Skip messages that are only tool_result responses without user prompt
            full_text = "\n".join(p for p in text_parts if p.strip()).strip()
            if t == "user" and not full_text and not tools:
                # This was likely just a tool_result holder
                continue

            tmsg = TranscriptMessage(
                index=idx,
                role=t,
                text=full_text,
                uuid=uuid,
                parent_uuid=parent_uuid,
                timestamp=ts,
                raw_obj=obj,
            )
            tmsg.tools = tools
            self.messages.append(tmsg)
            if uuid:
                self.uuid_to_msg[uuid] = tmsg

    def _parse_gemini(self):
        # Gemini format: sequential step_index records
        for i, (idx, obj) in enumerate(self.raw_records):
            source = obj.get("source")
            stype = obj.get("type")
            ts = obj.get("created_at")
            content = obj.get("content") or ""
            tcs = obj.get("tool_calls") or []

            role = "assistant" if source == "MODEL" else "user" if source in ("USER_EXPLICIT", "USER") else "system"
            if stype == "USER_INPUT":
                role = "user"

            # Check next step for tool result if this step has tool calls
            next_content = ""
            is_err = False
            if tcs and i + 1 < len(self.raw_records):
                next_obj = self.raw_records[i + 1][1]
                if next_obj.get("source") == "MODEL" and next_obj.get("type") == "GENERIC":
                    next_content = str(next_obj.get("content") or "")
                    if "exited with code" in next_content and not "exited with code 0" in next_content:
                        is_err = True

            tools = []
            for tc in tcs:
                tname = tc.get("name") or "tool"
                args = tc.get("args") or {}
                # Clean up json strings in args if needed
                clean_args = {}
                for k, v in args.items():
                    if isinstance(v, str) and (v.startswith('"') and v.endswith('"')):
                        clean_args[k] = v[1:-1]
                    else:
                        clean_args[k] = v

                cat, summ, det = categorize_tool(tname, clean_args, next_content, is_err)
                tools.append(
                    ToolRecord(
                        tool_id=f"step_{idx}",
                        name=tname,
                        category=cat,
                        summary=summ,
                        details=det,
                        is_error=is_err,
                        output=next_content,
                        line_num=idx,
                    )
                )

            # Skip pure generic tool output messages from top-level list
            if stype == "GENERIC" and source == "MODEL" and not tcs:
                continue

            tmsg = TranscriptMessage(
                index=idx,
                role=role,
                text=str(content).strip(),
                timestamp=ts,
                raw_obj=obj,
            )
            tmsg.tools = tools
            self.messages.append(tmsg)

    def _build_branch_indices(self):
        if self.format != "claude":
            return

        for m in self.messages:
            if m.parent_uuid:
                self.children[m.parent_uuid].append(m)

        # Find branch points (parent with > 1 children)
        for parent_uuid, child_list in self.children.items():
            if len(child_list) > 1:
                parent_msg = self.uuid_to_msg.get(parent_uuid)
                if parent_msg:
                    self.branch_points.append((parent_msg, child_list))

        self.branch_points.sort(key=lambda x: x[0].index)

        # Find branch tips (leaf nodes)
        parent_uuids = set(self.children.keys())
        tips = []
        for m in self.messages:
            if not m.uuid:
                continue
            if m.uuid not in parent_uuids or len(self.children[m.uuid]) == 0:
                # Calculate depth
                chain = self._trace_chain(m)
                tips.append((m, len(chain)))

        tips.sort(key=lambda x: -x[1])
        self.branch_tips = tips

    def _trace_chain(self, leaf_msg: TranscriptMessage) -> List[TranscriptMessage]:
        chain = []
        curr = leaf_msg
        visited = set()
        while curr:
            if curr.uuid and curr.uuid in visited:
                break
            if curr.uuid:
                visited.add(curr.uuid)
            chain.append(curr)
            if curr.parent_uuid and curr.parent_uuid in self.uuid_to_msg:
                curr = self.uuid_to_msg[curr.parent_uuid]
            else:
                break
        chain.reverse()
        return chain

    def get_branch_messages(self, branch_rank: int = 1) -> List[TranscriptMessage]:
        """Return messages along the Nth deepest branch (1 = deepest)."""
        if self.format != "claude" or not self.branch_tips:
            return self.messages

        idx = branch_rank - 1
        if idx < 0 or idx >= len(self.branch_tips):
            return self.messages

        leaf = self.branch_tips[idx][0]
        return self._trace_chain(leaf)


# ----------------------------------------------------------------------
# Inspection & Presentation Views
# ----------------------------------------------------------------------

def print_banner(title: str):
    print("=" * 78)
    print(f"  {title}")
    print("=" * 78)


def view_summary(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    all_tools = [t for m in messages for t in m.tools]
    tool_counts = defaultdict(int)
    for t in all_tools:
        tool_counts[t.name] += 1

    user_msgs = [m for m in messages if m.role == "user"]
    asst_msgs = [m for m in messages if m.role == "assistant"]
    errors = [t for t in all_tools if t.is_error]

    # Git operations count
    git_tools = [t for t in all_tools if t.category == "git"]
    # Files modified count
    file_writes = [t for t in all_tools if t.category == "file_write"]
    files_touched = set(t.details.get("file_path", "") for t in file_writes if t.details.get("file_path"))

    first_ts = next((m.timestamp for m in messages if m.timestamp), None)
    last_ts = next((m.timestamp for m in reversed(messages) if m.timestamp), None)

    print_banner("SESSION OVERVIEW")
    print(f"  File:            {parser.file_path}")
    print(f"  Format:          {parser.format.upper()} ({len(parser.raw_records)} raw records)")
    if parser.ai_title:
        print(f"  AI Title:        {parser.ai_title}")
    if parser.session_id:
        print(f"  Session ID:      {parser.session_id}")
    if first_ts and last_ts:
        print(f"  Time Range:      {first_ts} -> {last_ts}")

    print()
    print_banner("CONVERSATION STRUCTURE")
    print(f"  User Prompts:    {len(user_msgs)}")
    print(f"  Assistant Turns: {len(asst_msgs)}")
    print(f"  Total Tool Calls:{len(all_tools)}")
    print(f"  Tool Errors:     {len(errors)}")

    if parser.format == "claude":
        branch_count = len(parser.branch_tips)
        fork_count = len(parser.branch_points)
        status = "Linear (No branches)" if fork_count == 0 else f"Branched ({fork_count} fork points, {branch_count} leaf tips)"
        print(f"  DAG Topology:    {status}")
        if branch_filter:
            print(f"  Scoped Branch:   #{branch_filter} (of {branch_count})")

    print()
    print_banner("KEY ACTIVITIES")
    print(f"  Git Operations:  {len(git_tools)}")
    print(f"  Files Modified:  {len(files_touched)}")
    if files_touched:
        print("  Touched Paths:   " + ", ".join(Path(p).name for p in list(files_touched)[:8]) + ("..." if len(files_touched) > 8 else ""))

    print()
    print_banner("TOOL CALL BREAKDOWN")
    for name, count in sorted(tool_counts.items(), key=lambda x: -x[1]):
        bar = "■" * min(30, max(1, int(count * 30 / (len(all_tools) or 1))))
        print(f"  {name:<20} {count:>4}  {bar}")


def view_changes(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    all_tools = [t for m in messages for t in m.tools]
    file_writes = [t for t in all_tools if t.category == "file_write"]
    git_tools = [t for t in all_tools if t.category == "git"]

    print_banner(f"FILE MODIFICATIONS AUDIT ({len(file_writes)} edit/write operations)")

    # Group by file path
    by_file: Dict[str, List[ToolRecord]] = defaultdict(list)
    for t in file_writes:
        path = t.details.get("file_path", "unknown")
        by_file[path].append(t)

    if not by_file:
        print("  No file modifications recorded in this session.")
    else:
        for path, ops in sorted(by_file.items(), key=lambda x: len(x[1]), reverse=True):
            print(f"\n  📄 {path}  ({len(ops)} operations)")
            for op in ops:
                status_icon = "❌" if op.is_error else "✓"
                print(f"     L{op.line_num:<4} {status_icon} {op.name:<6} {op.summary}")

    print()
    print_banner(f"GIT OPERATIONS AUDIT ({len(git_tools)} git commands executed)")
    if not git_tools:
        print("  No git operations recorded in this session.")
    else:
        for t in git_tools:
            status_icon = "❌" if t.is_error else "✓"
            sub = t.details.get("git_subcommand", "")
            args = t.details.get("git_args", "")
            print(f"  L{t.line_num:<4} {status_icon} git {sub:<10} {args}")


def view_git(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    git_tools = [t for m in messages for t in m.tools if t.category == "git"]

    print_banner(f"DETAILED GIT AUDIT ({len(git_tools)} operations)")
    if not git_tools:
        print("  No git operations found.")
        return

    for idx, t in enumerate(git_tools, 1):
        sub = t.details.get("git_subcommand", "")
        cmd = t.details.get("command", "")
        desc = t.details.get("description", "")
        out = t.output.strip()
        status = "FAILED" if t.is_error else "SUCCESS"

        print(f"\n[{idx}] git {sub} (Status: {status} | Line {t.line_num})")
        if desc:
            print(f"    Intent:  {desc}")
        print(f"    Command: {cmd}")
        if out:
            out_preview = "\n".join("    | " + l for l in out.splitlines()[:6])
            print(f"    Output:\n{out_preview}")
            if len(out.splitlines()) > 6:
                print(f"    | ... ({len(out.splitlines()) - 6} more lines)")


def view_timeline(
    parser: TranscriptParser,
    branch_filter: Optional[int] = None,
    tools_only: bool = False,
    user_only: bool = False,
    full_text: bool = False,
    max_items: Optional[int] = None,
):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    if user_only:
        messages = [m for m in messages if m.role == "user"]
    elif tools_only:
        messages = [m for m in messages if m.tools]

    if max_items:
        messages = messages[:max_items]

    print_banner(f"CONVERSATION TIMELINE ({len(messages)} events)")

    for m in messages:
        ts = f" [{m.timestamp}]" if m.timestamp else ""
        role_label = "🧑 USER" if m.role == "user" else "🤖 ASSISTANT" if m.role == "assistant" else "⚙️ SYSTEM"

        print(f"\n--- L{m.index} {role_label}{ts} ---")

        if m.text and not tools_only:
            if full_text:
                print(m.text)
            else:
                lines = m.text.strip().splitlines()
                preview = lines[0][:100] if lines else ""
                print(f"  {preview}" + ("..." if len(m.text) > 100 or len(lines) > 1 else ""))

        for t in m.tools:
            icon = "❌" if t.is_error else "🔧"
            print(f"    {icon} [{t.name}] {t.summary}")
            if full_text and t.output:
                out_snippet = "\n".join("      | " + l for l in t.output.splitlines()[:4])
                print(out_snippet)


def view_errors(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    all_tools = [t for m in messages for t in m.tools]
    errors = [t for t in all_tools if t.is_error]

    print_banner(f"FAILED TOOL EXECUTIONS & ERRORS ({len(errors)} found)")
    if not errors:
        print("  ✓ No failed tool operations detected in this session!")
        return

    for idx, e in enumerate(errors, 1):
        print(f"\n[{idx}] Line {e.line_num}: Tool [{e.name}] Failed")
        print(f"    Summary: {e.summary}")
        if "command" in e.details:
            print(f"    Command: {e.details['command']}")
        if e.output:
            lines = e.output.strip().splitlines()
            print("    Error Output:")
            for l in lines[:8]:
                print(f"      {l}")
            if len(lines) > 8:
                print(f"      ... ({len(lines) - 8} more lines)")


def search_transcript(
    parser: TranscriptParser,
    query: str,
    branch_filter: Optional[int] = None,
    full_text: bool = False,
):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    q_lower = query.lower()
    matches = []

    for m in messages:
        # Match message text
        if q_lower in m.text.lower():
            matches.append((m.index, m.role, "message", m.text))

        # Match tools
        for t in m.tools:
            t_str = f"{t.name} {t.summary} {json.dumps(t.details)} {t.output}"
            if q_lower in t_str.lower():
                matches.append((t.line_num, m.role, f"tool:{t.name}", t.summary + " | " + t.output[:200]))

    print_banner(f"SEARCH RESULTS FOR '{query}' ({len(matches)} matches)")
    if not matches:
        print("  No matches found.")
        return

    for line_num, role, match_type, content in matches:
        print(f"\n  [L{line_num}] ({role} | {match_type})")
        lines = content.strip().splitlines()
        if full_text:
            for l in lines:
                print(f"    {l}")
        else:
            for l in lines[:3]:
                print(f"    {l[:100]}")
            if len(lines) > 3:
                print(f"    ... ({len(lines) - 3} more lines)")


def diff_branches(parser: TranscriptParser, rank_a: int, rank_b: int):
    if parser.format != "claude":
        print("Branch comparison is only supported for Claude Code DAG transcripts.")
        return

    if not parser.branch_tips:
        print("No branches found in this transcript — conversation is linear.")
        return

    if rank_a < 1 or rank_a > len(parser.branch_tips):
        print(f"Invalid branch #{rank_a}. Available: 1..{len(parser.branch_tips)}")
        return
    if rank_b < 1 or rank_b > len(parser.branch_tips):
        print(f"Invalid branch #{rank_b}. Available: 1..{len(parser.branch_tips)}")
        return

    chain_a = parser.get_branch_messages(rank_a)
    chain_b = parser.get_branch_messages(rank_b)

    uuids_a = set(m.uuid for m in chain_a if m.uuid)
    uuids_b = set(m.uuid for m in chain_b if m.uuid)

    common_uuids = uuids_a.intersection(uuids_b)
    unique_a = [m for m in chain_a if m.uuid not in common_uuids]
    unique_b = [m for m in chain_b if m.uuid not in common_uuids]

    # Find the fork point (last common message)
    last_common = None
    for m in chain_a:
        if m.uuid in common_uuids:
            last_common = m

    print_banner(f"BRANCH COMPARISON: #{rank_a} (Depth {len(chain_a)}) vs #{rank_b} (Depth {len(chain_b)})")

    if last_common:
        print(f"\n🌱 Fork Point:")
        print(f"   Line {last_common.index}: [{last_common.role}] {last_common.text[:100]}")

    print(f"\n🌿 Branch #{rank_a} Divergence ({len(unique_a)} unique turns):")
    tools_a = [t for m in unique_a for t in m.tools]
    files_a = set(t.details.get("file_path", "") for t in tools_a if t.category == "file_write")
    git_a = [t for t in tools_a if t.category == "git"]
    print(f"   Tools called: {len(tools_a)} (Git: {len(git_a)}, Files modified: {len(files_a)})")
    if files_a:
        print(f"   Modified files: {', '.join(Path(p).name for p in files_a if p)}")
    for m in unique_a[:5]:
        print(f"   - L{m.index} [{m.role}] {m.text[:80]}")
        for t in m.tools:
            print(f"       🔧 {t.summary}")
    if len(unique_a) > 5:
        print(f"   ... ({len(unique_a) - 5} more unique messages)")

    print(f"\n🍂 Branch #{rank_b} Divergence ({len(unique_b)} unique turns):")
    tools_b = [t for m in unique_b for t in m.tools]
    files_b = set(t.details.get("file_path", "") for t in tools_b if t.category == "file_write")
    git_b = [t for t in tools_b if t.category == "git"]
    print(f"   Tools called: {len(tools_b)} (Git: {len(git_b)}, Files modified: {len(files_b)})")
    if files_b:
        print(f"   Modified files: {', '.join(Path(p).name for p in files_b if p)}")
    for m in unique_b[:5]:
        print(f"   - L{m.index} [{m.role}] {m.text[:80]}")
        for t in m.tools:
            print(f"       🔧 {t.summary}")
    if len(unique_b) > 5:
        print(f"   ... ({len(unique_b) - 5} more unique messages)")


def export_markdown(parser: TranscriptParser, out_file: str, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    all_tools = [t for m in messages for t in m.tools]
    file_writes = [t for t in all_tools if t.category == "file_write"]
    git_tools = [t for t in all_tools if t.category == "git"]

    lines = []
    lines.append(f"# Conversation Audit Report")
    lines.append(f"")
    lines.append(f"- **Source Transcript**: `{parser.file_path}`")
    lines.append(f"- **Format**: {parser.format.upper()}")
    if parser.ai_title:
        lines.append(f"- **AI Title**: {parser.ai_title}")
    if parser.session_id:
        lines.append(f"- **Session ID**: `{parser.session_id}`")
    if branch_filter:
        lines.append(f"- **Scoped Branch**: #{branch_filter}")
    lines.append(f"- **Generated At**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"")

    lines.append(f"## 1. Executive Summary")
    lines.append(f"")
    lines.append(f"| Metric | Count |")
    lines.append(f"| :--- | :--- |")
    lines.append(f"| User Prompts | {len([m for m in messages if m.role == 'user'])} |")
    lines.append(f"| Assistant Turns | {len([m for m in messages if m.role == 'assistant'])} |")
    lines.append(f"| Total Tool Executions | {len(all_tools)} |")
    lines.append(f"| Git Operations | {len(git_tools)} |")
    lines.append(f"| Files Modified | {len(set(t.details.get('file_path', '') for t in file_writes if t.details.get('file_path')))} |")
    lines.append(f"| Tool Failures/Errors | {len([t for t in all_tools if t.is_error])} |")
    lines.append(f"")

    if file_writes:
        lines.append(f"## 2. Modified Files")
        lines.append(f"")
        lines.append(f"| Line | Operation | File | Detail | Status |")
        lines.append(f"| :--- | :--- | :--- | :--- | :--- |")
        for t in file_writes:
            path = t.details.get("file_path", "")
            stat = "❌ Failed" if t.is_error else "✓ OK"
            lines.append(f"| L{t.line_num} | `{t.name}` | `{path}` | {t.summary} | {stat} |")
        lines.append(f"")

    if git_tools:
        lines.append(f"## 3. Git Operations")
        lines.append(f"")
        lines.append(f"| Line | Command | Intent | Status |")
        lines.append(f"| :--- | :--- | :--- | :--- |")
        for t in git_tools:
            cmd = t.details.get("command", "")
            desc = t.details.get("description", "") or "-"
            stat = "❌ Failed" if t.is_error else "✓ OK"
            lines.append(f"| L{t.line_num} | `{cmd[:60]}` | {desc[:40]} | {stat} |")
        lines.append(f"")

    lines.append(f"## 4. Conversation Transcript")
    lines.append(f"")
    for m in messages:
        role_hdr = "🧑 User" if m.role == "user" else "🤖 Assistant" if m.role == "assistant" else "⚙️ System"
        ts_str = f" ({m.timestamp})" if m.timestamp else ""
        lines.append(f"### [L{m.index}] {role_hdr}{ts_str}")
        lines.append(f"")
        if m.text:
            lines.append(m.text)
            lines.append(f"")
        for t in m.tools:
            icon = "❌" if t.is_error else "🔧"
            lines.append(f"> {icon} **`{t.name}`**: {t.summary}")
            if t.output:
                preview = t.output.strip()[:200]
                lines.append(f"> ```text")
                lines.append(f"> {preview}")
                lines.append(f"> ```")
        lines.append(f"")

    out_p = Path(out_file)
    out_p.parent.mkdir(parents=True, exist_ok=True)
    with open(out_p, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"Exported Markdown audit report to: {out_file}")


def export_json(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    data = {
        "file": parser.file_path,
        "format": parser.format,
        "ai_title": parser.ai_title,
        "session_id": parser.session_id,
        "branch_filter": branch_filter,
        "total_messages": len(messages),
        "messages": [m.to_dict() for m in messages],
    }
    print(json.dumps(data, indent=2, ensure_ascii=False))


# ----------------------------------------------------------------------
# Main CLI Entry Point
# ----------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Inspect, audit, and analyze coding agent conversation transcripts."
    )
    parser.add_argument("transcript", help="Path to conversation transcript JSONL file")
    parser.add_argument("--summary", action="store_true", help="Display overview summary (default)")
    parser.add_argument("--changes", action="store_true", help="Audit all file modifications and git commands")
    parser.add_argument("--git", action="store_true", help="Detailed audit of all Git operations")
    parser.add_argument("--timeline", action="store_true", help="Chronological conversation timeline")
    parser.add_argument("--errors", action="store_true", help="Show all failed tool calls and errors")
    parser.add_argument("--search", "--grep", dest="query", help="Search for keyword in messages and tools")
    parser.add_argument("--diff-branches", nargs=2, type=int, metavar=("A", "B"), help="Compare divergence between branch A and B")
    parser.add_argument("--branch", type=int, metavar="N", help="Scope analysis to Nth deepest branch (1=deepest)")
    parser.add_argument("--export-md", metavar="FILE", help="Export audit report and transcript to Markdown file")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    parser.add_argument("--full", action="store_true", help="Display full text content without truncation")
    parser.add_argument("--tools-only", action="store_true", help="Timeline view shows only tool invocations")
    parser.add_argument("--user-only", action="store_true", help="Timeline view shows only user prompts")
    parser.add_argument("--limit", type=int, metavar="N", help="Limit number of items displayed")

    args = parser.parse_args()

    try:
        t_parser = TranscriptParser(args.transcript)
    except Exception as e:
        print(f"Error reading transcript: {e}", file=sys.stderr)
        sys.exit(1)

    # Route execution
    if args.json:
        export_json(t_parser, args.branch)
    elif args.export_md:
        export_markdown(t_parser, args.export_md, args.branch)
    elif args.diff_branches:
        diff_branches(t_parser, args.diff_branches[0], args.diff_branches[1])
    elif args.query:
        search_transcript(t_parser, args.query, args.branch, args.full)
    elif args.errors:
        view_errors(t_parser, args.branch)
    elif args.git:
        view_git(t_parser, args.branch)
    elif args.changes:
        view_changes(t_parser, args.branch)
    elif args.timeline:
        view_timeline(
            t_parser,
            branch_filter=args.branch,
            tools_only=args.tools_only,
            user_only=args.user_only,
            full_text=args.full,
            max_items=args.limit,
        )
    else:
        view_summary(t_parser, args.branch)


if __name__ == "__main__":
    main()
