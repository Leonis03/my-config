---
name: antigravity-cli
description: Delegate a one-shot prompt, a local image, or a task inside one directory to Google Antigravity CLI (agy, Gemini 3.x) through the least-privilege wrapper agy-run.sh -- sandboxed, read-only by default, write and command access only through grants the user runs. TRIGGER when the user asks to use Antigravity, agy or Gemini for a question, a second opinion, OCR / image description, or work inside a folder. DO NOT TRIGGER for images you can read yourself unless Gemini is requested, or for tasks that need network access from shell commands.
allowed-tools: Bash(bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh *)
---

# Antigravity CLI (agy) -- least-privilege calls from an agent

Call agy **only** through `scripts/agy-run.sh`. Never run `agy -p` yourself, never pass
`--dangerously-skip-permissions`, never edit `~/.gemini/antigravity-cli/settings.json`.
The Claude Code hook `scripts/agy-guard.sh` blocks all three, even in bypassPermissions mode.

Why a wrapper: raw `agy -p` ends its turn with **exit 0 and an empty response** when a
permission is denied, and runs shell commands unsandboxed unless told otherwise.
`agy-run.sh` always adds `--sandbox`, starts from an empty temp workspace, and maps every
outcome to an exit code.

## Run

```bash
bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh "question"
bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh --image /abs/shot.png "Transcribe all text exactly"
bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh --dir /abs/project "Summarize README.md"
printf '%s' "$long_prompt" | bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh -
```

| Call | Workspace | agy can read | agy can write |
|---|---|---|---|
| no `--dir` | new empty temp dir, deleted afterwards | that dir, incl. `--image` copies | nothing |
| `--dir DIR` | `DIR` (not `/`, `$HOME` or its ancestors) | `DIR` | only if the user granted write for `DIR` |

Options: `--model NAME` (`agy models`; default is agy's own, currently `gemini-3.8-flash-high`), `--timeout 10m`,
`--dry-run` (show workspace, flags and final prompt; no model call), `--keep` (keep the temp
workspace). Also `quota` (remaining quota, no model call) and `grants` (current rules).

Put image paths in `--image`, not in the prompt: the wrapper copies them into the workspace
and tells agy to open them with its file viewer. Ask a focused question ("transcribe", "what
error is shown") rather than "describe".

## Read the result

stdout is agy's answer; stderr carries diagnostics and ends with one
`agy-run: exit=... model=... workspace=... blocked=... log=...` line.

| Exit | Meaning | Do |
|---|---|---|
| 0 | answered, nothing blocked | use stdout; still read any `agy-run: sandbox:` note -- a command hit a read-only path or had no network, and the answer may rest on that failure |
| 3 | agy / API error | `RESOURCE_EXHAUSTED`: run `quota`; Gemini and Claude/GPT models have separate pools (`--model claude-sonnet-4-6`). Login expired: the user runs an interactive `agy` once |
| 4 | an action was blocked | read the `BLOCKED tool(target) -- hint` lines; stdout may hold a partial answer. Do not retry with rephrasing or another tool -- see Grants |
| 5 | empty or incomplete answer | retry once; raise `--timeout` if it says print timeout |
| 6 | refused by policy | pick a narrower `--dir`, or fix the path |
| 1, 2 | setup / usage error | the message says what is missing |

## Grants -- widening access is the user's call

1. On exit 4 with a grant hint, stop.
2. Ask the user (AskUserQuestion): the exact rule (`write_file(/abs/dir)` or
   `command(prefix)`), why agy needs it, and that it stays in force for every later agy run
   until revoked.
3. If they agree, **they** type it:
   `! bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh grant write /abs/dir`
   or `... grant command 'uv run'`. Never run `grant` yourself; the hook blocks it.
4. Re-run. `revoke write|command ...` and `grants` you may run yourself.

`grant` refuses `/`, `$HOME` and its ancestors, and `*` / `regex:` command rules.
Command rules are **prefix** matches (`command(ls)` also allows `ls -la /anywhere`); the
sandbox is what keeps them inside the workspace.

## What agy can reach (verified 2026-09-26, agy 1.2.11, WSL)

- **File tools**: the workspace is readable with no rule; anything else needs a
  `read_file(...)` rule (none by default). Writes need `write_file(DIR)`. agy may write all
  of `/tmp` by default -- the `write_file(/tmp)` deny rule below closes that.
- **Shell commands**: need a `command(prefix)` rule, and always run in the sandbox. They see
  the workspace, system dirs and a few home dirs (`~/.cache`, `~/.npm`, `~/.nvm` writable;
  `~/.config`, `~/.gitconfig` read-only); the rest of `$HOME`, `~/.ssh` and agy's own config
  are hidden. **No network** (no DNS, no proxy). umask is 0000, so created files are
  world-writable.
- A command outside the allowlist, or a file read outside the workspace, ends agy's turn:
  exit 4.

## Setup (once per machine)

1. Log in and set the proxy: see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
2. `~/.gemini/antigravity-cli/settings.json`, minimal:

   ```json
   {
     "permissions": {
       "allow": [],
       "deny": ["write_file(/tmp)"]
     },
     "trustedWorkspaces": ["<your-home>"]
   }
   ```

   `trustedWorkspaces` is optional for agy-run (untrusted temp workspaces work). Add rules
   later with `grant`, never by hand-editing from an agent.
3. Claude Code hook, in `~/.claude/settings.json`:

   ```json
   "hooks": {
     "PreToolUse": [{
       "matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit",
       "hooks": [{"type": "command", "command": "bash ~/.claude/skills/antigravity-cli/scripts/agy-guard.sh"}]
     }]
   }
   ```
4. Check: `bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh grants` warns about
   wildcard rules or a missing `/tmp` deny.

Something wrong? Diagnostics, proxy, login and raw-agy behavior: **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**

中文版见 [SKILL.zh.md](SKILL.zh.md)。
