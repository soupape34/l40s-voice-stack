#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Installation stack L40S (Gemma 26B + Qwen3 TTS) ==="

if ! command -v nvidia-smi &>/dev/null; then
  echo "Erreur: nvidia-smi introuvable. Installez les drivers NVIDIA + CUDA."
  exit 1
fi

nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

python3 -m venv .venv
source .venv/bin/activate
pip install -U pip wheel

# vLLM (Gemma 4 day-0 support)
pip install "vllm>=0.10.0" openai httpx python-dotenv

# STT (Parakeet via nano-parakeet ; ffmpeg pour webm/m4a)
if ! command -v ffmpeg &>/dev/null; then
  echo "Attention: installez ffmpeg (apt install ffmpeg) pour webm/m4a"
fi
pip install nano-parakeet soundfile
# Optionnel : STT_BACKEND=whisper
pip install faster-whisper || true

# TTS CUDA graphs (sans [demo] pour éviter le pin transformers==4.57 de qwen-tts)
pip install faster-qwen3-tts

# Web UI optionnelle
pip install fastapi uvicorn python-multipart

# vLLM/Gemma 4 exige transformers v5 — ré-appliquer après TTS
pip install "transformers>=5.9.0"

# TTS isolé : qwen-tts pin transformers 4.57.x, incompatible avec vLLM 5.x
if ! command -v sox &>/dev/null; then
  echo "Installez sox : sudo apt install -y sox libsox-fmt-all"
fi
python3 -m venv .venv-tts
source .venv-tts/bin/activate
pip install -U pip wheel
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu124
pip install "transformers==4.57.3" faster-qwen3-tts fastapi uvicorn python-dotenv httpx
deactivate
source .venv/bin/activate

echo ""
echo "=== Pré-téléchargement des modèles (peut prendre 30+ min) ==="
huggingface-cli download google/gemma-4-26B-A4B-it || true

huggingface-cli download Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice || true
huggingface-cli download Qwen/Qwen3-TTS-Tokenizer-12Hz || true
huggingface-cli download nvidia/parakeet-tdt-0.6b-v3 parakeet-tdt-0.6b-v3.nemo || true

echo ""
echo "=== Installation terminée ==="
echo "  cp .env.example .env"
echo "  ./deploy/up.sh       # start + services (depuis Mac)"
echo "  # ou manuellement : ./start-vllm.sh | ./start-tts.sh | voice_chat.py --web"
