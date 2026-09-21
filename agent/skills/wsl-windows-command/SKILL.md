---
name: wsl-windows-command
description: Run Windows commands, programs, and config edits from WSL2 via interop, and drive other WSL distros from one distro. Use whenever a WSL task must touch the Windows side -- reg.exe registry reads and writes, launching pwsh.exe / powershell.exe / wt.exe / wsl.exe / any Windows .exe, editing Windows config under /mnt/c (Windows Terminal settings.json, AppData, .reg files), or converting between /mnt/c and \\wsl.localhost paths. Also covers cross-distro work -- running commands in another distro, sharing files through /mnt/wsl bind mounts, why those mounts vanish after wsl --shutdown, syncing a Git clone between distros, and how one distro's lifecycle silently breaks interop in another. Reach for it when a Windows command run from WSL misbehaves -- exec format error on a valid .exe, accept4 failed 110, quoting errors, execution-policy errors, or registry keys that cannot be found though they exist. Covers the /reg:64 redirection gotcha, ExecutionPolicy Bypass, and quote-safe invocation.
allowed-tools: Bash Read
---

# Running Windows Commands from WSL (Interop Bridge)

WSL2 can launch Windows executables directly through the `/mnt/c` interop bridge. The process runs on the Windows host as the logged-in Windows user, accessing the real registry, real `%LOCALAPPDATA%`, and the active desktop session.

---

## 1. The Five Golden Rules

1. **Always Use Absolute `/mnt/c/...` Paths**:
   Interactive bash/zsh aliases (like `clip`, `notepad`, `pwsh`) are not expanded in non-interactive agent shells. Never rely on mirrored Windows PATH.
2. **Always Detach stdin (`< /dev/null`)**:
   The `/init` interop bridge waits on standard input. Without `< /dev/null`, commands will hang indefinitely in automated scripts.
3. **Always Bypass PowerShell Execution Policy**:
   Scripts on `\\wsl.localhost` or downloaded files carry an untrusted zone flag. Always pass `-NoProfile -ExecutionPolicy Bypass`.
4. **`cd /mnt/c` Before Launching `cmd.exe`** (and only tools that need it):
   A Windows process inherits the WSL cwd as `\\wsl.localhost\<distro>\...`. `cmd.exe` refuses UNC working directories, prints a warning, and **silently falls back to `C:\Windows`** -- harmless for `echo`, corrupting for anything path-relative.
   Measured on this machine: `wsl.exe`, `powershell.exe` and `pwsh.exe` all run fine from a WSL cwd. Do not cargo-cult `cd /mnt/c` onto every interop call; it is only load-bearing for `cmd.exe` and the handful of legacy tools that behave the same way.
5. **Use the Bundled Helper for Robust Execution**:
   Use `scripts/run-pwsh.sh` -- it handles path conversion, quote safety, stdin detachment, and probes the interop socket instead of guessing.

---

## 2. Common Tool Locations

| Tool | Recommended WSL Path |
| :--- | :--- |
| **PowerShell 7** | `/mnt/c/Program Files/PowerShell/7/pwsh.exe` |
| **Windows PowerShell** | `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe` |
| **CMD** | `/mnt/c/Windows/System32/cmd.exe` |
| **Registry CLI** | `/mnt/c/Windows/System32/reg.exe` |
| **WSL CLI** | `/mnt/c/Windows/System32/wsl.exe` |
| **Windows Terminal** | resolve at runtime -- see below, never hardcode |

### Store apps (`wt.exe`): use the alias, not the real binary

A Store-packaged app has two paths, and the big one is the wrong one. Measured for
Windows Terminal 1.24:

| Path | What it is | From WSL |
| :--- | :--- | :--- |
| `/mnt/c/Program Files/WindowsApps/Microsoft.WindowsTerminal_<version>_x64__8wekyb3d8bbwe/wt.exe` | the real 132 KB PE | **`rc=126` permission denied.** The directory is `d--x--x--x`: traversable if you already know the exact name, but `ls` gives `Permission denied`, and the ACL denies execute. The name also carries a version that changes on every Store update |
| `/mnt/c/Users/<user>/AppData/Local/Microsoft/WindowsApps/wt.exe` | a **2-byte** file containing just `MZ` -- an App Execution Alias (`IO_REPARSE_TAG_APPEXECLINK`, `0x8000001b`) | **works, `rc=0`.** This is what `where.exe wt` returns, and `%LOCALAPPDATA%\Microsoft\WindowsApps` is on the Windows PATH by default |

The alias is the supported entry point; the `WindowsApps` copy is an implementation detail.
Do not be misled by the file sizes -- `MZ` is just enough magic to be recognised as an
executable, and the real target lives in the reparse point, which drvfs does not expose.

Resolve the alias path at runtime; `$USER` is not the Windows account name (see
[references/paths-and-configs.md](references/paths-and-configs.md)):

```bash
WT=$(ls -d /mnt/c/Users/*/AppData/Local/Microsoft/WindowsApps/wt.exe 2>/dev/null | head -1)
[ -n "$WT" ] || { echo "wt.exe alias not found" >&2; exit 1; }
```

---

## 3. Progressive Disclosure (Topic Routing)

To avoid context clutter, detailed instructions and edge cases live in dedicated references. Read the relevant document as needed:

| Task / Scenario | Read Reference Document |
| :--- | :--- |
| **Registry Operations**<br>WOW64 `/reg:64` redirection gotcha, `reg add/delete`, UTF-16 LE `.reg` files, restarting Explorer | [references/registry.md](references/registry.md) |
| **Hardened Setups (`ro` Mounts)**<br>`/mnt/c` mounted read-only (EROFS), operating Windows files via interop, temporary `rw` remount, `verify.sh` | [references/hardened-mounts.md](references/hardened-mounts.md) |
| **Paths & Config Files**<br>`wslpath` conversion, UNC path limits (`\\wsl.localhost`), Windows Terminal `settings.json` (JSONC), backups | [references/paths-and-configs.md](references/paths-and-configs.md) |
| **Cross-Distro Work**<br>Running commands in another distro, sharing filesystems via `/mnt/wsl` bind mounts, moving files between distros, `--terminate` vs `--shutdown` blast radius, why another distro breaks your interop | [references/cross-distro.md](references/cross-distro.md) |
| **Troubleshooting & Diagnostics**<br>`accept4 failed 110`, `Exec format error` (`binfmt_misc`), UTF-16 LE spacing/garble, nested quoting | [references/troubleshooting.md](references/troubleshooting.md) |

---

## 4. Quick Execution Patterns

### Inline PowerShell via Helper
```bash
bash scripts/run-pwsh.sh -c 'Get-Date; whoami'
```

### PowerShell Script via Helper
```bash
bash scripts/run-pwsh.sh -f ./script.ps1 -Param Value
```

### Direct Invocation (PowerShell 7 / CMD / Reg)
```bash
cd /mnt/c   # see Golden Rule 4

# PowerShell 7:
"/mnt/c/Program Files/PowerShell/7/pwsh.exe" -NoProfile -ExecutionPolicy Bypass -Command 'whoami' < /dev/null

# CMD:
"/mnt/c/Windows/System32/cmd.exe" /c "ver" < /dev/null

# Registry (always /reg:64):
"/mnt/c/Windows/System32/reg.exe" query "HKLM\Software\Classes\Directory\Background\shell" /reg:64 < /dev/null
```

### Command in Another Distro
```bash
/mnt/c/Windows/System32/wsl.exe -d Fedora -u root -e sh -c 'cat /etc/os-release' \
  < /dev/null 2>&1 | tr -d '\0\r'
```
Check `echo "$WSL_DISTRO_NAME"` first -- the `*` in `wsl -l -v` marks the **default** distro, not the one you are in, so `-d` can silently re-enter the current one. Read the `STATE` column too: `-d` cold-starts a `Stopped` distro however read-only the command looks. Omit `-u` unless the default user is wrong -- `-e sh -c` already runs as the target distro's default user, which is what user-level work wants; `-u root` is for `mount` and leaves root-owned files behind if used by habit.

### Syncing a Git Clone Across Distros
For two independent clones of the same repository, synchronize versions through the Git remote (usually GitHub), not by copying `.git` through `/mnt/wsl`. **The clone path is per-distro** -- resolve it in the target, never assume the one you use locally (here the same repo is `~/dev/my-config-private` in Fedora and `~/code/my-config-private` in Ubuntu):

```bash
# Resolve the path. Print the whole result -- piping a probe through `head` is how
# a present clone reads as a missing one.
/mnt/c/Windows/System32/wsl.exe -d Ubuntu -e sh -c \
  'find ~ -maxdepth 3 -name my-config-private -type d' < /dev/null 2>&1 | tr -d '\0\r'

# Then run Git inside the target distro, at the path you just resolved.
/mnt/c/Windows/System32/wsl.exe -d Ubuntu -e sh -c \
  'cd /home/<user>/code/my-config-private && GIT_TERMINAL_PROMPT=0 git fetch origin main \
     && git merge --ff-only origin/main' < /dev/null 2>&1 | tr -d '\0\r'
```

Run Git **inside** the target distro so that its `origin` URL, config, credential helper, hooks, and network environment are used. `--ff-only` refuses rather than inventing a merge commit; if it refuses, stop and read `git status` and the branch graph. `GIT_TERMINAL_PROMPT=0` is load-bearing under `-e ... < /dev/null`: with stdin detached, a missing credential otherwise becomes a hang or an opaque failure instead of an immediate error.

Do not check credentials with `git config credential.helper`. `gh auth setup-git` writes a **host-scoped** key, so the bare key reads empty on a clone that authenticates perfectly well -- measured on Ubuntu, where all three scopes were empty and a private-repo fetch still succeeded. Probe the key that actually applies:

```bash
git config --get-urlmatch credential.helper https://github.com
# -> !/usr/bin/gh auth git-credential
```

A pull updates the source tree, not whatever was deployed from it. Skills in this repo live in `~/.claude/skills` and `~/.gemini/config/skills`, so the sync ends with `bash tools/sync-skills.sh deploy`, not with the fast-forward -- `tools/.sync-map` is gitignored and already present per machine. `/mnt/wsl` gives direct file access to another clone, but it does not fetch GitHub versions and a `git -C /mnt/wsl/<distro>/...` command would use the calling distro's Git environment.

### Files in Another Distro
```bash
# Bind the other distro's root into the shared tmpfs; then read it as ordinary local files.
/mnt/c/Windows/System32/wsl.exe -d Fedora -u root -e sh -c \
  'mkdir -p /mnt/wsl/Fedora && mount --bind / /mnt/wsl/Fedora' < /dev/null 2>&1 | tr -d '\0\r'
ls /mnt/wsl/Fedora/home

# After the bind exists, file operations do not invoke wsl.exe:
printf c > /mnt/wsl/Fedora/home/<user>/test.txt
cat /mnt/wsl/Fedora/home/<user>/test.txt
```
Anything bind-mounted **under `/mnt/wsl`** is visible in every WSL2 distro. Use this instead of `\\wsl.localhost` for file work -- it measured ~23x faster on a 21.6 MB tree. The bind is read/write by default, subject to normal Unix permissions and UID alignment.

The mounts are not persistent: `/mnt/wsl` is a shared tmpfs and `wsl --shutdown` removes the bind mounts. On a systemd distro, restore them with a **plain** `/ /mnt/wsl/<distro> none bind,nofail 0 0` line in each distro's `/etc/fstab` -- systemd creates the mount point itself. Do not reach for `X-mount.mkdir`: it makes WSL's pre-tmpfs `mount -a` pass succeed and leaves a shadowed orphan mount that `findmnt` lists but no path can reach (verified across a real `wsl --shutdown`; see the reference). For a one-off, rerun the guarded mount command. Do not expose an entire root read/write when a home-directory bind is sufficient.

See [references/cross-distro.md](references/cross-distro.md) before doing either -- both have non-obvious consequences for interop and for distro lifecycle.
