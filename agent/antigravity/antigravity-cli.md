---
name: antigravity-cli
description: Invoke the Google Antigravity CLI (agy) for one-shot plain-text replies. Use when the user asks to call Antigravity/agy, run a single non-interactive prompt, or use a specific gemini-3.x model via the terminal agent. 中文版见 SKILL.zh-CN.md.
---

# Antigravity CLI — Plain-Text Reply Invocation

Run a single, non-interactive prompt through `agy` (Google Antigravity CLI) and get a plain-text reply.

## Prerequisites (verified on this machine)

- Executable: `C:\Users\<your-windows-user>\AppData\Local\agy\bin\agy.exe` (command `agy`, on PATH)
- Version: v1.1.11 (`agy --version`)
- Auth: already completed (Google Sign-In, credentials in system credential manager); no re-login needed
- Note: the `antigravity` command points at the **Antigravity IDE** (VS Code-based) — NOT the CLI agent. The CLI agent is `agy`.

## Usage

Default output format is `text` (plain text):

```bash
agy -p "your prompt"         # one-shot single prompt, prints plain-text reply
agy -p -                     # read prompt from stdin (multi-line / long text)
agy --model gemini-3.5-flash-high -p "..."   # pick a model
agy --print-timeout 10m -p "..."             # override 5-minute default timeout
```

### Common flags

| Flag | Description |
|---|---|
| `-p` / `--print` / `--prompt` | Run one prompt non-interactively and print the reply |
| `-` | Append at end: read prompt from stdin |
| `--model <id>` | Model id, e.g. `gemini-3.5-flash-high` |
| `--effort low\|medium\|high` | Reasoning effort |
| `--print-timeout <dur>` | Print-mode wait timeout (default `5m0s`) |
| `--output-format text\|json\|stream-json` | Output format; plain text is the default `text` |
| `--sandbox` | Run in a restricted sandbox |
| `--continue` / `-c` | Continue the most recent conversation |
| `--conversation <id>` | Resume a conversation by ID |

### List available models

```bash
agy models
```

Models verified available (2026-08): `gemini-3.6-flash-high/medium/low`, `gemini-3.5-flash-high/medium/low`, `gemini-3.1-pro-high/low`, `claude-sonnet-4-6`, `claude-opus-4-6-thinking`, `gpt-oss-120b-medium`.

## Windows: PowerShell / Git Bash

- PowerShell: `agy -p "..."`; stdin: `"content" | agy -`
- Git Bash: `agy -p "..."` works too; multi-line prompt via heredoc:
  ```bash
  agy - <<'EOF'
  your multi-line prompt
  EOF
  ```

## Reading images (multimodal) — solved, strict read-only (2026-08-12)

**Working invocation — embed the path IN the prompt text** (the extra-positional-arg attach is broken in CLI v1.1.12):

```bash
agy -p "Describe the content of the image file located at C:\path\image.png"
```

No `--dangerously-skip-permissions`, no `command(*)` needed. The model uses the `ViewFile`/`ReadFile` tool directly (creates a media artifact in `.tempmediaStorage`), so only `read_file` permission is required — **no shell commands at all**.

**Minimal strict settings** (`~/.gemini/antigravity-cli/settings.json`):

```json
"permissions": {
  "allow": ["read_file(*)"],
  "deny": ["write_file(*)"],
  "ask": []
}
```

- Verified on v1.1.12 with `gemini-3.5-flash-high` and the default model; also works with `--sandbox` for an extra sandbox layer.
- Read-only is enforced: any command the model attempts (e.g. file writes via shell) is auto-denied in headless mode.
- Keep `write_file(*)` in `deny` as defense-in-depth.

**Notes on what NOT to do (why earlier attempts failed):**
- `command()` rules in v1.1.12 match **exact full command strings only** — no per-token regex, no prefix, no `command(Get-ChildItem)` covering `Get-ChildItem -Path ...` (verified empirically; contradicts the official docs' "token prefix regex" description). `command(*)` is the only rule matching all commands. So a command-based strict allowlist cannot cover the image tool's random `Get-ChildItem` variants — but that's moot because the ViewFile path needs no commands.
- The old positional-arg form (`agy -p "..." path.png`) silently drops the image in v1.1.12 ("no image was attached").
- **Caveat:** a settings.json with invalid JSON (e.g. a raw `C:\Users` single-backslash in `trustedWorkspaces`) makes the CLI fall back to `permissions=<nil>` and deny everything — use only valid JSON (double backslashes).
- Older fallbacks (kept for reference): blacklist config `allow:[command(*), read_file(*), ...]` + `deny:[write_file(*), command(rm -rf), command(sudo)]`, or `--dangerously-skip-permissions`.

## Notes

- Print mode defaults to a 5-minute timeout; add `--print-timeout` for long tasks.
- When the agent wants to run a tool that needs confirmation, the CLI waits for approval; use `--dangerously-skip-permissions` only in trusted contexts.
- This returns plain text; use `--output-format json` for structured output.

---

- 中文版：见 [../skills/antigravity-cli/SKILL.zh.md](../skills/antigravity-cli/SKILL.zh.md)
