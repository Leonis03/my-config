# Troubleshooting WSL-Windows Interop

A comprehensive diagnostic guide for common errors, socket timeouts, binfmt registration issues, and quoting pitfalls when invoking Windows programs from WSL.

---

## 1. Top Diagnostic Issues

### 1.1 `UtilAcceptVsock: accept4 failed 110` (Connection Timed Out)
* **Symptom**: Executing any Windows executable fails -- sometimes after a stall of several
  seconds, sometimes immediately -- with:
  ```text
  <3>WSL (XXXXX - ) ERROR: UtilAcceptVsock:273: accept4 failed 110
  ```
* **Two different causes produce this identical error. Diagnose before acting** -- guessing wrong burns a lot of time.

#### Step 1: probe every socket

```bash
for s in /run/WSL/*_interop; do
  printf '%-28s ' "$s"
  WSL_INTEROP="$s" /mnt/c/Windows/System32/cmd.exe /c "echo OK" < /dev/null 2>&1 | tr -d '\0\r' | head -1
done
```

#### Step 2: read the result

* **Some sockets work, others fail** -> **stale socket**. The shell's `WSL_INTEROP` points at
  an expired session (e.g. `/run/WSL/64736_interop`). Export a working one:
  ```bash
  export WSL_INTEROP="/run/WSL/2_interop"   # or whichever probed OK
  ```

* **ALL sockets fail identically** -> **NOT a stale socket.** The Windows-side interop
  listener is down and is refusing the vsock callback; no `WSL_INTEROP` value can fix it.
  Socket-swapping here is wasted effort. Remedies, cheapest first:
  1. Start (or open a terminal tab in) **another WSL distro** -- this re-establishes the
     host-side bridge and has been observed to restore interop for the distro already running.
  2. From a **Windows** shell, `wsl --shutdown`, then reopen WSL. Note this kills every
     distro, including the session you may be running in -- confirm with the user first.

> A useful tell: the stale-socket case usually stalls for several seconds before failing,
> while a downed host listener tends to fail fast and uniformly across every socket.

---

### 1.2 `cannot execute binary file: Exec format error`
* **Symptom**: Invoking `.exe` files fails immediately with `Exec format error`.
* **Cause**: The kernel's `binfmt_misc` table lost the `WSLInterop` registration. Usual triggers,
  in rough order of how often they bite:
  1. **Another WSL distro started or was terminated.** `binfmt_misc` is **kernel-global**, shared
     by every distro in the VM -- see [cross-distro.md](cross-distro.md) section 4. This is the
     dominant cause on a multi-distro machine and has no visible connection to the failure.
  2. `systemd-binfmt` was restarted or reloaded (e.g. a package installed a new handler).
  3. Container operations or systemd updates.
* **Fix** (works on any systemd-enabled WSL distro, and needs no interop):
  ```bash
  sudo systemctl restart systemd-binfmt
  ```
  This succeeds even with no `/etc/binfmt.d/` entry of your own, because WSL injects a generator
  drop-in at `/run/systemd/generator/systemd-binfmt.service.d/override.conf` that re-registers the
  handler explicitly. Adding your own `/etc/binfmt.d/WSLInterop.conf` is redundant.
* **Verify**:
  ```bash
  cat /proc/sys/fs/binfmt_misc/WSLInterop
  ```
  ```text
  enabled
  interpreter /init
  flags: P
  offset 0
  magic 4d5a
  ```
  > Expect `flags: P` -- WSL's own generator registers with `:P`. A handler you registered by
  > hand with `:PF` will show `flags: PF`. Both work; do not treat `P` as a broken registration.

> **The self-rescue paradox**: once `WSLInterop` is gone, `wsl.exe` is itself a Windows binary
> and cannot run -- you cannot repair interop *through* interop. Every recovery path must be
> local to the distro. For machines where a second distro is started and stopped routinely,
> automate recovery with the guard timer in [cross-distro.md](cross-distro.md) section 4.

---

### 1.3 Windows Program Hangs Indefinitely
* **Symptom**: Running a Windows command (like `cmd.exe`, `wsl.exe`, `powershell.exe`) in a non-interactive shell or script hangs forever without producing output.
* **Cause**: The `/init` interop bridge waits on standard input (stdin).
* **Fix**:
  Always redirect stdin with `< /dev/null`:
  ```bash
  "/mnt/c/Windows/System32/cmd.exe" /c "dir" < /dev/null
  ```

---

### 1.4 Spaces Between Output Characters (`U T F - 1 6 L E`)
* **Symptom**: Command output appears with spaces between characters:
  ```text
  M i c r o s o f t   W i n d o w s
  ```
* **Cause**: Certain Windows CLIs emit raw UTF-16 LE text with null bytes (`\0`) between ASCII characters.
* **Fix**:
  Strip carriage returns and null bytes via pipe:
  ```bash
  wsl.exe --status < /dev/null | tr -d '\r' | tr -d '\0'
  # Or use iconv:
  wsl.exe --status < /dev/null | iconv -f UTF-16LE -t UTF-8
  ```

---

### 1.5 `.ps1` Script Blocked: "Execution of scripts is disabled"
* **Symptom**:
  ```text
  File ... cannot be loaded because running scripts is disabled on this system.
  ```
* **Cause**: Windows PowerShell defaults to `Restricted` or `RemoteSigned` execution policy, and files on `\\wsl.localhost` carry an untrusted zone identifier.
* **Fix**:
  Pass `-NoProfile -ExecutionPolicy Bypass` to the PowerShell process:
  ```bash
  "/mnt/c/Program Files/PowerShell/7/pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "./script.ps1" < /dev/null
  ```
* **Related clutter**: the same zone marking is what leaves `*:Zone.Identifier`
  files scattered around after downloading into a Windows directory. They are
  NTFS alternate data streams surfaced as separate files by drvfs, harmless but
  noisy in `ls` and in `git status`. Look before deleting, then delete:
  ```bash
  find . -name "*:Zone.Identifier"            # list first
  find . -name "*:Zone.Identifier" -delete
  ```
  Only meaningful under `/mnt/*`; a WSL-native directory never has them.

---

### 1.6 Argument Mangling and Nested Quotes
* **Symptom**: Complex commands with nested quotes, `$variables`, or backslashes fail with syntax errors.
* **Defensive Practice**:
  1. Use **single quotes** in bash for inline PowerShell code:
     ```bash
     scripts/run-pwsh.sh -c 'Get-Process | Where-Object { $_.CPU -gt 10 }'
     ```
  2. For multi-line or complex logic, write a temporary `.ps1` file and execute via `-File`:
     ```bash
     cat << 'EOF' > /tmp/task.ps1
     $p = Get-Process
     $p | Select-Object -First 5
     EOF
     scripts/run-pwsh.sh -f /tmp/task.ps1
     ```

---

## 2. Gotchas Quick Reference

| Symptom | Likely Cause | Solution |
| :--- | :--- | :--- |
| `accept4 failed 110`, **some** sockets OK | Stale `WSL_INTEROP` socket | `export WSL_INTEROP=<one that probed OK>` |
| `accept4 failed 110`, **all** sockets fail | Windows-side interop listener is down | Start another distro, or `wsl --shutdown` from Windows |
| `Exec format error` | `WSLInterop` missing from the **global** `binfmt_misc` table -- usually another distro started/stopped | `sudo systemctl restart systemd-binfmt` (must be local; `wsl.exe` cannot run) |
| Windows tool writes to the wrong directory | WSL cwd inherited as UNC; `cmd.exe` silently fell back to `C:\Windows` | `cd /mnt/c` before invoking |
| Command hangs in script | Stdin waiting on interop bridge | Append `< /dev/null` |
| Output has spaces between letters | UTF-16 LE null bytes | Pipe to `tr -d '\r' \| tr -d '\0'` |
| `pwsh.exe: command not found` | Relying on interactive PATH / aliases | Use full path `/mnt/c/Program Files/PowerShell/7/pwsh.exe` |
| `reg query` child key not found | WOW64 32-bit registry redirection | Append `/reg:64` |
| `.reg` import results in garbled text | Saved as UTF-8 instead of UTF-16 | Save file as **UTF-16 LE with BOM** |
| Write fails with `Read-only file system` | `/mnt/c` mounted `ro` (hardening) | Modify via PowerShell interop, or `sudo mount -o remount,rw /mnt/c` |
