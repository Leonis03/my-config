# Antigravity CLI (agy) — Troubleshooting

> Usage: see [SKILL.md](SKILL.md). This doc covers issues you may hit.

## Network & proxy (WSL must go through the proxy)

- **Direct access to Google from WSL is blocked**: verified `dial tcp 172.217.118.4:443: i/o timeout`, flaky. agy must use the proxy.
- agy (Go) honors the `HTTPS_PROXY`/`HTTP_PROXY` env vars; setting them routes traffic over HTTP CONNECT. Already configured in `.bashrc`:
  ```bash
  export HTTPS_PROXY=http://127.0.0.1:<proxy-port>
  export HTTP_PROXY=http://127.0.0.1:<proxy-port>
  export ALL_PROXY=socks5h://127.0.0.1:<proxy-port>   # for curl/git and other tools that read ALL_PROXY
  ```
- **`ALL_PROXY` has no effect on agy**: Go only reads `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`; `ALL_PROXY` only applies to curl/git etc.
- **Use `socks5h://` for SOCKS5**: WSL's local DNS is poisoned for Google domains (`www.google.com` → fake address `2001::1`); `socks5://` (local DNS) fails against the fake address; `socks5h://` (remote DNS) resolves via Clash and works.
- **Don't wrap agy with antissh.sh's graftcp**: agy honors `HTTP_PROXY`, so just use the env vars — no graftcp needed (graftcp can hijack Go's connect() via ptrace, but it's unnecessary here).

## Authentication

| Symptom | Fix |
|---|---|
| `Please sign in to view available models` / stuck at auth | Token expired or refresh failed. **Run an interactive `agy` once** to re-authenticate and refresh the token; non-interactive calls work again afterwards |
| Long silence (no output, `i/o timeout`) | Not going through the proxy. Confirm `HTTPS_PROXY`/`HTTP_PROXY` are set; or prefix the command: `HTTPS_PROXY=http://127.0.0.1:<proxy-port> HTTP_PROXY=http://127.0.0.1:<proxy-port> agy -p "..."` |

Auth mechanism: token stored at `~/.gemini/antigravity-cli/antigravity-oauth-token`, auto-refreshed; once expired and headless can't refresh on its own, only an interactive `agy` can refresh it manually.

## Image read failures

| Symptom | Fix |
|---|---|
| `a tool required the "read_file" permission ... auto-denied` | settings.json is missing the `permissions` section; add `allow: ["read_file(*)"]` (template in SKILL.md) |
| No output / image not attached | Path must be **inside the prompt text** (not a positional arg); use WSL absolute paths (`$HOME/...`) |
| settings.json is invalid JSON (e.g. single backslash `C:\Users`) | CLI silently falls back to `permissions=<nil>` and denies everything — make it valid JSON (double backslashes / forward slashes) |

## Misc

| Symptom | Fix |
|---|---|
| `Eligibility check failed: ... EOF` | Transient proxy/endpoint jitter — **just retry** (verified occasional, not a config issue) |
| print mode timeout | Add `--print-timeout`, e.g. `--print-timeout 10m` |

## Appendix: verified facts on this machine (2026-08-17)

- `agy` at `$HOME/.local/bin/agy`, v1.1.13, native Linux ELF (works directly in WSL)
- Text Q&A and image reading both verified working (with proxy env vars)
- Available models (`agy models`): `gemini-3.7-flash-high/medium/low` (default), `gemini-3.6-flash-*`, `gemini-3.5-flash-*`, `gemini-3.1-pro-*`, `claude-sonnet-4-6`, `claude-opus-4-6-thinking`, `gpt-oss-120b-medium`

中文版见 [TROUBLESHOOTING.zh.md](TROUBLESHOOTING.zh.md)。
