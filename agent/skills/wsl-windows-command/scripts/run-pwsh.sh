#!/usr/bin/env bash
# Run Windows PowerShell from WSL, quote-safely, with execution policy bypassed and interop self-healing.
#
# Usage:
#   run-pwsh.sh -c '<powershell command>'      # run an inline command
#   run-pwsh.sh -f <script.ps1> [args...]      # run a .ps1 file (path may be WSL or Windows)
#
# Prefers PowerShell 7 (pwsh.exe), falls back to Windows PowerShell.
# Override the interpreter with PWSH_EXE_WSL=/mnt/c/.../pwsh.exe
set -euo pipefail

# 1. Self-heal WSL_INTEROP against "UtilAcceptVsock ... accept4 failed 110".
#
# A socket FILE existing proves nothing -- a socket can be present and dead. So probe by
# actually running something, and only replace the inherited WSL_INTEROP if it fails. The
# naive "always prefer /run/WSL/2_interop" approach is actively harmful: it overwrites a
# working socket with an untested one.
_interop_works() {
  WSL_INTEROP="$1" /mnt/c/Windows/System32/cmd.exe /c "echo OK" < /dev/null 2>/dev/null \
    | tr -d '\0\r' | grep -q '^OK'
}

if [ -z "${WSL_INTEROP:-}" ] || ! _interop_works "$WSL_INTEROP"; then
  _healed=""
  for candidate in /run/WSL/*_interop; do
    [ -S "$candidate" ] || continue
    if _interop_works "$candidate"; then
      export WSL_INTEROP="$candidate"
      _healed="yes"
      break
    fi
  done
  if [ -z "$_healed" ]; then
    # Every socket failed the same way: this is NOT a stale socket. The Windows-side
    # interop listener is down and no WSL_INTEROP value will help.
    echo "run-pwsh.sh: all interop sockets failed; the Windows-side listener appears down." >&2
    echo "  Try starting another WSL distro, or 'wsl --shutdown' from Windows (kills ALL distros)." >&2
    echo "  See references/troubleshooting.md section 1.1." >&2
    exit 1
  fi
fi

# 2. Locate PowerShell (prefer pwsh 7, fall back to Windows PowerShell)
PWSH=""
for c in \
  "${PWSH_EXE_WSL:-}" \
  "/mnt/c/Program Files/PowerShell/7/pwsh.exe" \
  "/mnt/c/Program Files/PowerShell/7-preview/pwsh-preview.exe" \
  "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"; do
  [ -n "$c" ] && [ -x "$c" ] && { PWSH="$c"; break; }
done
[ -z "$PWSH" ] && { echo "run-pwsh.sh: no pwsh.exe/powershell.exe found under /mnt/c" >&2; exit 127; }

# 3. Execute with execution policy bypassed and stdin detached (< /dev/null)
case "${1:-}" in
  -c)
    [ $# -ge 2 ] || { echo "run-pwsh.sh: -c needs a command" >&2; exit 2; }
    exec "$PWSH" -NoProfile -ExecutionPolicy Bypass -Command "$2" < /dev/null
    ;;
  -f)
    [ $# -ge 2 ] || { echo "run-pwsh.sh: -f needs a script path" >&2; exit 2; }
    script="$2"; shift 2
    # Convert a WSL path to a Windows path; leave an existing Windows path alone.
    case "$script" in
      /*) win="$(wslpath -w "$script")" ;;
      *)  win="$script" ;;
    esac
    exec "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$win" "$@" < /dev/null
    ;;
  *)
    echo "Usage: run-pwsh.sh -c '<command>' | -f <script.ps1> [args...]" >&2
    exit 2
    ;;
esac
