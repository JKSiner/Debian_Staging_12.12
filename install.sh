#!/usr/bin/env bash
set -euo pipefail

# NVIDIA Driver installer for Debian 12 (bookworm) via NVIDIA LOCAL repo
# Usage:
#   sudo bash install.sh                # uses default DRIVER_VER
#   sudo bash install.sh 580.105.08     # custom driver version
#
# Optional env:
#   FORCE_OPEN=1  -> install nvidia-open instead of nvidia-driver
#
# Notes:
# - Will blacklist nouveau and rebuild initramfs
# - Requires reboot
# - Designed for Debian 12

DRIVER_VER="${1:-580.105.08}"
FORCE_OPEN="${FORCE_OPEN:-0}"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run as root (use sudo)."
  exit 1
fi

if [[ ! -f /etc/os-release ]]; then
  echo "ERROR: /etc/os-release not found"
  exit 1
fi

. /etc/os-release
if [[ "${ID:-}" != "debian" ]]; then
  echo "ERROR: This script is intended for Debian (detected ID=${ID:-unknown})."
  exit 1
fi

# Debian 12 = bookworm
if [[ "${VERSION_CODENAME:-}" != "bookworm" ]]; then
  echo "WARNING: This script targets Debian 12 (bookworm). Detected: ${VERSION_CODENAME:-unknown}"
  echo "         It may still work, but URLs/repo package name are Debian12-specific."
fi

echo "==> Debian: ${PRETTY_NAME:-Debian}"
echo "==> Kernel: $(uname -r)"
echo "==> Target NVIDIA driver: ${DRIVER_VER}"
echo

echo "==> Installing prerequisites..."
apt update
apt install -y ca-certificates curl wget gnupg lsb-release \
              build-essential dkms "linux-headers-$(uname -r)" \
              pciutils

echo "==> Blacklisting nouveau..."
cat >/etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
update-initramfs -u

echo "==> Purging Debian NVIDIA/CUDA packages (if any)..."
apt purge -y 'nvidia-*' '*cuda*' || true
apt autoremove -y || true

DEB_NAME="nvidia-driver-local-repo-debian12-${DRIVER_VER}_amd64.deb"
URL="https://developer.download.nvidia.com/compute/nvidia-driver/${DRIVER_VER}/local_installers/${DEB_NAME}"

echo "==> Downloading NVIDIA local repo package..."
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"
echo "    ${URL}"
wget -q --show-progress "$URL" -O "$DEB_NAME"

echo "==> Installing NVIDIA local repo package..."
dpkg -i "$DEB_NAME"

REPO_DIR="/var/nvidia-driver-local-repo-debian12-${DRIVER_VER}"
KEYRING_SRC="$(ls -1 ${REPO_DIR}/nvidia-driver-*-keyring.gpg 2>/dev/null | head -n 1 || true)"
if [[ -z "${KEYRING_SRC}" ]]; then
  echo "ERROR: Keyring not found in ${REPO_DIR}"
  ls -la "${REPO_DIR}" || true
  exit 1
fi

echo "==> Installing repo keyring..."
cp -v "${KEYRING_SRC}" /usr/share/keyrings/

echo "==> apt update..."
apt update

install_proprietary() {
  echo "==> Installing proprietary driver packages..."
  apt install -y nvidia-driver nvidia-kernel-dkms
}

install_open() {
  echo "==> Installing OPEN kernel module driver packages..."
  apt install -y nvidia-open
}

if [[ "${FORCE_OPEN}" == "1" ]]; then
  install_open
else
  # Try proprietary first
  install_proprietary
fi

echo "==> Rebuilding initramfs..."
update-initramfs -u

echo "==> Attempting to load driver modules (no reboot yet)..."
systemctl stop nvidia-persistenced 2>/dev/null || true
modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null || true
modprobe nvidia 2>/dev/null || true
modprobe nvidia_uvm 2>/dev/null || true
modprobe nvidia_modeset 2>/dev/null || true
modprobe nvidia_drm 2>/dev/null || true

echo "==> Checking for 'open kernel modules required' hint..."
if dmesg | grep -qi "requires use of the NVIDIA open kernel modules"; then
  echo "!! Detected: GPU requires NVIDIA OPEN kernel modules."
  echo "==> Switching to nvidia-open..."
  apt purge -y nvidia-driver nvidia-kernel-dkms || true
  apt autoremove -y || true
  install_open
  update-initramfs -u
fi

echo "==> Cleanup..."
cd /
rm -rf "$TMPDIR"

echo
echo "============================================================"
echo "Installation finished."
echo "Next: reboot is required."
echo "  sudo reboot"
echo
echo "After reboot verify:"
echo "  nvidia-smi"
echo "  nvidia-smi -L"
echo "============================================================"
