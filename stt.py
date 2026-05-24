"""STT backends for the L40S voice stack."""

import os

from dotenv import load_dotenv

load_dotenv()
load_dotenv(".env.example")

STT_BACKEND = os.environ.get("STT_BACKEND", "parakeet").lower()
PARAKEET_MODEL = os.environ.get("PARAKEET_MODEL", "nvidia/parakeet-tdt-0.6b-v3")
PARAKEET_DEVICE = os.environ.get("PARAKEET_DEVICE", "cuda")
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "large-v3-turbo")
WHISPER_DEVICE = os.environ.get("WHISPER_DEVICE", "cuda")
WHISPER_COMPUTE = os.environ.get("WHISPER_COMPUTE", "int8_float16")

_model = None


def backend_name() -> str:
    if STT_BACKEND == "parakeet":
        return f"Parakeet TDT ({PARAKEET_MODEL})"
    if STT_BACKEND == "whisper":
        return f"Whisper ({WHISPER_MODEL})"
    raise ValueError(f"STT_BACKEND inconnu: {STT_BACKEND!r} (parakeet|whisper)")


def _load_model():
    global _model
    if _model is not None:
        return _model

    os.environ.pop("LD_LIBRARY_PATH", None)

    if STT_BACKEND == "parakeet":
        from nano_parakeet import from_pretrained

        print(f"Chargement {PARAKEET_MODEL} sur {PARAKEET_DEVICE}...")
        _model = from_pretrained(PARAKEET_MODEL, device=PARAKEET_DEVICE)
        return _model

    if STT_BACKEND == "whisper":
        from faster_whisper import WhisperModel

        print(f"Chargement Whisper {WHISPER_MODEL}...")
        _model = WhisperModel(WHISPER_MODEL, device=WHISPER_DEVICE, compute_type=WHISPER_COMPUTE)
        return _model

    raise ValueError(f"STT_BACKEND inconnu: {STT_BACKEND!r}")


def warmup() -> None:
    """Pre-load STT model so the first request is not slow."""
    _load_model()


def transcribe(path: str) -> str:
    model = _load_model()

    if STT_BACKEND == "parakeet":
        text = model.transcribe(path)
        return text.strip()

    segments, _ = model.transcribe(path, language="fr", beam_size=1, vad_filter=True)
    return " ".join(s.text.strip() for s in segments).strip()
