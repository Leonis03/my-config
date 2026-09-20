---
name: bx
description: Web search, news, images, videos, places and AI-synthesized answers via the Brave Search `bx` CLI. Reach for it when you need publication dates on results, a freshness window (past day/week/month or an explicit date range), non-US or non-English results, site-scoped or re-ranked search, or a cheap breadth scan of many queries -- none of which the built-in WebSearch tool can do. Outputs JSON; always pipe through jq.
allowed-tools: Bash
---

# bx -- Brave Search CLI

Official [Brave Search CLI](https://github.com/brave/brave-search-cli) at `~/.local/bin/bx`.
Every command writes structured JSON to stdout, errors to stderr, and returns a
machine-readable exit code.

## Rule 0: never let raw output into context

Measured on this machine, one `bx web --count 10` call:

| What enters context | Bytes | ~tokens |
|---|---:|---:|
| Raw JSON, no jq | 86,391 | **21,600** |
| jq: title + url + description | 3,585 | 900 |
| jq: url only | 716 | **180** |

That is a 120x spread. **A `bx` call without a jq filter is a bug.** Always pair
`--count N` with a jq projection. Copy-paste recipes are in the next section.

## Output paths differ per command -- getting this wrong fails silently

`news`/`images`/`videos`/`places` put results at the **top level**, not under a
named key. Using `.web.results[]` on `news` returns zero rows with exit code 0
and no error.

| Command | jq recipe |
|---|---|
| `web` | `jq -r '.web.results[] \| "\(.title)\n  \(.url)\n  \(.description)\n"'` |
| `news` | `jq -r '.results[] \| "\(.title)\n  \(.url)  [\(.age)]"'` |
| `images` / `videos` | `jq -r '.results[] \| "\(.title)  \(.url)"'` |
| `places` | `jq -r '.results[] \| "\(.title)  \(.postal_address.displayAddress // "")"'` |
| `context` | `jq -r '.grounding.generic[] \| "[\(.title)] \(.url)\n\(.snippets \| join("\n"))\n"'` |
| `answers` | `jq -r '.choices[0].message.content'` |

`context` also returns `.sources`, which is an **object keyed by URL** (not an
array): `.sources["https://..."] = {title, hostname, age, snippet}`.

Cheapest triage projection, use this first:
```bash
bx web "query" --count 10 | jq -r '.web.results[].url'
```

## Choosing between bx and the built-in WebSearch

Both are available here and they are not interchangeable. WebSearch fetches and
reads page bodies; `bx web` returns only titles and snippets.

| Goal | Use |
|---|---|
| Breadth scan, triage, "what exists on this" | `bx web/news` + jq (~180 tok/query) |
| Publication dates, "is this stale?" | `bx` -- WebSearch has **no** date metadata |
| Freshness window or explicit date range | `bx news --freshness` -- WebSearch has no such param |
| Non-US region or non-English results | `bx --country/--search-lang` -- WebSearch is US-only |
| Mechanism, quotes, numbers from page bodies | **WebSearch** (~780 tok, already read the pages) |
| Site-scoped or custom re-ranked search | `bx --include-site` / `--goggles` |

Reaching page-level depth with `bx` means `context` (~2,400 tok/query), which is
more expensive than one WebSearch call. Scan with `bx`, then go deep with
WebSearch or WebFetch on the 2-3 URLs worth reading.

## The `age` field is the main reason to use this tool

`news` results carry `.age`, and `context` carries `.sources[url].age`, giving an
exact publication date plus a relative form:

```
"age": ["Thursday, April 16, 2026", "2026-04-16", "151 days ago", "2026-04-16T00:00:00Z"]
```

The built-in WebSearch exposes nothing equivalent. Always surface `[\(.age)]` in
news projections so staleness is visible.

## Quick reference

| Need | Command |
|---|---|
| Raw web results | `bx web "q" --count 5` |
| News, freshness-filtered | `bx news "q" --freshness pw` |
| News, explicit date range | `bx news "q" --freshness 2026-09-01to2026-09-14` |
| RAG grounding (search+scrape+extract in one call) | `bx "q" --max-tokens 2048` (alias for `bx context`) |
| AI answer | `bx answers "q" --config ~/.config/brave-search/config-answers.json --no-stream` |
| Images / Videos | `bx images "q" --count 5` / `bx videos "q" --count 5` |
| Places / POI | `bx places "coffee" --location "San Francisco CA US"` (query is positional, there is no `-q`) |

Not available on the current plan: `bx suggest` returns HTTP 400.

## Flags that matter

- `--count N` -- always set it.
- `--freshness pd|pw|pm|py` or `YYYY-MM-DDtoYYYY-MM-DD` (`news`, `web`).
- `--country US|CN|JP|...`, `--search-lang en|zh-hans|ja|...`, `--ui-lang en-US|zh-CN|...`
  -- the only way to get non-US results in this environment. Works on `web`, `news`, `context`.
- `--include-site docs.rs` / `--exclude-site medium.com` (both repeatable) /
  `--goggles '$boost=3,site=docs.rs'` for custom re-ranking. **All three are
  mutually exclusive**; combining them exits 2.
- `--extra KEY=VALUE` passes raw API params. Useful:
  `--extra text_decorations=false` strips the `<strong>` markers Brave injects
  into descriptions. HTML entities (`&quot;`, `&#x27;`) still need decoding.
- `--offset N` for pagination (max 9).

`context` budget flags -- short forms are undocumented aliases but work:

- `--max-tokens N` -- **must be >= 1024**, or the API returns 422. 2048 is a
  sensible ceiling; 8192 puts ~10k tokens into context.
- `--max-tokens-per-url N`, `--max-urls N`, `--threshold strict|balanced|lenient`
  (canonical long forms: `--maximum-number-of-tokens`, `--maximum-number-of-urls`,
  `--context-threshold-mode`).

## Config and plans

Two separate API keys, two config files:

- `~/.config/brave-search/config.json` -- Search plan. Covers `web`, `news`,
  `images`, `videos`, `places`, `context`. **No `--config` flag needed.**
- `~/.config/brave-search/config-answers.json` -- Answers plan. **`bx answers`
  requires `--config <that path>`**, plus `--no-stream` for a single JSON blob
  instead of an SSE stream.

Inspect with `bx config show` / `bx config show-key`. `BRAVE_SEARCH_API_KEY`
overrides; with no key at all the CLI prints `error: no API key configured`.

## Do not use the brave-search MCP server

This machine also has `mcpServers.brave-search` configured with the same API key,
exposing `mcp__brave-search__brave_web_search` and friends. Prefer this CLI:
loading a single one of those tool schemas costs ~2,400 tokens, and MCP results
cannot be jq-filtered, so the 180-token floor above is unreachable. Do not
ToolSearch for them.

## Proxy

This WSL box routes external traffic through a local proxy. The `~/.local/bin/bx`
wrapper already clears the incompatible `ALL_PROXY=socks5h://...` and sets
`HTTPS_PROXY`/`HTTP_PROXY` (`http://127.0.0.1:<proxy-port>`). Never unset those vars. To
call the raw binary directly use `~/.local/bin/bx-bin` and clear `ALL_PROXY`
yourself.

## Example workflows

Triage a topic cheaply, then go deep on what matters:
```bash
bx web "axum middleware ordering" --include-site docs.rs --count 10 \
  | jq -r '.web.results[].url'
# then WebFetch / WebSearch the 2-3 URLs worth reading
```

Check whether something is recent, with dates visible:
```bash
bx news "openssl vulnerability" --freshness pw --count 5 \
  | jq -r '.results[] | "\(.title)\n  \(.url)  [\(.age)]"'
```

Non-US / non-English results:
```bash
bx web "subagent config" --country CN --search-lang zh-hans --count 5 \
  | jq -r '.web.results[] | "\(.title)  \(.url)"'
```

Grounded context for an error, in one call:
```bash
bx "Python TypeError cannot unpack non-iterable NoneType" --max-tokens 2048 \
  | jq -r '.grounding.generic[] | "[\(.title)] \(.url)\n\(.snippets | join("\n"))\n"'
```

AI-synthesized answer:
```bash
bx answers "Compare PostgreSQL and MySQL for high write throughput" \
  --config ~/.config/brave-search/config-answers.json --no-stream \
  | jq -r '.choices[0].message.content'
```

## Exit codes

| Code | Meaning | Action |
|---|---|---|
| 0 | Success | Process the JSON (check the row count -- a wrong jq path yields 0 rows at exit 0) |
| 1 | Client error (4xx) | Fix query/params, or the plan lacks that endpoint |
| 2 | Usage error (bad flag) | Fix arguments; check for mutually exclusive flags |
| 3 | Auth (401/403) | `bx config show-key` |
| 4 | Rate limited (429) | Retry with backoff |
| 5 | Server/network | Check proxy at 127.0.0.1:<proxy-port>, retry with backoff |

A Chinese reference translation of an older revision lives at `references/zh.md`.
It is not loaded by any harness and may lag this file; this file is authoritative.
