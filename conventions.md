# Conventions

*English · [中文（正本 / canonical）](conventions.zh.md) · back to [README](README.md)*

- **These surfaces are pure ASCII only**: directory and file names; system and tool config
  files (**including their comments**, which are written in English); every skill's YAML
  frontmatter (especially `description`, which loads every session and participates in
  trigger matching). Prose docs (`README.zh.md`, `references/*.md`, everything below a
  skill's frontmatter) are in Chinese. Non-ASCII in the wrong place fails **silently and far
  from its cause** -- across the WSL/Windows boundary, in archives, in shell and harness
  parsing.
- **Markdown filenames are lowercase kebab-case**: `wsl-gui-and-ime.md` -- no capitals,
  underscores or spaces. Forensic records and point-in-time snapshots get a `-YYYYMMDD`
  suffix (`etc-diff-analysis-20260330.md`, `pnpm-npm-cleanup-20260920.md`); process docs and
  evergreen docs do not. The only exceptions are **protocol filenames**: `README.md`,
  `README.zh.md`, `SKILL.md`, `SKILL.zh.md`, `CLAUDE.md`, `TROUBLESHOOTING.md` -- tools and
  harnesses look these up literally, so renaming them breaks things.
- **Root-level docs are bilingual; subdirectory docs are not.** Every document at the root
  comes as a pair -- `x.md` in English (what GitHub renders by default) and `x.zh.md` as the
  canonical Chinese. Currently three pairs: `README`, `conventions`, `redaction`. Changes
  land in the Chinese version first, then get synced to English -- the pitfall index is
  compressed debugging conclusions, and those are worth getting exactly right in the author's
  first language before translating. **Subdirectory docs are Chinese-only**, with skills as
  the exception: they are read by agents, so both languages earn their keep.
- **The README is a landing page and a router**: header, start here, layout, pitfall index,
  license. Anything substantial that is not needed on every read moves to its own file, with
  one row in the "Start here" table pointing at it -- the same split skills use between
  `SKILL.md` and `references/`. The pitfall index **deliberately stays** in the README: it is
  the most interesting thing here, and moving it out would leave a bare table of contents.
- **Python goes through `uv`, pinned to 3.12**. The system `/usr/bin/python3` is reserved for
  Ubuntu's apt packages; leave it alone.
- **Install skills with `cp`, never `ln -s`**. This tree gets moved between machines, file
  systems and operating systems, and symlinks do not survive that.
- **Sync skills with `bash tools/sync-skills.sh`, not a bare `cp` either.** The repo says
  `<your-home>`, `CourseName` and similar placeholders; the script expands them to real values
  when writing `~/.claude/skills/` and `~/.gemini/config/skills/`, and compares the
  **substituted** bytes when verifying -- so "the hashes match" means "repo == deployed copy,
  modulo redaction". Running it with no arguments is a read-only check. How to write a home
  directory depends on **whether a shell will expand it**: if it will, write `$HOME` (a
  runtime variable shipped as-is, not a placeholder); only where it will not do you write
  `<your-home>` -- just two lines of JSON left in the whole repo. See
  [`agent/skills/README.md`](agent/skills/README.md).
- **Do temporary things in `tmp/`**: backup copies taken before an edit, intermediate script
  output, snippets you want to try, raw command output. Not scattered across the repo root,
  and not in the system `/tmp` either (it is gone after a reboot, right when you want to look
  again tomorrow). The directory is gitignored, `git archive` will not export it, and
  `privacy-gate.sh` **skips** it -- so it can hold real paths and account names without
  turning the gate red every day. `tmp/.gitkeep` is tracked, so a fresh clone still has the
  directory.
- **Run `bash tools/privacy-gate.sh` before publishing.** It only covers known shapes; passing
  is not the same as safe -- `wsl/storage/` is raw forensic output and has to be read by hand.
  The account names are **not in the script** (putting them there would make the script itself
  the leak); they are read at run time from `tools/.privacy-names`, which is gitignored.
- **Export a public copy with `git archive`, not `cp -r`.** `cp -r` copies the local private
  files that gitignore was hiding straight into the public directory. This repo is a
  **private primary plus a public snapshot**; the public clone carries its own `.git`, so
  syncing is always these four steps:

  ```bash
  cd ~/dev/my-config                                   # the public clone
  find . -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +
  ( cd ../my-config-private && git archive HEAD ) | tar -x -C .
  git add -A && git commit && git push
  ```

  **Do not skip the wipe.** `tar -x` overwrites but never deletes, so a file removed in the
  private repo would linger in the public one. The wipe needs `-not -name '.git'` or it takes
  the repository with it. **Use `git archive`, not `cp -r`**, so `tools/.privacy-names`,
  `tools/.sync-map` and `tmp/` cannot get in. Check before pushing:
  `find . -type f -not -path './.git/*' | git check-ignore --stdin` should print nothing.

  The public repo keeps **normal history** -- plain `commit` and `push`, never `--amend` plus
  a force push, which would break anyone who has cloned it. (Two amends happened early on: one
  to add the licenses, one to reformat the commit message, both before anyone could have
  cloned it.)
- **Credentials never enter version control.** Tokens that need to be environment variables go
  in `~/.shell_secrets` (`chmod 600`), loaded automatically at the end of `~/.shell_common`.

