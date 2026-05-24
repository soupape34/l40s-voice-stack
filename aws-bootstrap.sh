#!/usr/bin/env bash
# g6e.xlarge: 32 Go RAM — Gemma 26B mmap ~50 Go. Swap sur NVMe éphémère AWS.
set -euo pipefail

SWAP="${SWAP_PATH:-/opt/dlami/nvme/swapfile}"
SWAP_SIZE="${SWAP_SIZE:-64G}"

if swapon --show | grep -q swap; then
  echo "Swap déjà actif:"
  swapon --show
  exit 0
fi

if [[ -d /opt/dlami/nvme ]]; then
  SWAP="/opt/dlami/nvme/swapfile"
  echo "NVMe éphémère détecté → swap sur $SWAP"
else
  SWAP="/swapfile"
  echo "Pas de NVMe éphémère → swap sur $SWAP"
fi

sudo fallocate -l "$SWAP_SIZE" "$SWAP" 2>/dev/null || \
  sudo dd if=/dev/zero of="$SWAP" bs=1M count=65536 status=progress
sudo chmod 600 "$SWAP"
sudo mkswap "$SWAP"
sudo swapon "$SWAP"

# Libérer de l'espace sur le volume root
pip cache purge 2>/dev/null || true

echo "Mémoire:"
free -h
swapon --show
