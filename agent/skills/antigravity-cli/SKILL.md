---
name: antigravity-cli
description: Call Google Antigravity CLI (agy) for one-shot plain-text Q&A or reading local images (WSL/Linux edition). Trigger on: user asks to invoke Antigravity/agy, run a single non-interactive prompt, Q&A with gemini-3.x models, or read/describe local images.
---

# Antigravity CLI (agy) — WSL / Linux usage

> Proxy env vars are already configured in `.bashrc` (`HTTPS_PROXY`/`HTTP_PROXY=http://127.0.0.1:<proxy-port>`), so the commands below **run as-is**. If something fails, see the troubleshooting section at the end.

## Text Q&A

```bash
agy -p "your prompt"          # one-shot Q&A, plain text output
agy -p -                      # read prompt from stdin (multi-line / long text)
agy --model gemini-3.5-flash-high -p "..."   # pick a model
agy --print-timeout 10m -p "..."             # override the default 5-minute timeout
```

## Reading images (multimodal)

**Put the image path in the prompt text** (passing the image as a positional arg is silently dropped and has no effect):

```bash
agy -p "Describe the content of the image file located at $HOME/code/antig/test.png"
```

Prerequisite: `~/.gemini/antigravity-cli/settings.json` must contain a permissions config (headless mode denies all tools by default):

```json
{
  "enableTelemetry": false,
  "permissions": {
    "allow": ["read_file(*)"],
    "deny": ["write_file(*)"]
  },
  "trustedWorkspaces": ["<your-home>"]
}
```

- The model reads the image directly via `ViewFile`/`ReadFile` — **no shell command** needed, no `--dangerously-skip-permissions`
- Read-only constraint works: write attempts by the model are auto-denied by headless
- Use WSL absolute paths (`$HOME/...`); Windows paths (`C:\...`) cannot be read
- Verified: test.png (dark-gray background, three lines of Chinese) described correctly

## Something wrong?

Network proxy / stuck auth / expired token / image-read failures → see **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**

中文版见 [SKILL.zh.md](SKILL.zh.md)。
