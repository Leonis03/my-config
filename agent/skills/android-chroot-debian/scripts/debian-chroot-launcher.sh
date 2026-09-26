#!/data/data/com.termux/files/usr/bin/bash
# debian-chroot-launcher.sh -- Root Debian chroot wrapper for Android (Termux)
#
# Production script deployed to: $HOME/.local/bin/debian
# Supports:
#   debian          # Enter interactive Debian root shell with private mount namespace
#   debian --check  # Run comprehensive non-interactive health check

set -Eeuo pipefail

ROOT="${DEBIAN_ROOT:-$HOME/debian-trixie-minbase-install}"
MODE="${1:-}"

# If not already running as root inside private namespace, elevate via su and unshare -m
if [[ "${1:-}" != "--root" ]]; then
    case "$MODE" in
        ""|--check) ;;
        *) printf 'Usage: debian [--check]\n' >&2; exit 2 ;;
    esac
    ROOT_SCRIPT="$HOME/.local/bin/debian"
    if [[ -n "$MODE" ]]; then
        exec /data/data/com.termux/files/usr/bin/su -c "/system/bin/unshare -m '$ROOT_SCRIPT' --root '$MODE'"
    else
        exec /data/data/com.termux/files/usr/bin/su -c "/system/bin/unshare -m '$ROOT_SCRIPT' --root"
    fi
fi
shift
MODE="${1:-}"

# Keep mount changes private to this invocation's mount namespace
/system/bin/mount -o rprivate none /
/system/bin/mkdir -p "$ROOT/android"

# Expose the Android host root at /android. Android's mount command does not
# recursively bind its mount tree, so map each host mountpoint below / separately.
/system/bin/mount -t proc proc "$ROOT/proc"
/system/bin/mount / "$ROOT/android"
declare -A SEEN_MOUNTS=()
while IFS=' ' read -r _ target _; do
    case "$target" in
        /|"$ROOT"|"$ROOT"/*|/data/*|/debug_ramdisk/.magisk/preinit|*\\*) continue ;;
    esac
    if [[ ${SEEN_MOUNTS[$target]+yes} ]]; then
        continue
    fi
    SEEN_MOUNTS[$target]=1
    if [[ "$target" == "/data" ]]; then
        destination="$ROOT/android/data"
    else
        destination="$ROOT/android$target"
    fi
    [[ -d "$target" && -d "$destination" ]] || continue
    /system/bin/mount "$target" "$destination" 2>/dev/null || \
        printf 'Note: could not expose Android mount %s\n' "$target" >&2
done < /proc/mounts

# Give Debian its own /dev and PTY instance on tmpfs without changing Android's /dev
/system/bin/mount -t tmpfs -o mode=755,nosuid,nodev tmpfs "$ROOT/dev"
/system/bin/mkdir -p "$ROOT/dev/pts" "$ROOT/dev/shm"
for node in null zero full random urandom tty console; do
    if [[ -e "/dev/$node" ]]; then
        /system/bin/ln -s "/android/dev/$node" "$ROOT/dev/$node"
    fi
done
/system/bin/ln -s pts/ptmx "$ROOT/dev/ptmx"
/system/bin/ln -s /proc/self/fd "$ROOT/dev/fd"
/system/bin/ln -s /proc/self/fd/0 "$ROOT/dev/stdin"
/system/bin/ln -s /proc/self/fd/1 "$ROOT/dev/stdout"
/system/bin/ln -s /proc/self/fd/2 "$ROOT/dev/stderr"
/system/bin/mount -t devpts -o newinstance,gid=5,mode=620,ptmxmode=666 devpts "$ROOT/dev/pts"
/system/bin/mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs "$ROOT/dev/shm"

if [[ "$MODE" == "--check" ]]; then
    exec /system/bin/chroot "$ROOT" /usr/bin/env -i \
        HOME=/root \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        TERM="${TERM:-xterm-256color}" \
        /bin/bash -c '
            set -e
            printf "Debian UID: "
            /usr/bin/id -u
            test -e /proc/self/exe && echo "proc: OK"
            test -d /android/system && echo "Android /system: OK"
            test -e /android/data/data/com.termux/files/home && echo "Android /data: OK"
            test -e /android/dev/null && echo "Android /dev: OK"
            printf x >/dev/null && echo "dev nodes: OK"
            exec 3<>/dev/ptmx
            echo "PTY: OK"
        '
fi

printf 'Entering Debian as root; Android host filesystem is available at /android.\n'
exec /system/bin/chroot "$ROOT" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM="${TERM:-xterm-256color}" \
    /bin/bash -l
