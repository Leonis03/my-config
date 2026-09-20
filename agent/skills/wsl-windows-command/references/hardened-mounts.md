# Read-Only /mnt (Hardened WSL Setups)

> **This is an opt-in scenario, not a default.** Most WSL boxes mount Windows drives `rw`,
> and `scripts/verify.sh` is written to assert the hardened state -- on an ordinary `rw` box
> it will report failures, which means "hardening not enabled here", not "something is broken".
>
> Be aware of what `ro` does and does not buy you: it blocks accidents (a stray `rm -rf` with
> a wrong path), but it does **not** contain an AI agent, because any `powershell.exe` bridge
> writes to Windows through interop and bypasses the mount entirely. Treat it as a guard
> against slips, never as a security boundary.

In hardened WSL environments, Windows drives (`/mnt/c`, `/mnt/d`, etc.) are mounted **read-only (`ro`)** via `/etc/wsl.conf`:

```ini
[automount]
options = "metadata,uid=1000,gid=1000,umask=22,ro"
```

This prevents WSL processes, compromised scripts, or autonomous agents from accidentally or maliciously modifying Windows host files.

---

## 1. Symptoms and the EROFS Boundary

When `/mnt/c` is mounted `ro`:
* File write and delete attempts fail with:
  ```text
  touch: cannot touch '/mnt/c/...': Read-only file system
  rm: cannot remove '/mnt/c/...': Read-only file system
  ```
* Even `sudo rm` or `sudo chmod` fails with `EROFS` (`Read-only file system`).
* **Root Cause**: The barrier is at the Linux VFS **mount level**, not POSIX file permissions. Changing file permissions (`chmod`/`chown`) is physically blocked by the kernel.

---

## 2. Sanctioned Workflow: Modify via Windows Interop

The `ro` mount blocks direct Linux filesystem writes, but **WSL Interop to Windows processes is the sanctioned way to touch Windows files**.

Processes launched on the Windows side run under the Windows host user account and are **not** subject to WSL's mount flags:

```bash
# Delete files or folders via PowerShell:
"/mnt/c/Program Files/PowerShell/7/pwsh.exe" -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -LiteralPath 'C:\path\to\file.txt' -Force" < /dev/null

# Write content to a Windows file:
"/mnt/c/Program Files/PowerShell/7/pwsh.exe" -NoProfile -ExecutionPolicy Bypass -Command "Set-Content -Path 'C:\path\to\output.txt' -Value 'hello'" < /dev/null

# Copy files from WSL to Windows:
"/mnt/c/Program Files/PowerShell/7/pwsh.exe" -NoProfile -ExecutionPolicy Bypass -Command "Copy-Item -Path '\\wsl.localhost\Ubuntu\home\<user>\data.csv' -Destination 'C:\Users\<user>\Desktop\'" < /dev/null
```

> **Note**: Reading through `/mnt/c` still works perfectly and at full speed from Linux.

---

## 3. Temporary Read-Write Remount (Requires Root)

If a complex Linux tool or build script must output directly to `/mnt/c`:

```bash
# 1. Temporarily remount as read-write:
sudo mount -o remount,rw /mnt/c

# 2. Perform necessary operations...

# 3. Restore hardened read-only mount:
sudo mount -o remount,ro /mnt/c
```

Even if you forget to remount `ro`, the mount automatically reverts to `ro` on the next `wsl --shutdown` because `/etc/wsl.conf` specifies `options = "...,ro"`.

---

## 4. Automated Verification (`scripts/verify.sh`)

To confirm that your hardening is intact and that interop is working correctly, run the bundled verification script:

```bash
bash scripts/verify.sh
```

### What `verify.sh` checks:
1. All Windows drive mounts (`/mnt/c`, `/mnt/d`, etc.) report `ro` in `findmnt`.
2. Direct WSL write attempts are blocked with `EROFS`.
3. `sudo chmod` is blocked by the mount layer.
4. Windows PowerShell interop is functional and callable.
5. Round-trip test: Creates a temporary directory under Windows `%TEMP%` via PowerShell, proves WSL cannot delete it, and cleans it up via PowerShell.
