#!/usr/bin/env python3
"""
Chat vocal : Parakeet STT → Gemma 4 26B (vLLM) → Qwen3 TTS 0.6B.
WebSocket duplex : STT, TTS par phrases, audio streamé, barge-in.
"""

import os

os.environ.pop("LD_LIBRARY_PATH", None)

import argparse
import asyncio
import sys
import tempfile
from collections.abc import Iterator
from contextlib import asynccontextmanager

import httpx
from dotenv import load_dotenv
from openai import OpenAI

from activity import mark_boot, touch_activity
from stt import backend_name, transcribe, warmup
from voice_session import ParlorVoiceSession

load_dotenv()
load_dotenv(".env.example")

VLLM_URL = os.environ.get("VLLM_BASE_URL", "http://localhost:8000/v1")
TTS_URL = os.environ.get("TTS_BASE_URL", "http://localhost:8002")
LLM_MAX_TOKENS = int(os.environ.get("LLM_MAX_TOKENS", "128"))
SYSTEM = os.environ.get(
    "SYSTEM_PROMPT",
    "Tu es une assistante amicale. Réponds toujours en français, de façon concise (1-3 phrases).",
)

_history: list[dict] = []
_llm_client: OpenAI | None = None
_tts_client: httpx.Client | None = None


def _get_llm() -> OpenAI:
    global _llm_client
    if _llm_client is None:
        _llm_client = OpenAI(base_url=VLLM_URL, api_key="dummy")
    return _llm_client


def _get_tts() -> httpx.Client:
    global _tts_client
    if _tts_client is None:
        _tts_client = httpx.Client(timeout=120.0)
    return _tts_client


def llm_reply(text: str) -> str:
    return "".join(llm_reply_stream(text)).strip()


def llm_reply_stream(text: str) -> Iterator[str]:
    global _history
    client = _get_llm()
    _history.append({"role": "user", "content": text})
    messages = [{"role": "system", "content": SYSTEM}, *_history[-10:]]
    stream = client.chat.completions.create(
        model="google/gemma-4-26B-A4B-it",
        messages=messages,
        max_tokens=LLM_MAX_TOKENS,
        temperature=0.6,
        stream=True,
    )
    parts: list[str] = []
    for chunk in stream:
        delta = chunk.choices[0].delta.content or ""
        if delta:
            parts.append(delta)
            yield delta
    _history.append({"role": "assistant", "content": "".join(parts).strip()})


def synthesize_bytes(text: str) -> bytes:
    r = _get_tts().post(
        f"{TTS_URL}/v1/audio/speech",
        json={
            "input": text,
            "voice": os.environ.get("TTS_SPEAKER", "serena"),
            "response_format": "wav",
        },
    )
    r.raise_for_status()
    return r.content


def synthesize(text: str, out_path: str) -> None:
    with open(out_path, "wb") as f:
        f.write(synthesize_bytes(text))


def pipeline_from_audio(audio_path: str, out_wav: str) -> tuple[str, str]:
    user_text = transcribe(audio_path)
    reply = llm_reply(user_text)
    synthesize(reply, out_wav)
    return user_text, reply


def pipeline_from_text(text: str, out_wav: str | None) -> str:
    reply = llm_reply(text)
    if out_wav:
        synthesize(reply, out_wav)
    return reply


def run_web(port: int):
    from pathlib import Path

    from fastapi import FastAPI, File, Form, UploadFile, WebSocket
    import uvicorn

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        print("Pré-chargement STT…")
        try:
            await asyncio.to_thread(warmup)
            print("STT prêt.")
        except Exception as exc:
            print(f"STT warmup ignoré ({exc})")
        mark_boot()
        print("Activity tracker prêt (idle auto-stop).")
        yield
        if _tts_client is not None:
            _tts_client.close()

    app = FastAPI(lifespan=lifespan)
    template_path = Path(__file__).parent / "web_ui.html"

    def render_html() -> str:
        return template_path.read_text(encoding="utf-8").replace(
            "{{STT_LABEL}}", backend_name()
        )

    @app.get("/")
    def index():
        from fastapi.responses import HTMLResponse

        return HTMLResponse(render_html())

    @app.post("/voice/clone")
    async def voice_clone(
        audio: UploadFile = File(...),
        ref_text: str = Form(""),
    ):
        touch_activity()
        raw = await audio.read()
        if not raw:
            return {"status": "error", "message": "Fichier audio vide"}
        files = {
            "audio": (
                audio.filename or "ref.wav",
                raw,
                audio.content_type or "application/octet-stream",
            )
        }
        data = {"ref_text": ref_text}
        try:
            r = _get_tts().post(
                f"{TTS_URL}/v1/voice/clone",
                files=files,
                data=data,
                timeout=180.0,
            )
            r.raise_for_status()
            return r.json()
        except httpx.HTTPStatusError as exc:
            detail = exc.response.text
            try:
                detail = exc.response.json().get("detail", detail)
            except Exception:
                pass
            return {"status": "error", "message": str(detail)}
        except Exception as exc:
            return {"status": "error", "message": str(exc)}

    @app.post("/voice/reset")
    async def voice_reset():
        touch_activity()
        try:
            r = _get_tts().post(f"{TTS_URL}/v1/voice/reset", timeout=30.0)
            r.raise_for_status()
            return r.json()
        except httpx.HTTPStatusError as exc:
            detail = exc.response.text
            try:
                detail = exc.response.json().get("detail", detail)
            except Exception:
                pass
            return {"status": "error", "message": str(detail)}
        except Exception as exc:
            return {"status": "error", "message": str(exc)}

    @app.get("/voice/status")
    async def voice_status():
        try:
            r = _get_tts().get(f"{TTS_URL}/health", timeout=10.0)
            r.raise_for_status()
            return r.json()
        except Exception as exc:
            return {"status": "error", "message": str(exc)}

    @app.websocket("/ws")
    async def ws_parlor(ws: WebSocket):
        await ws.accept()
        session = ParlorVoiceSession(
            ws,
            llm_stream_fn=llm_reply_stream,
            tts_fn=synthesize_bytes,
            loop=asyncio.get_running_loop(),
        )
        await session.run()

    uvicorn.run(app, host="0.0.0.0", port=port)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--web", action="store_true")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--text", help="Test texte sans audio")
    parser.add_argument("--audio", help="Fichier WAV/MP3 entrant")
    parser.add_argument("--out", default="reply.wav")
    args = parser.parse_args()

    if args.web:
        run_web(args.port)
        return
    if args.text:
        pipeline_from_text(args.text, args.out)
        return
    if args.audio:
        pipeline_from_audio(args.audio, args.out)
        return
    parser.print_help()
    sys.exit(1)


if __name__ == "__main__":
    main()
