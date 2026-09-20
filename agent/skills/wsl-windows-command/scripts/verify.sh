#!/usr/bin/env bash
# verify.sh - check the WSL "read-only /mnt" hardening is in effect.
#
# Confirms, on the current box:
#   1. /mnt/* drives are mounted read-only (ro)
#   2. WSL writes are blocked (EROFS)
#   3. even `sudo chmod` is blocked -> the gate is the mount, not permissions
#   4. interop still works (Windows programs are callable)
#   5. PowerShell can still operate Windows files, while WSL cannot delete them
#
# Safe & self-cleaning: the only files touched are a throwaway dir this script
# creates and deletes under the Windows TEMP folder. All other checks are reads
# or no-ops. Exit code is non-zero if any hardening check fails.
#
# ----------------------------------------------------------------------------
# SCOPE: this script is for the OPT-IN read-only hardening scenario ONLY.
#
# It is NOT a health check for this repo's default configuration. The default
# in wsl/setup/ mounts C/D/E read-WRITE on purpose -- `ro` was dropped because
# it is bypassed by the powershell() bridge in ~/.shell_wslfn anyway, so it
# never stopped an AI agent; it only made ordinary Windows-side commands fail
# with confusing EROFS errors. See wsl/setup/README.md step 1.2.
#
# On a default (rw) box this script is EXPECTED to report failures for checks
# 1, 2, 3 and 5. That is not a problem with the box -- it means the hardening
# is simply not in effect. Run this only where you deliberately enabled `ro`.
# ----------------------------------------------------------------------------
set -uo pipefail

case "${1:-}" in
  -h|--help)
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
esac

# Early advisory so a default (rw) box is not mistaken for a broken one.
if findmnt -n /mnt/c >/dev/null 2>&1 && \
   [[ ",$(findmnt -no OPTIONS /mnt/c)," != *",ro,"* ]]; then
  echo "NOTE: /mnt/c is mounted rw -- the read-only hardening is NOT configured here."
  echo "      That is this repo's DEFAULT. The failures below are expected; they do"
  echo "      not indicate a broken setup. See wsl/setup/README.md step 1.2."
  echo
fi

pass=0; fail=0
ok()   { echo "  [PASS] $*"; pass=$((pass+1)); }
bad()  { echo "  [FAIL] $*"; fail=$((fail+1)); }
info() { echo "  [info] $*"; }

# Locate PowerShell (prefer pwsh 7, fall back to Windows PowerShell).
PWSH=""
for c in "${PWSH_EXE_WSL:-}" \
         "/mnt/c/Program Files/PowerShell/7/pwsh.exe" \
         "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"; do
  [ -n "$c" ] && [ -x "$c" ] && { PWSH="$c"; break; }
done

ps_test() {  # ps_test <WindowsPath> -> prints "yes" / "no"
  "$PWSH" -NoProfile -Command "if (Test-Path -LiteralPath '$1') {'yes'} else {'no'}" 2>/dev/null | tr -d '\r'
}

echo "== 1. mount options (expect ro) =="
for d in /mnt/c /mnt/d /mnt/e /mnt/f; do
  findmnt -n "$d" >/dev/null 2>&1 || continue
  opts=$(findmnt -no OPTIONS "$d")
  if [[ ",$opts," == *",ro,"* ]]; then ok "$d is ro"; else bad "$d is NOT ro -> $opts"; fi
done

echo "== 2. WSL write blocked (expect EROFS) =="
wt="/mnt/c/Users/Public/.wsl_verify_$$"
if touch "$wt" 2>/dev/null; then bad "wrote $wt -> /mnt/c is WRITABLE"; rm -f "$wt" 2>/dev/null; else ok "touch blocked (Read-only file system)"; fi

echo "== 3. sudo chmod blocked (gate is the mount, not permissions) =="
hf="/mnt/c/Windows/System32/drivers/etc/hosts"
if ! sudo -n true 2>/dev/null; then
  info "passwordless sudo unavailable; skipping chmod test"
elif [ -e "$hf" ]; then
  m=$(stat -c %a "$hf")                       # set the SAME mode -> no-op even if it were writable
  if sudo -n chmod "$m" "$hf" 2>/dev/null; then bad "sudo chmod succeeded -> fs is writable"; else ok "sudo chmod blocked (EROFS)"; fi
else
  info "$hf not found; skipping chmod test"
fi

echo "== 4. interop works (Windows programs callable) =="
if [ -z "$PWSH" ]; then
  bad "no pwsh/powershell found under /mnt/c"
else
  out=$("$PWSH" -NoProfile -Command "'interop-ok'" 2>/dev/null | tr -d '\r')
  [ "$out" = "interop-ok" ] && ok "PowerShell interop works ($PWSH)" || bad "interop call failed"
fi

echo "== 5. PowerShell can operate Windows files; WSL cannot delete them =="
if [ -z "$PWSH" ]; then
  info "no PowerShell -> skipping round-trip"
else
  wdir=$("$PWSH" -NoProfile -Command '$p=Join-Path $env:TEMP ("wslverify_"+[guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $p -Force | Out-Null; $p' 2>/dev/null | tr -d '\r')
  if [ -z "$wdir" ] || [ "$(ps_test "$wdir")" != "yes" ]; then
    bad "could not create Windows temp dir via PowerShell"
  else
    info "created throwaway Windows dir: $wdir"
    udir=$(wslpath -u "$wdir" 2>/dev/null)
    rm -rf "$udir" 2>/dev/null                 # expect this to fail on a ro mount
    if [ "$(ps_test "$wdir")" = "yes" ]; then ok "WSL rm could NOT delete it"; else bad "WSL rm deleted it -> fs writable"; fi
    "$PWSH" -NoProfile -Command "Remove-Item -LiteralPath '$wdir' -Recurse -Force" 2>/dev/null
    if [ "$(ps_test "$wdir")" = "no" ]; then ok "PowerShell deleted the Windows dir"; else bad "PowerShell delete failed (leftover: $wdir)"; fi
  fi
fi

echo
echo "== summary: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
