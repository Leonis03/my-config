# Global Conventions and Environment Guidelines

## Web Search

- **Brave Search CLI (`bx`)**: For up-to-date information, documentation, or verifying uncertain facts, do not use the built-in search tool (`search_web`). Always use the **Brave Search CLI (`bx`)** (e.g., `bx "query" --max-tokens 2048` for RAG grounding, `bx web "query" --count 5` for raw search results). For specialized search modes (such as AI answers, news freshness filtering, images, or site scoping), refer to the `bx` skill (`~/.gemini/config/skills/bx/SKILL.md`).
- **Search Query Language**: Default to searching with **English** keywords unless the target information is specifically unique to the Chinese internet.

## Python Environment

- **Python & Package Management**: Python and dependencies are managed exclusively via `uv` using Python 3.13 (globally pinned in `~/.config/uv/.python-version`).
- **Execution Command**: Always run Python code and scripts using `uv run` or `uv run --python 3.13`. Never use the system `/usr/bin/python3` directly (which points to Python 3.12), unless the user explicitly requests/instructs to use the system-level Python.

## Subagents / Delegated Tasks

- **Subagent Model**: When dispatching or invoking subagents via `invoke_subagent`, always explicitly set `Model` to `"flash"` (instead of defaulting to `"inherit"`), unless the user explicitly specifies a different model.
