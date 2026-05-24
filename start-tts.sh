#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
elif [[ -f .env.example ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env.example
  set +a
fi

export CUDA_VISIBLE_DEVICES="${TTS_GPU:-0}"

# qwen-tts needs transformers 4.57.x; vLLM needs 5.x — use isolated venv if present
if [[ -d .venv-tts ]]; then
  source .venv-tts/bin/activate
elif [[ -d .venv ]]; then
  source .venv/bin/activate
fi

echo "Démarrage faster-qwen3-tts sur GPU ${CUDA_VISIBLE_DEVICES} (port ${TTS_PORT:-8002})..."
echo "  Voix défaut: ${TTS_SPEAKER:-serena} (${TTS_CUSTOM_MODEL:-CustomVoice})"
echo "  Clone: ${TTS_CLONE_MODEL:-Base} (à la demande) | Langue: ${TTS_LANGUAGE:-French}"

exec python tts_server.py
