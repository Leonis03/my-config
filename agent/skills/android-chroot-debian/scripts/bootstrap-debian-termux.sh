#!/data/data/com.termux/files/usr/bin/bash
# bootstrap-debian-termux.sh -- Bootstrap minimal Debian Trixie (arm64) inside Termux
#
# Usage (run inside Termux):
#   bash bootstrap-debian-termux.sh

set -Eeuo pipefail

ROOT="${DEBIAN_ROOT:-$HOME/debian-trixie-minbase-install}"
SUITE="trixie"
MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
KEYRING_DIR="$HOME/.cache/debian-keyrings"

echo "[1/6] Installing bootstrap prerequisites in Termux..."
pkg install -y debootstrap gnupg debian-archive-keyring 2>/dev/null || pkg install -y debootstrap gnupg

echo "[2/6] Preparing Debian archive keyrings..."
mkdir -p "$KEYRING_DIR"
# Try system keyring first, or fetch Debian archive key if missing
if [ -f "$PREFIX/etc/apt/trusted.gpg.d/debian-archive-keyring.gpg" ]; then
    KEYRING="$PREFIX/etc/apt/trusted.gpg.d/debian-archive-keyring.gpg"
elif [ -f "$PREFIX/share/keyrings/debian-archive-keyring.gpg" ]; then
    KEYRING="$PREFIX/share/keyrings/debian-archive-keyring.gpg"
else
    KEYRING="$KEYRING_DIR/debian-archive-keyring.gpg"
    if [ ! -f "$KEYRING" ]; then
        curl -fsSL "https://ftp-master.debian.org/keys/archive-key-13.asc" -o "$KEYRING_DIR/archive-key-13.asc" || true
        if [ -f "$KEYRING_DIR/archive-key-13.asc" ]; then
            gpg --dearmor < "$KEYRING_DIR/archive-key-13.asc" > "$KEYRING"
        fi
    fi
fi

KEYRING_ARG=""
if [ -f "$KEYRING" ]; then
    KEYRING_ARG="--keyring=$KEYRING"
fi

echo "[3/6] Running debootstrap minbase (arm64) from Tsinghua mirror..."
mkdir -p "$ROOT"
debootstrap --verbose --arch=arm64 --variant=minbase $KEYRING_ARG "$SUITE" "$ROOT" "$MIRROR"

echo "[4/6] Configuring DNS resolution and network hosts..."
mkdir -p "$ROOT/etc"
# Inherit primary DNS from Android system properties
DNS_IP="$(getprop net.dns1 2>/dev/null || true)"
if [ -z "$DNS_IP" ]; then
    DNS_IP="1.1.1.1"
fi
printf "nameserver %s\nnameserver 8.8.8.8\n" "$DNS_IP" > "$ROOT/etc/resolv.conf"
printf "127.0.0.1 localhost\n::1 localhost\n" > "$ROOT/etc/hosts"

echo "[5/6] Setting standard file permissions..."
chmod 1777 "$ROOT/tmp"
chmod 644 "$ROOT/etc/resolv.conf" "$ROOT/etc/hosts"

echo "[6/6] Writing Tsinghua mirror APT sources..."
cat << 'EOF' > "$ROOT/etc/apt/sources.list"
deb https://mirrors.tuna.tsinghua.edu.cn/debian trixie main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian trixie-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security trixie-security main contrib non-free non-free-firmware
EOF

echo ""
echo "=== Debian bootstrap completed successfully ==="
echo "Target directory: $ROOT"
echo "You can now deploy debian-chroot-launcher.sh to \$HOME/.local/bin/debian and launch Debian."
