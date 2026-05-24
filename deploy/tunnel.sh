#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh
load_config

IP="$(get_public_ip)"

if pgrep -f "ssh.*-L ${LOCAL_PORT}:localhost:${WEB_PORT}.*${IP}" >/dev/null 2>&1; then
  echo "Tunnel déjà actif → http://localhost:${LOCAL_PORT}"
  exit 0
fi

echo "Tunnel SSH → http://localhost:${LOCAL_PORT}"
echo "  ${SSH_USER}@${IP}:${WEB_PORT}"
exec ssh -N \
  -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=30 \
  -o ExitOnForwardFailure=yes \
  -i "$SSH_KEY" \
  -L "${LOCAL_PORT}:localhost:${WEB_PORT}" \
  "${SSH_USER}@${IP}"
