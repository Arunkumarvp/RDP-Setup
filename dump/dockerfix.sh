#!/usr/bin/env bash

set -e

echo "[*] Fixing VirtualBox on Kali Linux..."
echo "[*] This script must be run as root."

if [[ $EUID -ne 0 ]]; then
  echo "[!] Please run as root: sudo ./fix-virtualbox-kali.sh"
  exit 1
fi

echo "[*] Removing broken Docker repository (if present)..."
rm -f /etc/apt/sources.list.d/docker.list || true
sed -i '/download.docker.com/d' /etc/apt/sources.list || true

echo "[*] Ensuring correct Kali repository..."
cat > /etc/apt/sources.list <<EOF
deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
EOF

echo "[*] Cleaning APT cache..."
apt clean

echo "[*] Updating package lists..."
apt update --fix-missing

echo "[*] Fixing broken packages..."
apt --fix-broken install -y

echo "[*] Installing required build tools and headers..."
apt install -y \
  dkms \
  build-essential \
  linux-headers-$(uname -r) || apt install -y linux-headers-amd64

echo "[*] Installing VirtualBox dependencies..."
apt install -y \
  libqt6help6 \
  libqt6printsupport6 \
  libqt6statemachine6 \
  libqt6xml6 \
  libvpx9 \
  libxml2 \
  libsdl-ttf2.0-0

echo "[*] Reinstalling VirtualBox..."
apt install --reinstall -y virtualbox virtualbox-dkms

echo "[*] Rebuilding VirtualBox kernel modules..."
/sbin/vboxconfig

echo "[*] Updating linker cache..."
ldconfig

echo "[*] Checking kernel modules..."
lsmod | grep vbox || echo "[!] vbox modules not loaded yet (reboot may be required)"

echo "[✓] Fix completed."
echo "[✓] Reboot recommended."
