---
name: compress-wsl-space
description: Safely estimate and compact local WSL2 ext4.vhdx disk usage on Windows. Use when the user asks to check how much WSL disk space can be reclaimed, shrink or compress WSL storage, run fstrim plus Optimize-VHD, troubleshoot WSL VHDX size growth, or document the local WSL compaction workflow.
---

# Compress WSL Space

## Overview

Use this skill to reduce Windows-side WSL2 `ext4.vhdx` size after files were deleted inside Linux. The verified local workflow is:

1. Measure the host VHDX file size and Linux `df` usage.
2. Run `fstrim` inside the distro to mark free ext4 blocks.
3. Stop WSL so the VHDX is detached.
4. Run `Optimize-VHD -Mode Full`.
5. Restart the distro and verify `whoami` plus `df -h /`.

Do not enable WSL sparse VHD as a default fix. Treat sparse mode as experimental unless the user explicitly asks for it and accepts the risk.

## Quick Start

Use the bundled script:

```powershell
# Estimate only
powershell -NoProfile -ExecutionPolicy Bypass -File .\compress-wsl-space\scripts\compact-wsl-vhdx.ps1 -Distro Ubuntu

# Execute compaction
powershell -NoProfile -ExecutionPolicy Bypass -File .\compress-wsl-space\scripts\compact-wsl-vhdx.ps1 -Distro Ubuntu -Compact

# If active WSL sessions keep the VHDX attached, allow stopping WSLService
powershell -NoProfile -ExecutionPolicy Bypass -File .\compress-wsl-space\scripts\compact-wsl-vhdx.ps1 -Distro Ubuntu -Compact -ForceStopService
```

For this machine, the current Ubuntu VHDX has historically lived at:

```text
D:\WSL\UbuntuFresh\ext4.vhdx
```

Prefer registry discovery over hard-coding this path.

## Workflow

### Estimate

Read the distro path from:

```powershell
HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss
```

Then compare:

- Windows host file size: `Get-Item <BasePath>\ext4.vhdx`
- Linux used bytes: `wsl -d <Distro> -- bash -lc "df -B1 --output=used / | tail -n 1 | tr -d ' '"`

The rough reclaim estimate is:

```text
VHDX file size - Linux used bytes
```

Expect the final VHDX to be larger than Linux used bytes because VHDX and ext4 metadata still need space.

### Compact

Only compact when:

- The user explicitly asks to compress or compact.
- The shell is elevated as Administrator.
- `Optimize-VHD` is available from the Hyper-V module.
- The VHDX can be detached.

Run:

```powershell
wsl -d Ubuntu -- bash -lc "df -h / /home; sudo fstrim -av"
wsl --shutdown
Optimize-VHD -Path "D:\WSL\UbuntuFresh\ext4.vhdx" -Mode Full
```

`wsl --terminate <Distro>` is **not** a substitute for `wsl --shutdown` here. Verified on WSL 2.7.14.0: if another distro holds a bind mount of this one under `/mnt/wsl` (see [cross-distro.md](../wsl-windows-command/references/cross-distro.md) section 2), `--terminate` leaves the filesystem mounted and writable from that distro while `wsl -l -v` reports `Stopped`. The VHDX stays attached. Only dropping the last mount, or `--shutdown`, releases it.

If `wsl --shutdown` or `wsl --terminate <Distro>` leaves the VHDX attached, inspect running processes. If the user has requested compression and accepts disconnecting active WSL sessions, stop `WSLService`:

```powershell
Stop-Service -Name WSLService -Force
```

Then re-check:

```powershell
Get-VHD -Path "D:\WSL\UbuntuFresh\ext4.vhdx" | Select-Object Path,FileSize,Attached
```

Proceed only when `Attached` is `False`.

### Verify

After compaction, always verify:

```powershell
Get-Item "D:\WSL\UbuntuFresh\ext4.vhdx" | Select-Object FullName,Length,LastWriteTime
wsl -d Ubuntu -- whoami
wsl -d Ubuntu -- bash -lc "df -h / /home"
```

Report:

- Original VHDX size.
- Final VHDX size.
- Reclaimed GiB.
- Whether the distro restarted.
- Any forced WSLService stop.

## Failure Handling

- If WSL cannot see the distro from the current user context, do not unregister or import anything. Report that exact estimation needs the registered distro context; host-side VHDX size can still be read if the file path is known.
- If `Optimize-VHD` is unavailable, tell the user Hyper-V PowerShell is missing or use the official `diskpart compact vdisk` fallback.
- If the VHDX remains attached, do not run `Optimize-VHD`. Stop active WSL sessions first.
- If `fstrim` succeeds but compaction is blocked, it is safe to retry compaction later after WSL is fully stopped.
