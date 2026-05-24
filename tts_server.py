#!/usr/bin/env python3
"""Serveur TTS OpenAI-compatible — CustomVoice (défaut) + voice clone (Base)."""

import io
import os
import struct
import subprocess
import tempfile
from contextlib import asynccontextmanager
from typing import Any, Literal

import numpy as np
import torch
import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel

load_dotenv()
load_dotenv(".env.example")

CUSTOM_MODEL = os.environ.get(
    "TTS_CUSTOM_MODEL", "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"
)
CLONE_MODEL = os.environ.get("TTS_CLONE_MODEL", "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
SPEAKER = os.environ.get("TTS_SPEAKER", "serena")
LANGUAGE = os.environ.get("TTS_LANGUAGE", "French")
PORT = int(os.environ.get("TTS_PORT", "8002"))

tts_custom = None
tts_clone = None
sample_rate = 24000
voice_mode: Literal["custom", "clone"] = "custom"
voice_clone_prompt: list[Any] | None = None
voice_clone_meta: dict[str, Any] = {}


def pcm_to_wav(pcm: np.ndarray, sr: int) -> bytes:
    pcm16 = np.clip(pcm * 32768, -32768, 32767).astype(np.int16)
    data = pcm16.tobytes()
    buf = io.BytesIO()
    buf.write(b"RIFF")
    buf.write(struct.pack("<I", 36 + len(data)))
    buf.write(b"WAVEfmt ")
    buf.write(struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16))
    buf.write(b"data")
    buf.write(struct.pack("<I", len(data)))
    buf.write(data)
    return buf.getvalue()


def ensure_clone_model() -> None:
    global tts_clone, sample_rate
    if tts_clone is not None:
        return
    from faster_qwen3_tts import FasterQwen3TTS

    print(f"Chargement modèle clone {CLONE_MODEL}…")
    tts_clone = FasterQwen3TTS.from_pretrained(
        CLONE_MODEL,
        device="cuda",
        dtype=torch.bfloat16,
    )
    sample_rate = tts_clone.sample_rate
    print(f"Modèle clone prêt — sr={sample_rate}")


def prepare_ref_audio(path: str) -> tuple[str, bool]:
    ext = os.path.splitext(path)[1].lower()
    if ext in {".wav", ".wave"}:
        return path, False
    out = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-i", path, "-ac", "1", "-ar", "24000", out],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise HTTPException(
            500, "ffmpeg requis pour convertir m4a/mp3 (apt install ffmpeg)"
        ) from exc
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or str(exc)).strip()
        raise HTTPException(400, f"Conversion audio échouée: {detail}") from exc
    return out, True


def clear_voice_clone() -> dict[str, Any]:
    global voice_mode, voice_clone_prompt, voice_clone_meta
    voice_mode = "custom"
    voice_clone_prompt = None
    voice_clone_meta = {}
    return {
        "status": "ok",
        "voice_mode": "custom",
        "speaker": SPEAKER,
        "clone_ready": False,
    }


def set_voice_clone(ref_path: str, ref_text: str = "") -> dict[str, Any]:
    global voice_mode, voice_clone_prompt, voice_clone_meta, sample_rate

    ensure_clone_model()
    wav_path, converted = prepare_ref_audio(ref_path)
    try:
        xvec_only = not bool(ref_text.strip())
        prompt_items = tts_clone.model.create_voice_clone_prompt(
            ref_audio=wav_path,
            ref_text=ref_text.strip() or None,
            x_vector_only_mode=xvec_only,
        )
        wavs, sr = tts_clone.generate_voice_clone(
            text="Bonjour.",
            language=LANGUAGE,
            voice_clone_prompt=prompt_items,
            ref_text=ref_text.strip(),
            xvec_only=xvec_only,
        )
        _ = wavs[0] if wavs else None
        sample_rate = sr
        voice_clone_prompt = prompt_items
        voice_mode = "clone"
        voice_clone_meta = {
            "ref_text": ref_text.strip(),
            "xvec_only": xvec_only,
            "mode": "xvec" if xvec_only else "icl",
        }
        return {"status": "ok", "voice_mode": "clone", **voice_clone_meta}
    finally:
        if converted:
            try:
                os.unlink(wav_path)
            except OSError:
                pass


@asynccontextmanager
async def lifespan(app: FastAPI):
    global tts_custom, sample_rate
    from faster_qwen3_tts import FasterQwen3TTS

    print(f"Chargement voix par défaut {CUSTOM_MODEL} sur cuda…")
    tts_custom = FasterQwen3TTS.from_pretrained(
        CUSTOM_MODEL,
        device="cuda",
        dtype=torch.bfloat16,
    )
    sample_rate = tts_custom.sample_rate
    tts_custom.generate_custom_voice(
        text="Bonjour.",
        language=LANGUAGE,
        speaker=SPEAKER,
    )
    print(
        f"TTS prêt — défaut={SPEAKER} ({CUSTOM_MODEL}), "
        f"clone={CLONE_MODEL} (à la demande), sr={sample_rate}"
    )
    yield


app = FastAPI(lifespan=lifespan)


class SpeechRequest(BaseModel):
    model: str = "tts-1"
    input: str
    voice: str = SPEAKER
    response_format: str = "wav"
    speed: float = 1.0


@app.get("/health")
def health():
    return {
        "status": "ok",
        "voice_mode": voice_mode,
        "custom_model": CUSTOM_MODEL,
        "clone_model": CLONE_MODEL,
        "speaker": SPEAKER,
        "language": LANGUAGE,
        "clone_ready": voice_mode == "clone" and voice_clone_prompt is not None,
        **voice_clone_meta,
    }


@app.post("/v1/voice/clone")
async def clone_voice(
    audio: UploadFile = File(...),
    ref_text: str = Form(""),
):
    if tts_custom is None:
        raise HTTPException(503, "Modèle TTS non chargé")

    suffix = os.path.splitext(audio.filename or "ref.wav")[1].lower()
    if suffix not in {".wav", ".wave", ".m4a", ".mp4", ".aac", ".mp3"}:
        raise HTTPException(400, "Format non supporté — utilisez wav ou m4a")

    raw = await audio.read()
    if not raw:
        raise HTTPException(400, "Fichier audio vide")

    with tempfile.NamedTemporaryFile(suffix=suffix or ".wav", delete=False) as tmp:
        tmp.write(raw)
        in_path = tmp.name

    try:
        result = set_voice_clone(in_path, ref_text)
        return {
            **result,
            "filename": audio.filename,
            "sample_rate": sample_rate,
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, str(exc)) from exc
    finally:
        try:
            os.unlink(in_path)
        except OSError:
            pass


@app.post("/v1/voice/reset")
def reset_voice():
    if tts_custom is None:
        raise HTTPException(503, "Modèle TTS non chargé")
    return clear_voice_clone()


@app.post("/v1/audio/speech")
def speech(req: SpeechRequest):
    if not req.input.strip():
        raise HTTPException(400, "input vide")

    try:
        if voice_mode == "clone" and voice_clone_prompt is not None:
            ensure_clone_model()
            ref_text = voice_clone_meta.get("ref_text", "")
            xvec_only = voice_clone_meta.get("xvec_only", True)
            audio_arrays, sr = tts_clone.generate_voice_clone(
                text=req.input,
                language=LANGUAGE,
                voice_clone_prompt=voice_clone_prompt,
                ref_text=ref_text,
                xvec_only=xvec_only,
            )
        else:
            speaker = req.voice or SPEAKER
            audio_arrays, sr = tts_custom.generate_custom_voice(
                text=req.input,
                language=LANGUAGE,
                speaker=speaker,
            )
        audio = audio_arrays[0] if len(audio_arrays) == 1 else np.concatenate(audio_arrays)
        sample_rate = sr
    except Exception as exc:
        raise HTTPException(500, str(exc)) from exc

    if req.response_format == "wav":
        return Response(pcm_to_wav(audio, sample_rate), media_type="audio/wav")
    raise HTTPException(400, f"format {req.response_format} non supporté")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
