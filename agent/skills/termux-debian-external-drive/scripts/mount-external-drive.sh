#!/usr/bin/env bash
# mount-external-drive.sh -- Detect and mount external USB storage inside Termux Debian chroot
#
# Usage:
#   bash mount-external-drive.sh [mountpoint]
#
# Default mountpoint: /mnt/external

set -Eeuo pipefail

MOUNT_POINT="${1:-/mnt/external}"

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

# 1. Ensure root inside Debian
if [[ "$(id -u)" -ne 0 ]]; then
    err "This script must be run as root inside Debian chroot."
fi

# 2. Check if already mounted
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    info "Target '$MOUNT_POINT' is already a mountpoint."
    exit 0
fi

# 3. Detect external drive in current Debian mount namespace (/android/mnt/media_rw)
DETECTED_SOURCE=""
if [[ -d /android/mnt/media_rw ]]; then
    for d in /android/mnt/media_rw/*; do
        if [[ -d "$d" && "$d" != "/android/mnt/media_rw/*" ]]; then
            uuid="$(basename "$d")"
            # Ignore Android placeholder dirs
            if [[ "$uuid" =~ ^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$ ]] || [[ "$uuid" =~ ^[0-9A-Fa-f]{16}$ ]]; then
                DETECTED_SOURCE="$d"
                info "Found active Android media mount in current namespace: $d (UUID: $uuid)"
                break
            fi
        fi
    done
fi

# 4. If not found in current namespace, check host Android namespace via nsenter (hotplug scenario)
if [[ -z "$DETECTED_SOURCE" ]]; then
    if command -v nsenter >/dev/null 2>&1; then
        HOST_MEDIA="$(nsenter -t 1 -m /system/bin/mount 2>/dev/null | grep -E '/mnt/media_rw/' | awk '{print $3}' | head -n 1 || true)"
        if [[ -n "$HOST_MEDIA" ]]; then
            info "Detected external drive in Android host namespace: $HOST_MEDIA"
            # Expose host mount into Debian chroot
            target_subpath="/android${HOST_MEDIA}"
            mkdir -p "$target_subpath"
            if mount --bind "$target_subpath" "$MOUNT_POINT" 2>/dev/null; then
                DETECTED_SOURCE="$target_subpath"
            else
                # Bind directly using host nsenter if subpath is not mounted in chroot
                CHROOT_HOST_PATH="${DEBIAN_CHROOT_HOST_DIR:-}"
                if [[ -z "$CHROOT_HOST_PATH" ]]; then
                    CHROOT_HOST_PATH="$(nsenter -t 1 -m /system/bin/find /data/data/com.termux/files -maxdepth 2 -name "*debian*" -type d 2>/dev/null | head -n 1 || true)"
                fi
                if [[ -n "$CHROOT_HOST_PATH" ]] && nsenter -t 1 -m /system/bin/test -d "$CHROOT_HOST_PATH"; then
                    info "Mounting from host namespace into chroot path ($CHROOT_HOST_PATH)..."
                    nsenter -t 1 -m /system/bin/mount --bind "$HOST_MEDIA" "${CHROOT_HOST_PATH}${MOUNT_POINT}"
                    DETECTED_SOURCE="$HOST_MEDIA"
                fi
            fi
        fi
    fi
fi

# 5. Check fallback directly on block devices if vold is present
if [[ -z "$DETECTED_SOURCE" && -d /android/dev/block/vold ]]; then
    PUBLIC_BLOCK="$(ls /android/dev/block/vold/public:* 2>/dev/null | head -n 1 || true)"
    if [[ -n "$PUBLIC_BLOCK" ]]; then
        info "Found public storage block device: $PUBLIC_BLOCK"
        # Check if vold already mounted it
        VOLD_MOUNT="$(grep "$PUBLIC_BLOCK" /proc/mounts | awk '{print $2}' | head -n 1 || true)"
        if [[ -n "$VOLD_MOUNT" ]]; then
            DETECTED_SOURCE="$VOLD_MOUNT"
        fi
    fi
fi

[[ -n "$DETECTED_SOURCE" ]] || err "No external USB drive detected. Check OTG cable, power supply, and Android notification."

# 6. Bind-mount to target mountpoint if not already performed
mkdir -p "$MOUNT_POINT"
if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    mount --bind "$DETECTED_SOURCE" "$MOUNT_POINT"
fi

info "Successfully mounted '$DETECTED_SOURCE' to '$MOUNT_POINT'."
info "Mount summary:"
df -h "$MOUNT_POINT"
