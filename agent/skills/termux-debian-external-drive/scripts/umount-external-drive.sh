#!/usr/bin/env bash
# umount-external-drive.sh -- Safely sync and unmount external USB storage in Termux Debian
#
# Usage:
#   bash umount-external-drive.sh [mountpoint] [--lazy]
#
# Default mountpoint: /mnt/external

set -Eeuo pipefail

MOUNT_POINT="${1:-/mnt/external}"
LAZY_MODE=0

if [[ "${2:-}" == "--lazy" || "${1:-}" == "--lazy" ]]; then
    LAZY_MODE=1
    if [[ "${1:-}" == "--lazy" ]]; then
        MOUNT_POINT="/mnt/external"
    fi
fi

info() {
    printf '[+] %s\n' "$*"
}

warn() {
    printf '[!] %s\n' "$*" >&2
}

err() {
    printf '[-] %s\n' "$*" >&2
    exit 1
}

if [[ "$(id -u)" -ne 0 ]]; then
    err "This script must be run as root inside Debian chroot."
fi

if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    warn "Target '$MOUNT_POINT' is not an active mountpoint."
    exit 0
fi

# 1. Flush pending write buffers to prevent data loss on NTFS/exFAT
info "Flushing cached write buffers (sync)..."
sync -f "$MOUNT_POINT" 2>/dev/null || sync

# 2. Check for processes using the mountpoint
BUSY_PROCS=0
if command -v fuser >/dev/null 2>&1; then
    if fuser -m "$MOUNT_POINT" >/dev/null 2>&1; then
        BUSY_PROCS=1
        warn "Active processes are accessing '$MOUNT_POINT':"
        fuser -v -m "$MOUNT_POINT" || true
    fi
elif command -v lsof >/dev/null 2>&1; then
    if lsof +D "$MOUNT_POINT" >/dev/null 2>&1; then
        BUSY_PROCS=1
        warn "Active processes found holding files in '$MOUNT_POINT':"
        lsof +D "$MOUNT_POINT" || true
    fi
fi

if [[ "$BUSY_PROCS" -eq 1 ]]; then
    if [[ "$LAZY_MODE" -eq 1 ]]; then
        warn "Mountpoint is busy; proceeding with lazy unmount (-l)..."
        umount -l "$MOUNT_POINT"
        info "Lazy unmount issued. Mountpoint detached from filesystem tree."
        exit 0
    else
        err "Target is busy. Close applications using the drive or pass --lazy to detach."
    fi
fi

# 3. Standard unmount
umount "$MOUNT_POINT"
sync
info "Successfully unmounted '$MOUNT_POINT'."
info "It is now safe to unplug the drive or unmount from Android notification bar."
