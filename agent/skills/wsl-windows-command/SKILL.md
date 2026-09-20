---
name: wsl-windows-command
description: Run Windows commands, programs, and config edits from inside WSL2 via interop, and drive other WSL distros from one distro. Use whenever a task in a WSL shell needs to touch the Windows side: reading or writing the Windows registry with reg.exe, launching pwsh.exe / powershell.exe / wt.exe / wsl.exe / any Windows .exe, editing Windows user config files under /mnt/c (Windows Terminal settings.json, AppData, registry .reg files), or converting between /mnt/c and \\wsl.localhost paths. Also covers cross-distro work -- running commands in another distro, sharing or moving files between distros via /mnt/wsl bind mounts, and why one distro's lifecycle silently breaks interop in another. Reach for this skill the moment a Windows command run from WSL misbehaves -- "exec format error" on a valid .exe, "accept4 failed 110", quoting errors, "cannot be loaded because running scripts is disabled" execution-policy errors, or registry keys that "cannot be found" even though they exist. Covers the /reg:64 redirection gotcha, ExecutionPolicy Bypass, and quote-safe invocation.
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
cd /mnt/c && /mnt/c/Windows/System32/wsl.exe -d Fedora -u root -e sh -c 'cat /etc/os-release' \
  < /dev/null 2>&1 | tr -d '\0\r'
```
Check `echo "$WSL_DISTRO_NAME"` first -- the `*` in `wsl -l -v` marks the **default** distro, not the one you are in, so `-d` can silently re-enter the current one.

### Files in Another Distro
```bash
# Bind the other distro's root into the shared tmpfs; then read it as ordinary local files.
cd /mnt/c && /mnt/c/Windows/System32/wsl.exe -d Fedora -u root -e sh -c \
  'mkdir -p /mnt/wsl/Fedora && mount --bind / /mnt/wsl/Fedora' < /dev/null 2>&1 | tr -d '\0\r'
ls /mnt/wsl/Fedora/home
```
Anything bind-mounted **under `/mnt/wsl`** is visible in every WSL2 distro. Use this instead of `\\wsl.localhost` for file work -- it measured ~23x faster on a 21.6 MB tree.

See [references/cross-distro.md](references/cross-distro.md) before doing either -- both have non-obvious consequences for interop and for distro lifecycle.
