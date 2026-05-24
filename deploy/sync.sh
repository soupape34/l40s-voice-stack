#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh
load_config

IP="$(get_public_ip)"
ROOT="$(cd .. && pwd)"

echo "Sync code → ${SSH_USER}@${IP}:${REMOTE_DIR}"

rsync -avz --delete \
  -e "ssh -o StrictHostKeyChecking=no -i $SSH_KEY" \
  --exclude '.git/' \
  --exclude '.env' \
  --exclude '.venv/' \
  --exclude '.venv-tts/' \
  --exclude '*.log' \
  --exclude 'deploy/aws.env' \
  --exclude '__pycache__/' \
  "$ROOT/" "${SSH_USER}@${IP}:${REMOTE_DIR}/"

echo "Sync terminé."
