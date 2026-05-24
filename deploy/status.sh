#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh
load_config

IID="$(resolve_instance_id)"
STATE="$(instance_state "$IID")"
IP="$(instance_public_ip "$IID")"
[[ "$IP" == "None" ]] && IP="—"

echo "Instance : $IID"
echo "Région   : $AWS_REGION"
echo "État     : $STATE"
echo "IP       : $IP"
echo "Type     : g6e.xlarge (L40S)"

case "$STATE" in
  running)
    echo ""
    echo "Coût GPU  : ~2,33 €/h (~56 €/jour si laissé allumé)"
    echo "Tunnel    : ./deploy/tunnel.sh  → http://localhost:${LOCAL_PORT}"
    echo "Services  : ./deploy/up.sh --running-only"
    ;;
  stopped)
    echo ""
    echo "Coût GPU  : 0 €/h (disque EBS ~15–20 €/mois pour ~150 Go)"
    echo "Relancer  : ./deploy/up.sh"
    ;;
esac
