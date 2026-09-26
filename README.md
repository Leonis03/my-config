# my-config

*English · [中文（正本 / canonical）](README.zh.md)*

Configuration, skills, and hard-won debugging notes from one WSL2 development machine.

The environment is **Windows 11 + WSL2 + zsh**, driven mainly by Claude Code and the
Antigravity CLI, with networking through a local proxy. Two kinds of content live here:
**config files you can deploy as-is**, and **conclusions left behind by debugging** -- the
latter is usually worth more than the config itself, because it records *why* things are the
way they are.

> **Migration in progress.** **Ubuntu 24.04** was the primary distro; day-to-day work has
> moved to **Fedora 44** and the configuration is being aligned to it. Both are installed
> side by side: Ubuntu is still the WSL default (the `*` in `wsl -l -v`), but commands are
> actually typed in Fedora. The three core shell-config layers (`.zshenv`, `.shell_wslfn`,
> `.shell_common`) hash identically on both; what still differs is either dictated by the
> distro (Fedora's fcitx5 block, its `/etc/bashrc` chain) or still converging. The full
> comparison, split into what is avoidable and what is not, is in
> [`wsl/distro-differences.md`](wsl/distro-differences.md).
>
> Most references to Ubuntu elsewhere in these docs still hold; where they do not, the
> difference is recorded in that file.

> Every path, username, machine identifier, port and timestamp is redacted (`$HOME`,
> `<your-linux-user>`, `<your-windows-user>`, `<vm-1>`, `<proxy-port>`, `<ssh-port>`, `<t-created>`), and email
> addresses are written as `your-old-email@example.com`. Substitute your own before
> deploying.
>
> The `<t-...>` tokens under `wsl/storage/` are **stable** placeholders: the same token means
> the same instant wherever it appears, so timestamp columns can still be compared across
> forensic blocks. Intervals between events are spelled out in prose.

---

## Start here

| What you want | Where |
| :--- | :--- |
| **Rebuild the whole environment on a new machine** | [`wsl/setup/`](wsl/setup/) -- the rebuild guide plus 12 config originals you can `cp` directly |
| Set up Git and GitHub (including the privacy email) | [`git-github/`](git-github/) |
| Set up Claude Code | [`agent/claude-code/`](agent/claude-code/) |
| Find a ready-made skill, or sync skills to this machine | [`agent/skills/`](agent/skills/) -- 14 of them; deploy with `tools/sync-skills.sh`, not `cp` |
| Look up one specific trap | See the pitfall index below |
| Understand the writing and publishing rules here | [`conventions.md`](conventions.md) -- ASCII boundaries, naming, `tmp/`, the pre-publish gate, the two-repo sync |
| Understand the placeholder scheme: no real usernames in the repo, yet everything resolves on deploy | [`redaction.md`](redaction.md) -- the three classes of value and the two pipelines |

---

## Layout

### [`wsl/`](wsl/) -- WSL2 and the Linux side

| Directory | Contents |
| :--- | :--- |
| [`setup/`](wsl/setup/) | **The rebuild guide.** `/etc/wsl.conf`, apt mirrors, zsh + oh-my-zsh, the four-layer shell config split, toolchain. `files/` holds the deployable originals |
| [`gui-ime/`](wsl/gui-ime/) | WSLg GUI apps and the fcitx5 Chinese input method |
| [`storage/`](wsl/storage/) | Moving a distro off the system drive, reclaiming VHDX space, pnpm/npm disk cleanup. Includes a full forensic analysis of one EACCES permission failure |
| [`zsh/`](wsl/zsh/) | Installing zsh, and getting out of System32 automatically |

The core idea is **`appendWindowsPath=false` plus explicit function bridging**: do not inject
Windows' several hundred PATH entries -- wrap only the handful of `.exe`s you actually need in
shell functions.

### [`windows/`](windows/) -- the Windows side

[`terminal/`](windows/terminal/) (Windows Terminal config) ·
[`powershell/`](windows/powershell/) (PowerShell 7 profile, PSReadLine, closing every File
Explorer window without killing the shell) ·
[`context-menu/`](windows/context-menu/) (diagnosing and trimming context-menu entries) ·
[`windows-update/`](windows/windows-update/) (pin feature updates to 24H2 while keeping
updates visible)

### [`agent/`](agent/) -- AI toolchain

| Directory | Contents |
| :--- | :--- |
| [`claude-code/`](agent/claude-code/) | `settings.json`, the global `CLAUDE.md`, a 159-line statusline script. Byte-identical to the live copies |
| [`skills/`](agent/skills/) | 14 skills, serving both `~/.claude/` and `~/.gemini/config/`. The repo copy is redacted; deploy and verify through [`tools/sync-skills.sh`](tools/sync-skills.sh) |
| [`antigravity/`](agent/antigravity/) | The `~/.gemini/config/AGENTS.md` original (which forces `bx`), plus `agy` CLI usage and image handoff |
| [`brave-search/`](agent/brave-search/) | The `bx` CLI and the Brave Search MCP integration |

### [`git-github/`](git-github/) · [`tools/`](tools/) · `tmp/`

Git privacy configuration and a history-scrubbing runbook (including GitHub's four file-size
thresholds); Python and remote-execution pitfalls; Docker;
[`tools/latex/`](tools/latex/) (the VS Code LaTeX Workshop toolchain, and why ChkTeX has to be
off for Chinese documents); and two scripts --
[`tools/privacy-gate.sh`](tools/privacy-gate.sh) (the pre-publish redaction gate) and
[`tools/sync-skills.sh`](tools/sync-skills.sh) (rendered skill deployment and verification).

`tmp/` is a **scratch area**, gitignored. Every temporary edit, trial script run, and
pre-overwrite backup happens in there. All three are covered in [`conventions.md`](conventions.md).

---

## Pitfall index

Entries that took real time to diagnose and whose conclusion is not obvious.

| Pitfall | Symptom | Where |
| :--- | :--- | :--- |
| **Non-interactive shells do not expand aliases** | Scripts and AI agents get `command not found` while the same command works when you type it | [`wsl/setup/`](wsl/setup/) section 2 |
| **wslu misreports under systemd** | `WSL Interoperability is disabled`, even though `wsl.conf` is plainly correct | [`git-github/README.md`](git-github/README.md) 2.3 |
| **`filter-repo` silently destroys changes** | Uncommitted modifications to tracked files vanish after a history rewrite, with no warning | [`git-github/email-scrub-runbook.md`](git-github/email-scrub-runbook.md) section 2 |
| **`no_proxy` wildcards do not work** | A request to a local service goes through the proxy anyway and returns an empty 502 that looks like "the request failed" | [`tools/python/`](tools/python/) section 1 |
| **f-string quoting rules** | `invalid syntax`, and 3.10 behaves differently from 3.12 | [`tools/python/`](tools/python/) section 2 |
| **`pkill -f` kills itself** | Returns 255, which looks like the SSH connection dropped | [`tools/remote-ssh.md`](tools/remote-ssh.md) section 2 |
| **Setting thread counts too late in Python** | BLAS is already initialised; 48 workers spawn 3077 threads and run 227x slower | [`tools/remote-ssh.md`](tools/remote-ssh.md) section 3 |
| **Drive-letter paths never exist in WSL** | `C:/Windows/Fonts/...` finds no font; you get silent tofu squares and no error | [`agent/skills/wsl-cjk-font/`](agent/skills/wsl-cjk-font/) |
| **A hardcoded Windows account name expires** | Tofu squares again, silently: `/mnt/c/Users/<the old machine's account>/...` does not exist here. WSL has no `%USERPROFILE%`; use `glob("/mnt/c/Users/*/...")` | [`agent/skills/README.md`](agent/skills/README.md) |
| **drvfs case-insensitivity hides a hardcoded account name** | Nastier than the row above: the Windows account name and `$USER` here differ only in case, so the string comparison is false while `/mnt/c/Users/$USER/...` still stats successfully. "Build the Windows home directory from `$USER`" is therefore **always passing** on this machine, and only fails -- silently -- on a machine where the names really differ | [`wsl/setup/`](wsl/setup/) FAQ |
| **zsh aborts the whole file on an unmatched glob in a `for` list** | One `~/.shell_common` is shared by bash and zsh; bash passes the literal through, zsh exits with `no matches found` and everything after it never runs | [`wsl/setup/`](wsl/setup/) FAQ |
| **Non-interactive bash has no equivalent of `.zshenv`** | The interop functions reach scripts and agents on the zsh side but not on the bash side: `bash -c` and `#!/bin/bash` read neither startup file. The verification checklist historically said `bash -ic`, and the `-i` happened to paper over the gap. The way out is `BASH_ENV` | [`wsl/setup/`](wsl/setup/) checklist item 3 |
| **`.gitattributes` does not reach inside a zip** | The entire file is reported as rewritten and the real change drowns in a fake diff | [`git-github/crlf-and-diffing.md`](git-github/crlf-and-diffing.md) |
| **`/reg:64` redirection** | A registry key "cannot be found" even though it plainly exists | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **`binfmt_misc` is global across distros** | After starting or stopping another distro, Windows commands suddenly fail with `exec format error`, with no visible connection -- and you cannot use interop to rescue interop | [`wsl/setup/`](wsl/setup/) step 1.3 |
| **`accept4 110` has two distinct causes** | Applying the usual "swap the socket" prescription fails on every socket alike, burning an hour | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **The `*` in `wsl -l -v` marks the default, not the current distro** | Read it as "you are here" and `-d <other>` silently re-enters the one you are already in. Write a marker into "the other distro" and read it back and the test passes perfectly -- it is your own file. Only `stat -c %d` gives it away. The authority is `$WSL_DISTRO_NAME` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) section 1 |
| **Moving files between distros by way of Windows** | It works, but the same file set is 23x slower (0.97 s vs 22.5 s). `/mnt/wsl` is a shared tmpfs; bind-mount under it for a direct path instead of going through 9p on `\\wsl.localhost` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) section 2 |
| **`--terminate` does not release a disk another distro has bind-mounted** | `wsl -l -v` says `Stopped` while the other distro keeps writing to its ext4, and the writes are there at next boot. The VHDX stays attached too, so compaction requires `--shutdown` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) section 5 |
| **systemd >= 256 cannot start a user session under WSL** | `Failed to spawn executor: Device or resource busy`. Ubuntu's 255 is fine; Fedora's 259 always breaks | [`wsl/distro-differences.md`](wsl/distro-differences.md) |
| **cmd.exe refuses a UNC working directory** | It falls back to `C:\Windows` silently, so every path-relative operation is wrong without any error | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **WSL does not update through Windows Update** | Windows is version-pinned, so you assume WSL is pinned too; in fact the two channels are unrelated | [`wsl/setup/`](wsl/setup/) maintenance section |
| **Leave `.wslconfig` out of the repo and the proxy is guaranteed to break** | `host_ip="127.0.0.1"` is only correct under `networkingMode=mirrored`. Miss that Windows-side file during a rebuild, WSL falls back to NAT, `127.0.0.1` points at WSL itself, and every proxied request is refused -- far from the cause, with nothing in `~/.shell_common` pointing at it | [`wsl/setup/`](wsl/setup/) step 0.1 |
| **ChkTeX floods Chinese documents with false positives** | `Use "'" (ASCII 39) instead of "´"` fills the output and buries the real errors. It scans bytes rather than decoding UTF-8, so a continuation byte of a Chinese character landing on `´` (0xB4) reads as a typography mistake. No rule tweak helps; turn it off | [`tools/latex/`](tools/latex/) |
| **`-Source` given, still goes online** | Installing the Windows Chinese font package offline fails even with the ISO mounted -- `Add-WindowsCapability` contacts Windows Update first unless `-LimitAccess` is also passed | [`tools/latex/`](tools/latex/) · [`agent/skills/wsl-cjk-font/`](agent/skills/wsl-cjk-font/) |
| **pnpm blocks postinstall without saying so** | `pnpm update -g --latest` exits 0 and looks installed, but the command will not run -- pnpm 10+ skips lifecycle scripts by default. Allow them per package with `--allow-build=<name>` | [`wsl/storage/pnpm-npm-cleanup-20260920.md`](wsl/storage/pnpm-npm-cleanup-20260920.md) 3.2 |
| **A redaction placeholder borrowed `$HOME`** | One token meant both "a home directory awaiting substitution" and a genuine shell variable. Rendering it hardcoded the local path into `set-deepln.sh`, so the script was wrong everywhere on a rented GPU box. The test should be "will a shell expand this", not what kind of file it is | [`agent/skills/README.md`](agent/skills/README.md) |
| **A wrong jq path silently yields 0 rows** | Using `.web.results[]` against `bx news` exits 0 with no error and looks like "no results for this topic" | [`agent/brave-search/bx-cli.md`](agent/brave-search/bx-cli.md) section 6 |
| **A search-gating skill became a fixed tax** | `CLAUDE.md` is resident every session while a skill body loads on demand; making a 2.2k skill a prerequisite for `bx` inverts the cost structure | [`agent/claude-code/README.md`](agent/claude-code/README.md) |
| **Redaction regexes keep leaking** | The same value rendered differently (case, column alignment, another command's output format, a label in another language) slips past the check. Five rounds in a row failed here | [`tools/privacy-gate.sh`](tools/privacy-gate.sh) header comment |
| **The input method will not bind under Wayland** | An Electron app runs fine but cannot type Chinese, and no flag helps. Weston reserves `input_method` for its own IME client and WSLg does not run one; worse, fcitx5 hitting error 71 **exits the whole process**, taking the X11-side input method with it | [`wsl/gui-ime/`](wsl/gui-ime/) sections 1 and 9 |
| **`wmctrl` is useless under WSLg** | Window-placement scripts silently do nothing. The Weston WM does not export `_NET_CLIENT_LIST`, so `wmctrl -l` always fails -- and the script uses exactly that to find windows | [`wsl/gui-ime/`](wsl/gui-ime/) section 8 |
| **The machine changed, the document did not** | A "deployment summary" whose display parameters, file roles and fixes all disagree with this machine. Comparing first-run traces (`Crashpad/client_id`) against the document's own date proves it was never written on this machine at all | [`wsl/gui-ime/`](wsl/gui-ime/) sections 5 and 8 |

---

## License

Copyright © 2026 Leo `<28289630+Leonis03@users.noreply.github.com>`

**Code and config are [MIT](LICENSE); documentation is [CC BY 4.0](LICENSE-DOCS).** Both allow
commercial use and redistribution, and both require attribution.

| Scope | License | What it covers |
| :--- | :--- | :--- |
| Code and config | [MIT](LICENSE) | Everything that is **not** a `.md` file -- the `.sh` and `.py` files under `tools/` and `agent/skills/*/scripts/`, the `.ps1` files under `windows/`, the config originals under `wsl/setup/files/`, and `.gitignore` |
| Documentation | [CC BY 4.0](LICENSE-DOCS) | Every `.md` file -- both READMEs, the per-directory guides, skill bodies, pitfall write-ups and forensic analyses |

The split exists because **Creative Commons itself recommends against using CC licenses for
software**, and so does the FSF (CC BY 4.0 is a free license and is GPL-compatible, but "should
not be used on software"); the OSI has never approved any CC license. CC BY 4.0 §2(b)(2)
expressly grants **no patent rights**, §6(a) terminates the license **automatically** on breach
(§6(b) allows a 30-day cure), and §2(a)(5)(B) forbids applying technological protection
measures. Harmless for prose; real friction for scripts that get copied around.

### Third-party content

The following is **not** covered by either license above; copyright stays with its authors:

- `windows/powershell/SamplePSReadLineProfile_GitHub.ps1` -- a verbatim 694-line copy of the
  sample profile from [PowerShell/PSReadLine](https://github.com/PowerShell/PSReadLine),
  Copyright (c) 2013 Jason Shirk, **BSD-2-Clause**. The full notice is reproduced in that
  file's header.
- `wsl/setup/files/bashrc` retains fragments of Debian's stock `.bashrc`
  (`shopt -s checkwinsize`, `lesspipe`, `dircolors`, `alias ll=` and similar).
- Several files under `wsl/setup/files/` contain installer-generated blocks:
  oh-my-zsh lines and the Antigravity CLI PATH block.

These are widely-copied boilerplate fragments, noted here for accuracy; no copyright is
claimed over them.
