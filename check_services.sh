#!/usr/bin/env bash
# Vérifie que vLLM et TTS répondent avant de lancer voice_chat.py
set -euo pipefail
cd "$(dirname "$0")"
source .env 2>/dev/null || source .env.example

VLLM_PORT="${VLLM_PORT:-8000}"
TTS_PORT="${TTS_PORT:-8001}"

echo -n "vLLM (:${VLLM_PORT})... "
curl -sf "http://localhost:${VLLM_PORT}/v1/models" >/dev/null && echo OK || echo KO

echo -n "TTS (:${TTS_PORT})... "
curl -sf "http://localhost:${TTS_PORT}/health" >/dev/null && echo OK || echo KO

echo ""
echo "Test LLM rapide..."
curl -sf "http://localhost:${VLLM_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"google/gemma-4-26B-A4B-it","messages":[{"role":"user","content":"Dis bonjour en une phrase."}],"max_tokens":64}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"

echo ""
echo "Test TTS..."
curl -sf "http://localhost:${TTS_PORT}/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{"input":"Salut, comment ça va ?","voice":"serena","response_format":"wav"}' \
  --output /tmp/l40s-test.wav && echo "→ /tmp/l40s-test.wav"
