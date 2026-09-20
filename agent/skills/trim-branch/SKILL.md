---
name: trim-branch
description: Diagnose and fix Claude Code conversation JSONL branch/fork issues. Use when the user reports missing messages after resume, conversation branching problems, or wants to extract a specific branch from a forked JSONL session file. Also use when the user mentions JSONL, conversation history, resume showing wrong content, or messages disappearing after resume.
---

# Trim Branch

Fix Claude Code conversation JSONL files that have forked into multiple branches, causing `--resume` to land on the wrong branch and hide messages.

## When this happens

Claude Code stores conversations as a linked list via `parentUuid`. When session limits, retries, or concurrent resumes occur, multiple messages can share the same parent — creating a fork. `--resume` picks one branch (often the wrong one), and messages on the other branch become invisible.

## Workflow

### Step 1: Analyze the JSONL

Run the analysis script to see all branch points and tips:

```bash
python3 ~/.claude/skills/trim-branch/scripts/analyze.py <JSONL_PATH>
```

This shows:
- **Branch points**: where the conversation forked (which parent has multiple children)
- **Branch tips**: the leaf nodes of each branch, sorted by depth (deepest = most content)

Present the results to the user and help them identify which branch contains the content they want.

### Step 2: Extract the desired branch

Once the user identifies the target (by line number or branch rank):

```bash
# By line number (the line containing the desired message):
python3 ~/.claude/skills/trim-branch/scripts/analyze.py <JSONL_PATH> --extract <LINE>

# By branch rank (1 = deepest/longest branch):
python3 ~/.claude/skills/trim-branch/scripts/analyze.py <JSONL_PATH> --extract-tip 1
```

This traces back from the target message to the root, collecting only messages on that path plus associated system/meta messages. A backup of the original is automatically created as `<name>.original.jsonl`.

### Step 3: Replace the original (with user confirmation)

After the user confirms the extracted content looks correct:

```bash
python3 ~/.claude/skills/trim-branch/scripts/analyze.py <JSONL_PATH> --extract <LINE> --replace
```

Or manually:
```bash
cp <name>.trimmed.jsonl <name>.jsonl
```

The user can then `claude --resume <session-id>` to enter the correct branch.

## Important notes

- Always create a backup before replacing. The script does this automatically (`.original.jsonl`).
- The `--replace` flag copies the trimmed version over the original. The backup is created first.
- Cache (prompt cache) is unaffected — it has a short TTL and will have expired by the time the user notices the branch issue.
- If the user just wants to read the content without fixing the file, use the Read tool to read the specific line from the JSONL and parse the JSON to show the message content.
