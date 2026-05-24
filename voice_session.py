"""Parlor-style WebSocket voice session for cloud stack."""

from __future__ import annotations

import asyncio
import base64
import json
import re
import struct
import tempfile
import time
from collections.abc import Callable, Iterator

from fastapi import WebSocketDisconnect
from activity import touch_activity
from stt import transcribe

SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?…])\s+")


class Cancelled(Exception):
    pass


def split_sentences(text: str) -> list[str]:
    parts = SENTENCE_SPLIT_RE.split(text.strip())
    return [s.strip() for s in parts if s.strip()]


class SentenceSplitter:
    """Incremental sentence buffer for SSE streaming."""

    def __init__(self, max_hold: int = 90) -> None:
        self.buf = ""
        self.max_hold = max_hold

    def push(self, token: str) -> list[str]:
        self.buf += token
        out: list[str] = []
        while True:
            m = SENTENCE_SPLIT_RE.search(self.buf)
            if m:
                cut = m.end()
            elif len(self.buf) >= self.max_hold:
                cut = self.buf.rfind(" ", 0, self.max_hold)
                if cut <= 0:
                    cut = self.max_hold
            else:
                break
            chunk = self.buf[:cut].strip()
            self.buf = self.buf[cut:].lstrip()
            if chunk:
                out.append(chunk)
        return out

    def flush(self) -> str | None:
        rest = self.buf.strip()
        self.buf = ""
        return rest or None


def wav_bytes_to_pcm(wav: bytes) -> tuple[bytes, int]:
    if len(wav) < 44 or wav[:4] != b"RIFF":
        return wav, 24000
    sample_rate = struct.unpack_from("<I", wav, 24)[0]
    idx = wav.find(b"data")
    if idx == -1:
        return wav[44:], sample_rate
    data_len = struct.unpack_from("<I", wav, idx + 4)[0]
    return wav[idx + 8 : idx + 8 + data_len], sample_rate


async def transcribe_file(path: str) -> str:
    return await asyncio.to_thread(transcribe, path)


def llm_collect(
    text: str,
    llm_stream_fn: Callable[[str], Iterator[str]],
    cancel: Callable[[], bool],
) -> str:
    parts: list[str] = []
    for token in llm_stream_fn(text):
        if cancel():
            raise Cancelled()
        parts.append(token)
    return "".join(parts).strip()


class ParlorVoiceSession:
    """Parlor-compatible /ws protocol: audio wav in, text + PCM chunks out."""

    TTS_SAMPLE_RATE = 24000

    def __init__(
        self,
        ws,
        *,
        llm_stream_fn: Callable[[str], Iterator[str]],
        tts_fn: Callable[[str], bytes],
        loop: asyncio.AbstractEventLoop,
    ) -> None:
        self.ws = ws
        self.llm_stream_fn = llm_stream_fn
        self.tts_fn = tts_fn
        self.loop = loop
        self.interrupted = asyncio.Event()
        self.msg_queue: asyncio.Queue = asyncio.Queue()
        self.gen = 0

    async def send_json(self, msg: dict) -> None:
        await self.ws.send_text(json.dumps(msg, ensure_ascii=False))

    async def receiver(self) -> None:
        try:
            while True:
                raw = await self.ws.receive_text()
                msg = json.loads(raw)
                if msg.get("type") == "interrupt":
                    touch_activity()
                    self.interrupted.set()
                    self.gen += 1
                else:
                    await self.msg_queue.put(msg)
        except WebSocketDisconnect:
            await self.msg_queue.put(None)

    async def run(self) -> None:
        recv_task = asyncio.create_task(self.receiver())
        try:
            while True:
                msg = await self.msg_queue.get()
                if msg is None:
                    break
                await self._handle_turn(msg)
        finally:
            recv_task.cancel()

    async def _handle_turn(self, msg: dict) -> None:
        self.interrupted.clear()
        self.gen += 1
        turn = self.gen
        cancel = lambda: self.interrupted.is_set() or turn != self.gen

        audio_b64 = msg.get("audio")
        text_in = msg.get("text", "").strip()

        if not audio_b64 and not text_in:
            return

        touch_activity()

        if audio_b64:
            wav_bytes = base64.b64decode(audio_b64)
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                tmp.write(wav_bytes)
                audio_path = tmp.name
            try:
                user_text = await transcribe_file(audio_path)
            finally:
                import os

                try:
                    os.unlink(audio_path)
                except OSError:
                    pass
            if not user_text.strip():
                await self.send_json({"type": "error", "message": "Transcription vide"})
                return
        elif text_in:
            user_text = text_in

        if cancel():
            return

        t0 = time.time()
        try:
            reply = await asyncio.to_thread(
                llm_collect, user_text, self.llm_stream_fn, cancel
            )
        except Cancelled:
            return
        llm_time = round(time.time() - t0, 2)

        if cancel() or not reply:
            return

        await self.send_json(
            {
                "type": "text",
                "text": reply,
                **({"transcription": user_text} if audio_b64 else {}),
                "llm_time": llm_time,
            }
        )

        if cancel():
            return

        sentences = split_sentences(reply) or [reply]
        tts_start = time.time()

        await self.send_json(
            {
                "type": "audio_start",
                "sample_rate": self.TTS_SAMPLE_RATE,
                "sentence_count": len(sentences),
            }
        )

        for i, sentence in enumerate(sentences):
            if cancel():
                break
            wav = await asyncio.to_thread(self.tts_fn, sentence)
            if cancel():
                break
            pcm, sr = wav_bytes_to_pcm(wav)
            await self.send_json(
                {
                    "type": "audio_chunk",
                    "audio": base64.b64encode(pcm).decode("ascii"),
                    "index": i,
                    "sample_rate": sr,
                }
            )

        if not cancel():
            await self.send_json(
                {"type": "audio_end", "tts_time": round(time.time() - tts_start, 2)}
            )
