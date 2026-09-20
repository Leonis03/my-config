# Global Conventions and Environment Guidelines

## Web Search

**Never use the built-in `search_web`.** Every web lookup -- current events, docs, version
numbers, verifying an uncertain fact -- goes through the Brave Search CLI `bx`. It is the
only search path on this machine.

`bx` writes JSON to stdout. Two rules make a call safe: **always project through jq** (raw
output is ~120x the tokens), and **mind the result path per subcommand** -- `web` puts rows
under `.web.results[]`, everything else under `.results[]`, and a wrong path returns 0 rows
at exit 0 with no error. These five cover almost everything:

```bash
# read page bodies -- search + scrape + extract in one call; --max-tokens must be >= 1024
bx "Python TypeError cannot unpack non-iterable NoneType" --max-tokens 2048 \
  | jq -r '.grounding.generic[] | "[\(.title)] \(.url)\n\(.snippets | join("\n"))\n"'

# triage -- URLs only, ~180 tokens
bx web "axum middleware ordering" --include-site docs.rs --count 10 | jq -r '.web.results[].url'

# normal search -- title, url, snippet
bx web "query" --count 5 | jq -r '.web.results[] | "\(.title)\n  \(.url)\n  \(.description)\n"'

# news with publication dates; --freshness pd|pw|pm|py or YYYY-MM-DDtoYYYY-MM-DD
bx news "openssl vulnerability" --freshness pw --count 5 | jq -r '.results[] | "\(.title)\n  \(.url)  [\(.age)]"'

# non-US / non-English (--country, --search-lang; also valid on news/context)
bx web "PaddleOCR" --country CN --search-lang zh-hans --count 5 | jq -r '.web.results[] | "\(.title)  \(.url)"'
```

Read the `bx` skill (`~/.gemini/config/skills/bx/SKILL.md`) for anything past that: `answers`
(needs its own `--config`), `images`/`videos`/`places`, `--goggles` / `--exclude-site` /
`--extra` / `--offset`, config or proxy trouble, or any non-zero exit code. That skill file is
shared with another harness, so it routes some cases to a built-in `WebSearch` -- ignore those
rows here; the deep-read path on this machine is `bx "q" --max-tokens N` above.

**Search query language:** default to English keywords unless the target information is
specific to the Chinese internet.

## Python Environment

- **Python & Package Management**: Python and dependencies are managed exclusively via `uv`
  using Python 3.12 (globally pinned in `~/.config/uv/.python-version`).
- **Execution Command**: Always run Python code and scripts using `uv run` or
  `uv run --python 3.12`. Never use the system `/usr/bin/python3` directly (reserved strictly
  for host OS packages), unless the user explicitly requests/instructs to use the system-level
  Python. When injecting third-party packages, always use repeated `--with` flags for multiple
  dependencies (e.g., `uv run --python 3.12 --with numpy --with scipy ...` rather than
  `--with numpy,scipy`), and pin exact versions (e.g., `--with numpy==2.5.3`) whenever
  numerical reproducibility is required.
- **Output Buffering (`PYTHONUNBUFFERED=1`)**: `uv run` does not accept the `-u` flag. When
  executing Python scripts (especially long-running scripts, background tasks, pipes, or file
  redirections), standard output defaults to 4 KB block buffering in non-TTY environments,
  resulting in empty logs or delayed output. Always prepend `PYTHONUNBUFFERED=1` when running
  Python commands via `uv run` (e.g., `PYTHONUNBUFFERED=1 uv run --python 3.12 ...`) to ensure
  real-time flushing and prevent hung-process misdiagnoses.

## Keep These Surfaces Pure ASCII

Non-ASCII in the wrong place fails silently and far from its cause -- across the WSL/Windows
boundary, in archives, in shell and harness parsing. Keep ASCII-only:

- **Directory and file names.** No CJK, no spaces, no accents, no emoji. Applies to repos,
  skills, scripts and generated artifacts alike.
- **System and tool config files, comments included** -- dotfiles, shell rc, `config.json`,
  `~/.gemini/config/*`, `.reg`, systemd units. Write the comments in English.
- **Every skill's YAML frontmatter, `description` above all.** It is loaded into every
  session and matched against to decide triggering.

Prose docs (`README.md`, `references/*.md`, a skill's body below the frontmatter) may be
Chinese -- the surfaces above may not.

## Subagents / Delegated Tasks

- **Subagent Model**: When dispatching or invoking subagents via `invoke_subagent`, always
  explicitly set `Model` to `"flash"` (instead of defaulting to `"inherit"`), unless the user
  explicitly specifies a different model.
