#!/usr/bin/env bash
set -euo pipefail

# Debian 12 (bookworm): Docker + NVIDIA Container Toolkit (GPU v kontejnerech)
# Spusť: sudo bash install-docker-nvidia.sh

if [[ $EUID -ne 0 ]]; then
  echo "Spusť jako root (sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/6] Základní balíky..."
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings

echo "[2/6] Docker repo + instalace Dockeru..."
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

echo "[3/6] NVIDIA Container Toolkit repo..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit.gpg
chmod a+r /etc/apt/keyrings/nvidia-container-toolkit.gpg

curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list

echo "[4/6] Instalace NVIDIA Container Toolkit..."
apt-get update
apt-get install -y --no-install-recommends nvidia-container-toolkit

echo "[5/6] Konfigurace Docker runtime pro NVIDIA..."
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

echo "[6/6] Test..."
echo "- Host nvidia-smi:"
nvidia-smi || true

echo "- GPU v kontejneru:"
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi

echo "Hotovo."
echo "Volitelně: sudo usermod -aG docker <uzivatel> (pak odhlásit/přihlásit)."
