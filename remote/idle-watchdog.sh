#!/usr/bin/env bash
# Stop EC2 if no user activity for IDLE_MINUTES (after boot grace period).
set -euo pipefail

STACK="${HOME}/l40s-voice-stack"
STATE_DIR="${HOME}/.voice-stack"
ACTIVITY_FILE="${ACTIVITY_FILE:-$STATE_DIR/last_activity}"
BOOT_FILE="${BOOT_FILE:-$STATE_DIR/boot_time}"
IDLE_MINUTES="${IDLE_MINUTES:-30}"
GRACE_MINUTES="${IDLE_GRACE_MINUTES:-15}"
AWS_REGION="${AWS_REGION:-eu-central-1}"

if [[ "${IDLE_STOP_ENABLED:-1}" != "1" ]]; then
  exit 0
fi

now=$(date +%s)
idle_sec=$((IDLE_MINUTES * 60))
grace_sec=$((GRACE_MINUTES * 60))

read_ts() {
  local f="$1"
  local fallback="$2"
  if [[ -f "$f" ]]; then
    cat "$f"
  else
    echo "$fallback"
  fi
}

boot=$(read_ts "$BOOT_FILE" "$now")
last=$(read_ts "$ACTIVITY_FILE" "$boot")

# Grace après boot OS (évite stop avant post-boot / reset des timestamps)
uptime_sec=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
if (( uptime_sec < grace_sec )); then
  exit 0
fi

if (( now - boot < grace_sec )); then
  exit 0
fi

if (( now - last < idle_sec )); then
  exit 0
fi

echo "[idle-watchdog] Inactif depuis $(( (now - last) / 60 )) min (seuil ${IDLE_MINUTES} min) — arrêt…"

if [[ -x "$STACK/remote/persist-models.sh" ]]; then
  bash "$STACK/remote/persist-models.sh" || true
fi

imds_token=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)
imds_hdr=()
if [[ -n "$imds_token" ]]; then
  imds_hdr=(-H "X-aws-ec2-metadata-token: $imds_token")
fi

instance_id=$(curl -sf "${imds_hdr[@]}" \
  http://169.254.169.254/latest/meta-data/instance-id || true)
if [[ -z "$instance_id" ]]; then
  echo "[idle-watchdog] Pas sur EC2 (metadata absent) — skip stop." >&2
  exit 0
fi

region=$(curl -sf "${imds_hdr[@]}" \
  http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "$AWS_REGION")

aws ec2 stop-instances --region "$region" --instance-ids "$instance_id"
echo "[idle-watchdog] Stop demandé pour $instance_id"
