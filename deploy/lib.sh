#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"

load_config() {
  if [[ -f "$DEPLOY_DIR/aws.env" ]]; then
    # shellcheck source=/dev/null
    source "$DEPLOY_DIR/aws.env"
  elif [[ -f "$DEPLOY_DIR/aws.env.example" ]]; then
    # shellcheck source=/dev/null
    source "$DEPLOY_DIR/aws.env.example"
  else
    echo "Erreur: deploy/aws.env manquant." >&2
    exit 1
  fi

  AWS_REGION="${AWS_REGION:-eu-central-1}"
  SSH_USER="${SSH_USER:-ubuntu}"
  SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
  REMOTE_DIR="${REMOTE_DIR:-~/l40s-voice-stack}"
  WEB_PORT="${WEB_PORT:-8080}"
  LOCAL_PORT="${LOCAL_PORT:-8080}"

  SSH_KEY="${SSH_KEY/#\~/$HOME}"
  export AWS_REGION SSH_USER SSH_KEY REMOTE_DIR WEB_PORT LOCAL_PORT
}

resolve_instance_id() {
  load_config
  if [[ -n "${EC2_INSTANCE_ID:-}" ]]; then
    echo "$EC2_INSTANCE_ID"
    return
  fi
  if [[ -n "${EC2_NAME_TAG:-}" ]]; then
    aws ec2 describe-instances \
      --region "$AWS_REGION" \
      --filters "Name=tag:Name,Values=$EC2_NAME_TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
      --query 'Reservations[0].Instances[0].InstanceId' \
      --output text
    return
  fi
  echo "Erreur: EC2_INSTANCE_ID ou EC2_NAME_TAG requis." >&2
  exit 1
}

instance_state() {
  local iid="$1"
  aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --instance-ids "$iid" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text
}

instance_public_ip() {
  local iid="$1"
  aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --instance-ids "$iid" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text
}

write_public_ip() {
  local ip="$1"
  local env_file="$DEPLOY_DIR/aws.env"
  if [[ ! -f "$env_file" ]]; then
    cp "$DEPLOY_DIR/aws.env.example" "$env_file"
  fi
  if grep -q '^EC2_PUBLIC_IP=' "$env_file"; then
    sed -i.bak "s|^EC2_PUBLIC_IP=.*|EC2_PUBLIC_IP=$ip|" "$env_file"
    rm -f "$env_file.bak"
  else
    echo "EC2_PUBLIC_IP=$ip" >> "$env_file"
  fi
  EC2_PUBLIC_IP="$ip"
}

get_public_ip() {
  load_config
  local iid
  iid="$(resolve_instance_id)"
  local ip
  ip="$(instance_public_ip "$iid")"
  if [[ "$ip" == "None" || -z "$ip" ]]; then
    echo "Erreur: pas d'IP publique (instance arrêtée ?)." >&2
    exit 1
  fi
  write_public_ip "$ip"
  echo "$ip"
}

ssh_base() {
  load_config
  local ip="${EC2_PUBLIC_IP:-}"
  if [[ -z "$ip" || "$ip" == "None" ]]; then
    ip="$(get_public_ip)"
  fi
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i "$SSH_KEY" "${SSH_USER}@${ip}"
}

ssh_cmd() {
  load_config
  local ip="${EC2_PUBLIC_IP:-}"
  if [[ -z "$ip" || "$ip" == "None" ]]; then
    ip="$(get_public_ip)"
  fi
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i "$SSH_KEY" "${SSH_USER}@${ip}" "$@"
}

wait_for_state() {
  local iid="$1"
  local want="$2"
  local tries="${3:-60}"
  local delay="${4:-10}"
  for _ in $(seq 1 "$tries"); do
    local state
    state="$(instance_state "$iid")"
    if [[ "$state" == "$want" ]]; then
      return 0
    fi
    echo "  … état=$state (attente $want)"
    sleep "$delay"
  done
  echo "Timeout: instance pas en état $want." >&2
  return 1
}

wait_for_ssh() {
  local tries="${1:-30}"
  for i in $(seq 1 "$tries"); do
    if ssh_cmd 'echo ok' >/dev/null 2>&1; then
      echo "SSH prêt."
      return 0
    fi
    echo "  SSH tentative $i/$tries…"
    sleep 10
  done
  echo "Timeout SSH." >&2
  return 1
}
