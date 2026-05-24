#!/usr/bin/env bash
set -euo pipefail

STACK="${HOME}/l40s-voice-stack"
cd "$STACK"

# Pause idle watchdog pendant post-boot (timer OnBootSec=5min sinon stop pendant vLLM)
systemctl --user stop voice-idle-watchdog.timer 2>/dev/null || true
systemctl --user stop voice-idle-watchdog.service 2>/dev/null || true

# Reset idle timer (évite stop auto pendant post-boot / chargement vLLM)
mkdir -p "${HOME}/.voice-stack"
now=$(date +%s)
echo "$now" > "${HOME}/.voice-stack/boot_time"
echo "$now" > "${HOME}/.voice-stack/last_activity"

# Cache HF sur EBS si migré
if [[ -d "${HOME}/.cache/huggingface-ebs" ]]; then
  mkdir -p "${HOME}/.cache"
  ln -sfn "${HOME}/.cache/huggingface-ebs" "${HOME}/.cache/huggingface"
fi

chmod +x *.sh remote/*.sh 2>/dev/null || true

# Swap NVMe (recréé à chaque boot — normal)
./aws-bootstrap.sh

# tmux : vLLM + TTS (.venv-tts) + web
tmux kill-session -t voice 2>/dev/null || true
tmux start-server 2>/dev/null || true

tmux new-session -d -s voice -n vllm \
  "cd $STACK && source .venv/bin/activate && ./start-vllm.sh 2>&1 | tee vllm.log"

tmux new-window -t voice -n tts \
  "cd $STACK && ./start-tts.sh 2>&1 | tee tts.log"

tmux new-window -t voice -n web \
  "cd $STACK && source .venv/bin/activate && set -a && source .env && set +a && env -u LD_LIBRARY_PATH python voice_chat.py --web --port 8080 2>&1 | tee web.log"

echo "Services lancés (tmux session voice)."

if [[ "${POST_BOOT_SKIP_WAIT:-0}" == "1" ]]; then
  echo "Healthcheck ignoré (POST_BOOT_SKIP_WAIT=1) — vLLM charge en arrière-plan."
else
echo "Attente vLLM + TTS…"

ready=0
for i in $(seq 1 60); do
  vllm=0 tts=0 web=0
  curl -sf localhost:8000/v1/models >/dev/null 2>&1 && vllm=1
  curl -sf localhost:8002/health >/dev/null 2>&1 && tts=1
  curl -sf localhost:8080/voice/status >/dev/null 2>&1 && web=1
  if [[ "$vllm" == "1" && "$tts" == "1" && "$web" == "1" ]]; then
    echo "Tous les services répondent."
    curl -s localhost:8002/health
    ready=1
    break
  fi
  echo "Healthcheck $i/60 — vLLM=$vllm TTS=$tts web=$web"
  sleep 10
done

if [[ "$ready" != "1" ]]; then
  echo "Attention: timeout healthcheck — voir tmux attach -t voice"
fi
fi

# Idle auto-stop (30 min sans interaction)
if [[ -x "$STACK/remote/install-idle-watchdog.sh" ]]; then
  # shellcheck source=/dev/null
  [[ -f "$STACK/.env" ]] && source "$STACK/.env"
  bash "$STACK/remote/install-idle-watchdog.sh" || true
fi

exit 0
