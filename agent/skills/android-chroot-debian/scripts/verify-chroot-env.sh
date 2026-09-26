#!/usr/bin/env bash
# verify-chroot-env.sh -- Diagnostics script to run inside Debian chroot container
#
# Validates UID, Capabilities, SELinux, /proc/self/exe, PTY, and host mount bridges.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  [${GREEN}PASS${NC}] $1"; }
fail() { echo -e "  [${RED}FAIL${NC}] $1"; }
warn() { echo -e "  [${YELLOW}WARN${NC}] $1"; }
info() { echo -e "  [${BLUE}INFO${NC}] $1"; }

echo "=================================================="
echo "    Debian chroot (Android) Diagnostic Suite      "
echo "=================================================="

# 1. Credentials & Kernel
echo -e "\n1. Kernel and Identity Credentials:"
info "Kernel: $(uname -s -r -m)"
current_uid=$(id -u)
current_gid=$(id -g)
if [ "$current_uid" -eq 0 ] && [ "$current_gid" -eq 0 ]; then
    pass "Process runs as true root (uid=0 gid=0)"
else
    fail "Process is not root (uid=$current_uid gid=$current_gid)"
fi

# 2. SELinux & Capabilities
echo -e "\n2. Security Sandbox & Capabilities:"
if [ -f /proc/self/attr/current ]; then
    domain=$(cat /proc/self/attr/current)
    if [[ "$domain" == *"magisk"* ]] || [[ "$domain" == *"su"* ]]; then
        pass "SELinux domain: $domain (unrestricted root domain)"
    else
        warn "SELinux domain: $domain (may be constrained by Android SELinux policy)"
    fi
else
    warn "/proc/self/attr/current unavailable"
fi

if [ -f /proc/self/status ]; then
    cap_eff=$(grep -E '^CapEff:' /proc/self/status | awk '{print $2}')
    info "CapEff: $cap_eff"
    if [ "$cap_eff" = "000001ffffffffff" ]; then
        pass "All 41 Linux Capabilities are fully enabled"
    else
        warn "Capabilities set is reduced ($cap_eff)"
    fi
fi

# 3. Procfs & Runtime Self-Inspection
echo -e "\n3. Runtime Self-Inspection (/proc):"
if [ -d /proc ]; then
    exe_target=$(readlink /proc/self/exe 2>/dev/null || echo "FAILED")
    if [ "$exe_target" != "FAILED" ]; then
        pass "/proc/self/exe resolves correctly: $exe_target"
    else
        fail "/proc/self/exe cannot be resolved (breaks Go/Rust/Node CLI runtimes)"
    fi
else
    fail "/proc filesystem is not mounted"
fi

# 4. PTY & Terminal Emulation
echo -e "\n4. UNIX 98 PTY Subsystem:"
if [ -e /dev/ptmx ]; then
    if [ -L /dev/ptmx ]; then
        target=$(readlink /dev/ptmx)
        pass "/dev/ptmx is symlink -> $target"
    else
        pass "/dev/ptmx character device exists"
    fi
else
    fail "/dev/ptmx missing"
fi

if mountpoint -q /dev/pts 2>/dev/null || grep -qs '/dev/pts devpts' /proc/mounts; then
    pass "/dev/pts (devpts filesystem) is mounted"
else
    fail "/dev/pts is NOT mounted (causes 'open /dev/ptmx: no such device')"
fi

current_tty=$(tty 2>/dev/null || echo "not a tty")
info "Current terminal device: $current_tty"

# 5. Android Host Access Bridge
echo -e "\n5. Android Host Storage & Partitions:"
for check_path in /android /android/system /android/data /android/storage/emulated/0; do
    if [ -d "$check_path" ]; then
        pass "Host path accessible: $check_path"
    else
        warn "Host path not mounted: $check_path"
    fi
done

echo -e "\n=================================================="
echo "Diagnostics complete."
