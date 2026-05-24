#!/usr/bin/env bash
# Vérifie vLLM + TTS sur l'instance (à lancer via SSH ou après post-boot).
set -euo pipefail
cd "$(dirname "$0")"
source .env 2>/dev/null || source .env.example

VLLM_PORT="${VLLM_PORT:-8000}"
TTS_PORT="${TTS_PORT:-8002}"

echo -n "vLLM (:${VLLM_PORT})... "
curl -sf "http://localhost:${VLLM_PORT}/v1/models" >/dev/null && echo OK || echo KO

echo -n "TTS (:${TTS_PORT})... "
curl -sf "http://localhost:${TTS_PORT}/health" >/dev/null && echo OK || echo KO

echo -n "Web (:8080)... "
curl -sf "http://localhost:8080/voice/status" >/dev/null && echo OK || echo KO
