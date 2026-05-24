#!/usr/bin/env bash
set -euo pipefail

STACK="${HOME}/l40s-voice-stack"
UNIT_DIR="${HOME}/.config/systemd/user"
IDLE_MINUTES="${IDLE_MINUTES:-30}"
GRACE_MINUTES="${IDLE_GRACE_MINUTES:-15}"

mkdir -p "$UNIT_DIR"

cat > "$UNIT_DIR/voice-idle-watchdog.service" <<EOF
[Unit]
Description=Voice stack idle auto-stop

[Service]
Type=oneshot
Environment=IDLE_MINUTES=${IDLE_MINUTES}
Environment=IDLE_GRACE_MINUTES=${GRACE_MINUTES}
Environment=IDLE_STOP_ENABLED=${IDLE_STOP_ENABLED:-1}
ExecStart=${STACK}/remote/idle-watchdog.sh
EOF

cat > "$UNIT_DIR/voice-idle-watchdog.timer" <<EOF
[Unit]
Description=Check voice stack idle every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now voice-idle-watchdog.timer
echo "Idle watchdog actif (user timer, ${IDLE_MINUTES} min inactivité, ${GRACE_MINUTES} min grace)."
