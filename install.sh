#!/usr/bin/env bash
set -euo pipefail

# Debian 12 + NVIDIA (CUDA deb_network repo) driver installer
# Based on NVIDIA CUDA "deb (network)" flow: cuda-keyring -> apt update -> install driver
#
# Usage:
#   sudo bash install.sh
#   sudo DRIVER_FLAVOR=open bash install.sh
#   sudo DRIVER_FLAVOR=proprietary bash install.sh
#   sudo PIN_VERSION=580.105.08-1 DRIVER_FLAVOR=open bash install.sh
#
# Env:
#   DRIVER_FLAVOR=open|proprietary   (default: open)
#   PIN_VERSION=580.105.08-1         (optional exact Debian package version to pin)
#   DISABLE_NOUVEAU=1                (optional: blacklist nouveau + update-initramfs)
#   REBOOT_AFTER=1                   (optional: reboot at end)

DRIVER_FLAVOR="${DRIVER_FLAVOR:-open}"   # open recommended for Ada DC in your case
PIN_VERSION="${PIN_VERSION:-}"           # e.g. 580.105.08-1 (optional)
DISABLE_NOUVEAU="${DISABLE_NOUVEAU:-0}"
REBOOT_AFTER="${REBOOT_AFTER:-0}"

log(){ echo -e "\n==> $*\n"; }

require_root(){
  [[ "${EUID}" -eq 0 ]] || { echo "Run as root: sudo bash install.sh"; exit 1; }
}

check_debian12(){
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || { echo "This script is for Debian. Detected: ${ID:-unknown}"; exit 1; }
  [[ "${VERSION_ID:-}" == "12" ]] || { echo "This script targets Debian 12. Detected: ${VERSION_ID:-unknown}"; exit 1; }
}

install_prereqs(){
  log "Installing prerequisites..."
  apt-get update -y
  apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release \
    pciutils \
    dkms build-essential "linux-headers-$(uname -r)"
}

maybe_disable_nouveau(){
  if [[ "${DISABLE_NOUVEAU}" == "1" ]]; then
    log "Blacklisting nouveau + updating initramfs..."
    cat >/etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u
  fi
}

install_cuda_keyring(){
  log "Installing NVIDIA CUDA APT repo keyring (deb_network)..."
  local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb"
  wget -q --show-progress "${keyring_url}" -O /tmp/cuda-keyring.deb
  dpkg -i /tmp/cuda-keyring.deb
  rm -f /tmp/cuda-keyring.deb
  apt-get update -y
}

purge_old_debian_driver(){
  log "Purging Debian NVIDIA/CUDA packages (if any)..."
  apt-get purge -y 'nvidia-*' '*cuda*' || true
  apt-get autoremove -y || true
}

install_driver_open(){
  log "Installing NVIDIA OPEN kernel modules driver..."
  if [[ -n "${PIN_VERSION}" ]]; then
    # Pin exact version (must exist in repo)
    apt-get install -y "nvidia-open=${PIN_VERSION}" "nvidia-smi=${PIN_VERSION}" || \
      apt-get install -y "nvidia-open=${PIN_VERSION}" || true
  else
    apt-get install -y nvidia-open
  fi
}

install_driver_proprietary(){
  log "Installing NVIDIA proprietary kernel modules driver (cuda-drivers)..."
  if [[ -n "${PIN_VERSION}" ]]; then
    apt-get install -y "cuda-drivers=${PIN_VERSION}" || true
  else
    apt-get install -y cuda-drivers
  fi
}

post_steps(){
  log "Rebuilding initramfs..."
  update-initramfs -u

  log "Trying to load modules (best effort, reboot still recommended)..."
  systemctl stop nvidia-persistenced 2>/dev/null || true
  modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null || true
  modprobe nvidia 2>/dev/null || true
  modprobe nvidia_uvm 2>/dev/null || true
  modprobe nvidia_modeset 2>/dev/null || true
  modprobe nvidia_drm 2>/dev/null || true

  log "Driver version (if available):"
  modinfo nvidia 2>/dev/null | egrep -i '^(version:|filename:)' || true

  log "nvidia-smi (may require reboot):"
  nvidia-smi || true

  echo
  echo "============================================================"
  echo "DONE. Recommended next step:"
  echo "  sudo reboot"
  echo
  echo "After reboot verify:"
  echo "  nvidia-smi"
  echo "  nvidia-smi -L"
  echo "============================================================"
  echo

  if [[ "${REBOOT_AFTER}" == "1" ]]; then
    log "Rebooting..."
    reboot
  fi
}

main(){
  require_root
  check_debian12
  install_prereqs
  maybe_disable_nouveau
  purge_old_debian_driver
  install_cuda_keyring

  case "${DRIVER_FLAVOR}" in
    open) install_driver_open ;;
    proprietary) install_driver_proprietary ;;
    *) echo "Invalid DRIVER_FLAVOR=${DRIVER_FLAVOR} (use: open|proprietary)"; exit 1 ;;
  esac

  post_steps
}

main "$@"
