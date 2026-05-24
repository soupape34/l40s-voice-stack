#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

RUNNING_ONLY=0
NO_SYNC=0
NO_TUNNEL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --running-only) RUNNING_ONLY=1; shift ;;
    --no-sync) NO_SYNC=1; shift ;;
    --no-tunnel) NO_TUNNEL=1; shift ;;
    *) echo "Usage: $0 [--running-only] [--no-sync] [--no-tunnel]" >&2; exit 1 ;;
  esac
done

# shellcheck source=lib.sh
source ./lib.sh
load_config

if [[ "$RUNNING_ONLY" != "1" ]]; then
  ./start.sh
fi

wait_for_ssh 36

if [[ "$NO_SYNC" != "1" ]]; then
  ./sync.sh
fi

echo "Post-boot + démarrage services…"
ssh_cmd "bash -s" < ../remote/post-boot.sh

echo ""
echo "Stack prêt."
echo "  Status : ./deploy/status.sh"
if [[ "$NO_TUNNEL" != "1" ]]; then
  echo "  Tunnel : ./deploy/tunnel.sh   (autre terminal)"
  echo "  UI     : http://localhost:${LOCAL_PORT}"
fi
