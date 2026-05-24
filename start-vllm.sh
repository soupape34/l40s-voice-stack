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

export CUDA_VISIBLE_DEVICES="${VLLM_GPU:-0}"

ARGS=(
  serve "${VLLM_MODEL:-google/gemma-4-26B-A4B-it}"
  --host 0.0.0.0
  --port "${VLLM_PORT:-8000}"
  --max-model-len "${MAX_MODEL_LEN:-16384}"
  --max-num-batched-tokens 8192
  --gpu-memory-utilization "${GPU_MEMORY_UTIL:-0.82}"
  --dtype bfloat16
  --enable-auto-tool-choice
  --tool-call-parser gemma4
  --trust-remote-code
)

if [[ "${VLLM_QUANTIZATION:-fp8}" != "none" ]]; then
  ARGS+=(--quantization "${VLLM_QUANTIZATION}")
  ARGS+=(--kv-cache-dtype fp8)
fi

echo "Démarrage vLLM sur GPU ${CUDA_VISIBLE_DEVICES} (port ${VLLM_PORT:-8000})..."
echo "  Modèle: ${VLLM_MODEL:-google/gemma-4-26B-A4B-it}"
echo "  Quantization: ${VLLM_QUANTIZATION:-fp8}"

if [[ -d .venv ]]; then
  source .venv/bin/activate
fi

exec vllm "${ARGS[@]}"
