#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh

PERSIST=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-persist) PERSIST=0; shift ;;
    -y|--yes) YES=1; shift ;;
    *) echo "Usage: $0 [-y] [--no-persist]" >&2; exit 1 ;;
  esac
done

load_config
IID="$(resolve_instance_id)"
STATE="$(instance_state "$IID")"

if [[ "$STATE" == "stopped" ]]; then
  echo "Déjà arrêtée."
  exit 0
fi

if [[ "$STATE" != "running" ]]; then
  echo "État inattendu: $STATE" >&2
  exit 1
fi

if [[ "${YES:-}" != "1" ]]; then
  echo "Arrêt de $IID (EBS conservé, NVMe éphémère perdu au prochain boot)."
  echo "Les modèles HF seront migrés sur EBS avant l'arrêt (une fois)."
  read -r -p "Continuer ? [y/N] " ans
  [[ "$ans" =~ ^[yY] ]] || exit 0
fi

if [[ "$PERSIST" == "1" ]]; then
  echo "Migration modèles HF → EBS (si nécessaire)…"
  ssh_cmd "bash -s" < ../remote/persist-models.sh
fi

echo "Arrêt instance…"
aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$IID" >/dev/null
wait_for_state "$IID" stopped 60 10
echo "Arrêtée. GPU = 0 €/h. Relancer avec ./deploy/up.sh"
