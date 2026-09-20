# Global Conventions

## Web Search

Two complementary tools: the built-in `WebSearch` fetches and reads page bodies; the Brave
Search CLI `bx` does what `WebSearch` cannot -- publication dates, freshness windows, non-US
or non-English results, site scoping. Usual flow: scan cheaply with `bx`, then go deep with
`WebSearch` / `WebFetch` on the 2-3 URLs worth reading.

`bx` writes JSON to stdout. Two rules make an unassisted call safe: **always project through
jq** (raw output is ~120x the tokens), and **mind the result path per subcommand** -- `web`
puts rows under `.web.results[]`, everything else under `.results[]`, and a wrong path
returns 0 rows at exit 0 with no error. These five cover almost everything:

```bash
# triage -- URLs only, ~180 tokens
bx web "axum middleware ordering" --include-site docs.rs --count 10 | jq -r '.web.results[].url'

# normal search -- title, url, snippet
bx web "query" --count 5 | jq -r '.web.results[] | "\(.title)\n  \(.url)\n  \(.description)\n"'

# news with publication dates; --freshness pd|pw|pm|py or YYYY-MM-DDtoYYYY-MM-DD
bx news "openssl vulnerability" --freshness pw --count 5 | jq -r '.results[] | "\(.title)\n  \(.url)  [\(.age)]"'

# non-US / non-English (--country, --search-lang; also valid on news/context)
bx web "PaddleOCR" --country CN --search-lang zh-hans --count 5 | jq -r '.web.results[] | "\(.title)  \(.url)"'

# RAG grounding: search + scrape + extract in one call; --max-tokens must be >= 1024
bx "Python TypeError cannot unpack non-iterable NoneType" --max-tokens 2048 \
  | jq -r '.grounding.generic[] | "[\(.title)] \(.url)\n\(.snippets | join("\n"))\n"'
```

Read the `bx` skill for anything past that: `answers` (needs its own `--config`),
`images`/`videos`/`places`, `--goggles`/`--exclude-site`/`--extra`/`--offset`, config or
proxy trouble, or any non-zero exit code. Do not load the `mcp__brave-search__*` MCP tools;
the CLI supersedes them.

**Search query language:** default to English keywords unless the target information is
specific to the Chinese internet.

## Python Environment

- **Python & Package Management**: Python and dependencies are managed exclusively via `uv`
  using Python 3.12 (globally pinned in `~/.config/uv/.python-version`).
- **Execution Command**: Always run Python code and scripts using `uv run` or
  `uv run --python 3.12`. Never use the system `/usr/bin/python3` directly (reserved strictly
  for host OS packages), unless the user explicitly requests it. When injecting third-party
  packages, use repeated `--with` flags (e.g. `uv run --python 3.12 --with numpy --with scipy`,
  not `--with numpy,scipy`), and pin exact versions (e.g. `--with numpy==2.5.3`) whenever
  numerical reproducibility is required.
- **Output Buffering (`PYTHONUNBUFFERED=1`)**: `uv run` does not accept the `-u` flag. In
  non-TTY contexts (long-running scripts, background tasks, pipes, redirections) stdout
  defaults to 4 KB block buffering, producing empty or delayed logs. Always prepend
  `PYTHONUNBUFFERED=1` (e.g. `PYTHONUNBUFFERED=1 uv run --python 3.12 ...`) to keep output
  flushing in real time and avoid misdiagnosing a working process as hung.

## Keep These Surfaces Pure ASCII

Non-ASCII in the wrong place fails silently and far from its cause -- across the WSL/Windows
boundary, in archives, in shell and harness parsing. Keep ASCII-only:

- **Directory and file names.** No CJK, no spaces, no accents, no emoji. Applies to repos,
  skills, scripts and generated artifacts alike.
- **System and tool config files, comments included** -- dotfiles, shell rc, `settings.json`,
  `~/.claude/*`, `.reg`, systemd units. Write the comments in English.
- **Every skill's YAML frontmatter, `description` above all.** It is loaded into every
  session and matched against to decide triggering.

Prose docs (`README.md`, `references/*.md`, a skill's body below the frontmatter) may be
Chinese -- the surfaces above may not.

## Installing Skills and Configs

Copy files with `cp`. Do not use `ln -s`, and do not point an entry under `~/.claude/skills/`
at a cloned source repo -- this tree gets moved between machines, filesystems and operating
systems, and symlinks do not survive that. Copy only the files a skill needs at runtime,
not the whole development repo.
