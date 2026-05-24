#!/usr/bin/env bash
set -euo pipefail

STACK="${HOME}/l40s-voice-stack"
cd "$STACK"

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

tmux new-session -d -s voice -n vllm \
  "cd $STACK && source .venv/bin/activate && ./start-vllm.sh 2>&1 | tee vllm.log"

tmux new-window -t voice -n tts \
  "cd $STACK && ./start-tts.sh 2>&1 | tee tts.log"

tmux new-window -t voice -n web \
  "cd $STACK && source .venv/bin/activate && set -a && source .env && set +a && env -u LD_LIBRARY_PATH python voice_chat.py --web --port 8080 2>&1 | tee web.log"

echo "Services lancés (tmux session voice)."
echo "Attente vLLM + TTS…"

for _ in $(seq 1 60); do
  if curl -sf localhost:8000/v1/models >/dev/null 2>&1 \
     && curl -sf localhost:8002/health >/dev/null 2>&1 \
     && curl -sf localhost:8080/voice/status >/dev/null 2>&1; then
    echo "Tous les services répondent."
    curl -s localhost:8002/health
    exit 0
  fi
  sleep 10
done

echo "Attention: timeout healthcheck — voir tmux attach -t voice"
exit 0
