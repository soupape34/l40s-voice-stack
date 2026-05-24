#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh
load_config

IID="$(resolve_instance_id)"
STATE="$(instance_state "$IID")"

if [[ "$STATE" == "running" ]]; then
  IP="$(get_public_ip)"
  echo "Déjà running — IP $IP"
  exit 0
fi

if [[ "$STATE" != "stopped" ]]; then
  echo "État inattendu: $STATE" >&2
  exit 1
fi

echo "Démarrage $IID…"
aws ec2 start-instances --region "$AWS_REGION" --instance-ids "$IID" >/dev/null
wait_for_state "$IID" running 60 10
sleep 5
IP="$(get_public_ip)"
echo "Instance running — IP $IP"
