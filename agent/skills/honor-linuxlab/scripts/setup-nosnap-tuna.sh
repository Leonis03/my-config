#!/usr/bin/env bash
# setup-nosnap-tuna.sh -- Completely purge snapd, lock it with APT Pinning, switch to Tsinghua TUNA, and add Mozilla deb repo.
# Target: Ubuntu 24.04 (Noble) ARM64 inside Honor Linux Lab container.

set -euo pipefail

echo "=== 1. Checking Architecture ==="
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" != "arm64" ]; then
    echo "[WARN] Expected arm64, found: $ARCH"
fi

echo "=== 2. Purging snapd and Cleaning Directories ==="
sudo apt-get purge -y snapd || true
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /usr/lib/snapd "$HOME/snap" /etc/snapd

echo "=== 3. Setting APT Pinning (Negative Priority for snapd) ==="
sudo mkdir -p /etc/apt/preferences.d
sudo tee /etc/apt/preferences.d/nosnap.pref << 'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

echo "=== 4. Configuring Tsinghua University TUNA Mirror (ubuntu-ports) ==="
# Backup old configs
[ -f /etc/apt/sources.list ] && sudo cp /etc/apt/sources.list "/etc/apt/sources.list.bak_$(date +%s)"
[ -f /etc/apt/sources.list.d/ubuntu.sources ] && sudo cp /etc/apt/sources.list.d/ubuntu.sources "/etc/apt/sources.list.d/ubuntu.sources.bak_$(date +%s)"

# Write Tsinghua ubuntu-ports mirror
sudo tee /etc/apt/sources.list << 'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-security main restricted universe multiverse
EOF

# Disable default deb822 source file to prevent duplicate definitions
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    sudo mv /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.disabled
fi

echo "=== 5. Updating APT Index ==="
sudo apt-get update

echo "=== 6. Configuring Mozilla Official Native DEB Repository ==="
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null

sudo tee /etc/apt/sources.list.d/mozilla.list << 'EOF'
deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main
EOF

sudo tee /etc/apt/preferences.d/mozilla << 'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

sudo apt-get update

echo "=== 7. Verifying PulseAudio Service Integrity ==="
if ! which pulseaudio >/dev/null 2>&1; then
    echo "Reinstalling pulseaudio (without snapd)..."
    sudo apt-get install -y pulseaudio
fi

echo "=== Setup completed successfully! ==="
