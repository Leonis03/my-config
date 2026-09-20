# Path Conversion and Windows Config Management

When operating across the WSL-Windows boundary, path formats and configuration conventions differ significantly.

---

## 1. Path Conversion with `wslpath`

Always use the built-in `wslpath` utility instead of hand-crafting or replacing slashes with `sed`:

```bash
# Convert WSL Linux path to Windows UNC path:
wslpath -w "$HOME/file"
# Output: \\wsl.localhost\Ubuntu\home\<user>\file

# Convert Windows path to WSL Linux path:
wslpath -u 'C:\Users\<user>\Desktop\report.pdf'
# Output: /mnt/c/Users/<user>/Desktop/report.pdf

# Convert WSL /mnt/c path to Windows drive path:
wslpath -w /mnt/c/Users/<user>/file
# Output: C:\Users\<user>\file
```

### UNC Paths (`\\wsl.localhost\...`) and Tool Constraints
- Files in WSL are visible to Windows via `\\wsl.localhost\<distro>\...` (or older `\\wsl$\<distro>\...`).
- **Working Directory Caveat**: Some Windows tools (e.g., `cmd.exe`, MATLAB, older compilers) refuse to run with a UNC path as the current working directory, printing:
  ```text
  '\\wsl.localhost\Ubuntu\...'
  CMD.EXE was started with the above path as the current directory.
  UNC paths are not supported. Defaulting to Windows directory.
  ```
- **Mitigation**: If a tool cannot handle UNC paths, pass input files via absolute paths or copy inputs to a temporary directory under `C:\` before running.

---

## 2. Editing Windows Application Configurations

Windows user configuration files reside under `/mnt/c/Users/<user>/...`.

### Finding the Windows Profile Directory

**Never build that path from `$USER`, and never hardcode an account name.** The Windows
account name is not the Linux one, and the failure is silent in a specific way that makes it
easy to ship: `/mnt/c` is drvfs and inherits NTFS case-insensitivity, so `$USER` "works"
whenever the two names differ only in case -- which is common, and was true on the machine
this page was written for. Everywhere else the path simply does not exist and the caller
sees an empty result rather than an error.

Glob instead, and fail loudly when nothing matches:

```bash
WT_SETTINGS=$(ls -d /mnt/c/Users/*/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json 2>/dev/null | head -1)
[ -n "$WT_SETTINGS" ] || { echo "Windows Terminal settings.json not found" >&2; exit 1; }
```

When several profiles match, or you need the path for a profile that has no such file yet,
ask Windows for the authoritative answer -- `%USERPROFILE%`, **not** `%USERNAME%` (the
profile directory does not have to match the account name: it keeps its original spelling
after a rename, and domain accounts get `user.DOMAIN`):

```bash
WIN_HOME=$(wslpath -u "$(cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c 'echo %USERPROFILE%' < /dev/null 2>/dev/null | tr -d '\0\r')")
WT_SETTINGS="$WIN_HOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
```

`cd /mnt/c` is required here: `cmd.exe` refuses a UNC working directory (Golden Rule 4).
In zsh, guard any bare glob with `[ -d /mnt/c/Users ]` -- an unmatched glob in a `for` list
aborts the whole script (`NOMATCH`), unlike bash.

### Critical Rules for Config Editing

1. **Always Create a Backup First**:
   ```bash
   cp "$WT_SETTINGS" "${WT_SETTINGS}.bak_$(date +%Y%m%d%H%M%S)"
   ```
   Inform the user before touching active configuration files.

2. **Respect JSONC (JSON with Comments)**:
   Windows Terminal's `settings.json` uses **JSONC**, which allows:
   - Single-line comments (`// ...`) and block comments (`/* ... */`)
   - Trailing commas in arrays and objects (`{"a": 1,}`)
   
   > **Caution**: Do **not** use Python's built-in `json` module or `jq` without lenient comment-stripping, as strict JSON parsers will fail on JSONC syntax.

3. **Check File Encoding (UTF-8 vs UTF-16 with BOM)**:
   Many Windows configuration files use UTF-8, but some use UTF-16 LE with a Byte Order Mark (BOM). Always check before modifying:
   ```bash
   file -i "$WT_SETTINGS"
   ```

4. **Watch for Running Applications and Locks**:
   If an application (like Windows Terminal) is currently open, it may hold an in-memory copy and overwrite file changes upon exit. Advise the user or perform modifications when the app is closed.
