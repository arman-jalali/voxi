#!/usr/bin/env python3
"""Voxi local transcription server.

Loads Voxtral-Mini-4B-Realtime (MLX, 6-bit) once and serves:

    GET  /health              -> {"ok": true, "model": "..."}   (200 once warm)
    POST /transcribe          -> {"text": "..."}                (body: WAV bytes)

Single-threaded on purpose: one dictation at a time, no queueing complexity.
Runs on 127.0.0.1 only — audio never leaves the machine.
"""

import json
import os
import sys
import tempfile
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, HTTPServer

MODEL = os.environ.get("VOXI_MODEL", "mlx-community/Voxtral-Mini-4B-Realtime-6bit")
PORT = int(os.environ.get("VOXI_PORT", "48765"))

print(f"[voxi-server] loading {MODEL} ...", flush=True)
t0 = time.time()
import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402

from voxmlx import SpecialTokenPolicy, load_model, generate, _build_prompt_tokens  # noqa: E402

from stream_session import StreamSession  # noqa: E402

model, sp, config = load_model(MODEL)
prompt_tokens, n_delay_tokens = _build_prompt_tokens(sp)
print(f"[voxi-server] model loaded in {time.time() - t0:.1f}s", flush=True)


# The audio encoder is configured with sliding_window=750 but voxmlx applies a
# plain full causal mask, so audio longer than the trained window drifts out of
# distribution and the model starts emitting blanks — long dictations came back
# truncated to roughly the first half. Chunking keeps every segment inside the
# window the encoder was actually trained on.
SAMPLE_RATE = 16000
CHUNK_TARGET_S = 20.0   # nominal segment length
CHUNK_MAX_S = 24.0      # never exceed this in one generate() call
SEARCH_S = 4.0          # hunt for a pause this far back from the target
TAIL_PAD_S = 0.5        # trailing silence so the last word gets flushed


def _decode(samples: np.ndarray) -> str:
    """Run one segment through the model."""
    padded = np.concatenate([samples, np.zeros(int(TAIL_PAD_S * SAMPLE_RATE), dtype=np.float32)])
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()
    try:
        sf.write(tmp.name, padded, SAMPLE_RATE)
        tokens = generate(
            model,
            tmp.name,
            list(prompt_tokens),
            n_delay_tokens=n_delay_tokens,
            temperature=0.0,
            eos_token_id=sp.eos_id,
        )
        return sp.decode(tokens, special_token_policy=SpecialTokenPolicy.IGNORE).strip()
    finally:
        os.unlink(tmp.name)


def _split_points(audio: np.ndarray) -> list:
    """Segment boundaries, each placed at the quietest point near the target so
    a cut lands in a pause rather than mid-word."""
    target = int(CHUNK_TARGET_S * SAMPLE_RATE)
    hard = int(CHUNK_MAX_S * SAMPLE_RATE)
    search = int(SEARCH_S * SAMPLE_RATE)
    win = int(0.1 * SAMPLE_RATE)  # 100ms energy window

    bounds = [0]
    while len(audio) - bounds[-1] > hard:
        start = bounds[-1]
        lo, hi = start + target - search, min(start + target, len(audio) - win)
        region = audio[lo:hi + win]
        if len(region) <= win:
            bounds.append(min(start + target, len(audio)))
            continue
        # RMS per 100ms window; cut at the quietest one.
        n = (len(region) - win) // win
        energies = [float(np.sqrt(np.mean(region[i * win:i * win + win] ** 2))) for i in range(max(n, 1))]
        bounds.append(lo + int(np.argmin(energies)) * win + win // 2)
    bounds.append(len(audio))
    return bounds


def transcribe_file(path: str) -> str:
    audio, sr = sf.read(path, dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != SAMPLE_RATE:  # capture is already 16k; guard anyway
        n_out = int(len(audio) / sr * SAMPLE_RATE)
        audio = np.interp(np.linspace(0, len(audio) - 1, n_out), np.arange(len(audio)), audio).astype(np.float32)

    bounds = _split_points(audio)
    if len(bounds) > 2:
        print(f"[voxi-server] {len(audio) / SAMPLE_RATE:.1f}s -> {len(bounds) - 1} segments", flush=True)
    parts = [_decode(audio[bounds[i]:bounds[i + 1]]) for i in range(len(bounds) - 1)]
    return " ".join(p for p in parts if p)


# --- live preview sessions -------------------------------------------------
# One at a time: the app records one dictation at a time, and MLX work is
# serialized on the GPU anyway. A new /stream/start replaces any stale session.
_stream_lock = threading.Lock()
_stream = None


def stream_start():
    global _stream
    with _stream_lock:
        _stream = StreamSession(model, sp)
    return {"ok": True}


def stream_feed(pcm: bytes):
    with _stream_lock:
        s = _stream
    if s is None:
        return {"error": "no active session"}, 409
    return {"text": s.feed(pcm)}, 200


def stream_finish():
    global _stream
    with _stream_lock:
        s, _stream = _stream, None
    if s is None:
        return {"error": "no active session"}, 409
    return {"text": s.finish()}, 200


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        if self.path == "/health":
            self._json(200, {"ok": True, "model": MODEL})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", 0))
        if self.path == "/stream/start":
            self.rfile.read(length) if length > 0 else None
            self._json(200, stream_start())
            return
        if self.path == "/stream/audio":
            pcm = self.rfile.read(length) if length > 0 else b""
            try:
                payload, code = stream_feed(pcm)
            except Exception as e:  # noqa: BLE001
                traceback.print_exc()
                payload, code = {"error": str(e)}, 500
            self._json(code, payload)
            return
        if self.path == "/stream/finish":
            self.rfile.read(length) if length > 0 else None
            try:
                payload, code = stream_finish()
            except Exception as e:  # noqa: BLE001
                traceback.print_exc()
                payload, code = {"error": str(e)}, 500
            self._json(code, payload)
            return
        if self.path != "/transcribe":
            self._json(404, {"error": "not found"})
            return
        if length <= 0:
            self._json(400, {"error": "empty body"})
            return
        data = self.rfile.read(length)
        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        try:
            tmp.write(data)
            tmp.close()
            t = time.time()
            text = transcribe_file(tmp.name)
            print(f"[voxi-server] transcribed {length} bytes in {time.time() - t:.2f}s", flush=True)
            self._json(200, {"text": text})
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            self._json(500, {"error": str(e)})
        finally:
            os.unlink(tmp.name)

    def log_message(self, fmt, *args):  # quiet default access log
        pass


if __name__ == "__main__":
    # Warm-up: run a short silent clip through the model so the first real
    # dictation doesn't pay MLX compilation cost.
    try:
        import struct
        import wave

        warm = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        with wave.open(warm.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            w.writeframes(struct.pack("<8000h", *([0] * 8000)))  # 0.5s silence
        t = time.time()
        transcribe_file(warm.name)
        os.unlink(warm.name)
        print(f"[voxi-server] warm-up done in {time.time() - t:.1f}s", flush=True)
    except Exception:
        traceback.print_exc()

    server = HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[voxi-server] ready on http://127.0.0.1:{PORT}", flush=True)
    server.serve_forever()
