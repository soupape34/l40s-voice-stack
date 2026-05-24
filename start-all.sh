#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

chmod +x aws-bootstrap.sh start-vllm.sh start-tts.sh 2>/dev/null || true
./aws-bootstrap.sh

tmux kill-session -t voice 2>/dev/null || true
tmux new-session -d -s voice -n vllm "cd $(pwd) && source .venv/bin/activate && ./start-vllm.sh 2>&1 | tee vllm.log"
tmux new-window -t voice -n tts "cd $(pwd) && source .venv/bin/activate && ./start-tts.sh 2>&1 | tee tts.log"
tmux new-window -t voice -n web "cd $(pwd) && source .venv/bin/activate && python voice_chat.py --web --port 8080 2>&1 | tee web.log"

echo "Services démarrés dans tmux session 'voice'"
echo "  tmux attach -t voice"
