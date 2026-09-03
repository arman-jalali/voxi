#!/usr/bin/env python3
"""Voxi local transcription server.

Loads Voxtral-Mini-4B-Realtime (MLX, 6-bit) once and serves:

    GET  /health              -> {"ok": true, "model": "..."}   (200 once warm)
    POST /transcribe          -> {"text": "..."}                (body: WAV bytes)

Threaded HTTP so an idle keep-alive connection can never block another
request (URLSession holds idle connections open; a single-threaded server
would stall every other call behind it). Model work itself is serialized on
one lock — one dictation at a time. Runs on 127.0.0.1 only.
"""

import json
import os
import sys
import tempfile
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = os.environ.get("VOXI_MODEL", "mlx-community/Voxtral-Mini-4B-Realtime-6bit")
PORT = int(os.environ.get("VOXI_PORT", "48765"))

print(f"[voxi-server] loading {MODEL} ...", flush=True)
t0 = time.time()
import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402

from voxmlx import SpecialTokenPolicy, load_model, generate, _build_prompt_tokens  # noqa: E402

from stream_session import StreamSession  # noqa: E402

# ALL model work — loading included — runs on this one worker thread, whichever
# HTTP thread asks. MLX binds arrays to the stream of the thread that created
# them ("There is no Stream(gpu, N) in current thread" otherwise), and GPU work
# must not interleave anyway. HTTP threads just wait on the future.
_model_worker = ThreadPoolExecutor(max_workers=1, thread_name_prefix="mlx")


def on_model_thread(fn, *args):
    return _model_worker.submit(fn, *args).result()


model, sp, config = on_model_thread(load_model, MODEL)
prompt_tokens, n_delay_tokens = _build_prompt_tokens(sp)
print(f"[voxi-server] model loaded in {time.time() - t0:.1f}s", flush=True)


SAMPLE_RATE = 16000


def transcribe_file(path: str) -> str:
    """Batch path: the whole file through one StreamSession. Same bounded-window
    encoder as the live caption, so long audio neither truncates nor needs
    seams, and there is one decode path to trust."""
    audio, sr = sf.read(path, dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != SAMPLE_RATE:  # capture is already 16k; guard anyway
        n_out = int(len(audio) / sr * SAMPLE_RATE)
        audio = np.interp(np.linspace(0, len(audio) - 1, n_out), np.arange(len(audio)), audio).astype(np.float32)
    pcm = (np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes()
    step = SAMPLE_RATE * 2 * 5  # 5s per feed keeps peak memory flat on long files
    def run():
        session = StreamSession(model, sp)
        for i in range(0, len(pcm), step):
            session.feed(pcm[i:i + step])
        return session.finish()
    return on_model_thread(run)


# --- live preview sessions -------------------------------------------------
# One at a time: the app records one dictation at a time, and MLX work is
# serialized on the GPU anyway. A new /stream/start replaces any stale session.
_stream_lock = threading.Lock()
_stream = None


def stream_start():
    global _stream
    with _stream_lock:
        _stream = on_model_thread(StreamSession, model, sp)
    return {"ok": True}


def stream_feed(pcm: bytes):
    with _stream_lock:
        s = _stream
    if s is None:
        return {"error": "no active session"}, 409
    return {"text": on_model_thread(s.feed, pcm)}, 200


def stream_finish():
    global _stream
    with _stream_lock:
        s, _stream = _stream, None
    if s is None:
        return {"error": "no active session"}, 409
    return {"text": on_model_thread(s.finish)}, 200


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
        t_req = time.time()
        stamp = time.strftime("%H:%M:%S") + f".{int((t_req % 1) * 1000):03d}"
        if self.path == "/stream/start":
            self.rfile.read(length) if length > 0 else None
            try:
                payload, code = stream_start(), 200
            except Exception as e:  # noqa: BLE001
                traceback.print_exc()
                payload, code = {"error": str(e)}, 500
            self._json(code, payload)
            print(f"[{stamp}] stream/start -> {code}", flush=True)
            return
        if self.path == "/stream/audio":
            pcm = self.rfile.read(length) if length > 0 else b""
            try:
                payload, code = stream_feed(pcm)
            except Exception as e:  # noqa: BLE001
                traceback.print_exc()
                payload, code = {"error": str(e)}, 500
            self._json(code, payload)
            print(f"[{stamp}] stream/audio {len(pcm) / 32000:.2f}s audio -> {len(payload.get('text', ''))} chars in {(time.time() - t_req) * 1000:.0f} ms", flush=True)
            return
        if self.path == "/stream/finish":
            self.rfile.read(length) if length > 0 else None
            try:
                payload, code = stream_finish()
            except Exception as e:  # noqa: BLE001
                traceback.print_exc()
                payload, code = {"error": str(e)}, 500
            self._json(code, payload)
            print(f"[{stamp}] stream/finish -> {len(payload.get('text', ''))} chars in {(time.time() - t_req) * 1000:.0f} ms", flush=True)
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
            print(f"[{stamp}] transcribe {length / 32000:.1f}s audio -> {len(text)} chars in {time.time() - t:.2f}s", flush=True)
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
        transcribe_file(warm.name)  # also pins MLX init to the worker thread
        os.unlink(warm.name)
        print(f"[voxi-server] warm-up done in {time.time() - t:.1f}s", flush=True)
    except Exception:
        traceback.print_exc()

    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    server.daemon_threads = True
    print(f"[voxi-server] ready on http://127.0.0.1:{PORT}", flush=True)
    server.serve_forever()
