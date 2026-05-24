#!/usr/bin/env bash
# Migre le cache Hugging Face du NVMe éphémère vers EBS (survit à stop/start).
set -euo pipefail

HF_LINK="${HOME}/.cache/huggingface"
HF_EBS="${HOME}/.cache/huggingface-ebs"
MARKER="${HF_EBS}/.persisted-on-ebs"

if [[ -f "$MARKER" ]]; then
  echo "Modèles déjà persistés sur EBS."
  if [[ -L "$HF_LINK" ]]; then
    rm -f "$HF_LINK"
  fi
  mkdir -p "$(dirname "$HF_LINK")"
  ln -sfn "$HF_EBS" "$HF_LINK"
  exit 0
fi

NVME_HF="/opt/dlami/nvme/hf-cache/huggingface"
if [[ -L "$HF_LINK" ]]; then
  target="$(readlink -f "$HF_LINK")"
  if [[ -d "$target" ]]; then
    NVME_HF="$target"
  fi
fi

mkdir -p "$HF_EBS"
if [[ -d "$NVME_HF/hub" ]] && [[ ! -d "$HF_EBS/hub" ]]; then
  echo "Copie modèles HF NVMe → EBS (~56 Go, quelques minutes)…"
  rsync -a --info=progress2 "$NVME_HF/" "$HF_EBS/"
elif [[ -d "$HF_LINK/hub" ]] && [[ ! -d "$HF_EBS/hub" ]] && [[ ! -L "$HF_LINK" ]]; then
  echo "Copie modèles HF → EBS…"
  rsync -a "$HF_LINK/" "$HF_EBS/"
fi

touch "$MARKER"
rm -f "$HF_LINK"
ln -sfn "$HF_EBS" "$HF_LINK"
echo "Cache HF sur EBS : $HF_EBS"
du -sh "$HF_EBS" 2>/dev/null || true
