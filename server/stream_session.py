"""Incremental streaming transcription session.

Adapted from voxmlx's `stream_transcribe` mic loop, but driven by audio pushed
in from the app instead of a sounddevice callback. One session per dictation.

Used two ways: fed incrementally while the user talks (the pill's live caption,
and — once flushed at key-up — the transcript that gets inserted), and fed a
whole file at once by the batch /transcribe endpoint. Both go through the same
bounded-window encoder, so there is exactly one decode path to trust.

The app still falls back to /transcribe when the live session failed or came
back implausibly short, so a streaming glitch can never cost someone their words.
"""

import threading

import mlx.core as mx
import numpy as np
from voxmlx import SpecialTokenPolicy, _build_prompt_tokens
from voxmlx.audio import SAMPLES_PER_TOKEN, log_mel_spectrogram_step
from voxmlx.cache import RotatingKVCache

N_LEFT_PAD_TOKENS = 32
# Trailing silence fed at finish(): the model emits text ~6 tokens behind the
# audio, so without it the last word is cut ("the issu"). Matches voxmlx's pad.
N_RIGHT_PAD_TOKENS = 17
SLIDING_WINDOW = 8192
# The audio encoder was trained with a 750-frame sliding window (config
# `sliding_window`). voxmlx's encode_step allocates a 100k-frame cache when
# handed None — effectively unbounded — and past the trained window the
# encoder drifts and the model emits blanks, so long dictations went silent
# after ~40s. Bounding the cache ourselves restores the trained behaviour.
ENCODER_WINDOW = 750


class StreamSession:
    """Feed PCM in, read partial text out. Not thread-safe across sessions;
    the server serializes calls with a lock because MLX work is single-GPU."""

    def __init__(self, model, sp, temperature: float = 0.0):
        self.model = model
        self.sp = sp
        self.temperature = temperature
        self.lock = threading.Lock()

        self.prompt_tokens, self.n_delay_tokens = _build_prompt_tokens(sp)
        self.prefix_len = len(self.prompt_tokens)
        self.eos_token_id = sp.eos_id

        self.t_cond = model.time_embedding(mx.array([self.n_delay_tokens], dtype=mx.float32))
        mx.eval(self.t_cond)
        self.text_embeds = model.language_model.embed(mx.array([self.prompt_tokens]))[0]
        mx.eval(self.text_embeds)
        self.n_layers = len(model.language_model.layers)

        # Decoder state
        self.cache = None
        self.y = None
        self.prefilled = False

        # Incremental encoder state
        self.audio_tail = None
        self.conv1_tail = None
        self.conv2_tail = None
        self.encoder_cache = [RotatingKVCache(ENCODER_WINDOW) for _ in model.encoder.layers]
        self.ds_buf = None

        self.pending_audio = np.zeros(0, dtype=np.float32)
        self.audio_embeds = None
        self.n_audio_samples_fed = 0
        self.n_total_decoded = 0
        self.first_cycle = True

        self.text = ""

    def _sample(self, logits):
        if self.temperature <= 0:
            return mx.argmax(logits[0, -1:], axis=-1).squeeze()
        return mx.random.categorical(logits[0, -1:] / self.temperature).squeeze()

    def _encode_pending(self) -> None:
        if len(self.pending_audio) < SAMPLES_PER_TOKEN:
            return
        n_feed = (len(self.pending_audio) // SAMPLES_PER_TOKEN) * SAMPLES_PER_TOKEN
        chunk = self.pending_audio[:n_feed]
        self.pending_audio = self.pending_audio[n_feed:]
        self.n_audio_samples_fed += n_feed

        if self.first_cycle:
            left_pad = np.zeros(N_LEFT_PAD_TOKENS * SAMPLES_PER_TOKEN, dtype=np.float32)
            chunk = np.concatenate([left_pad, chunk])
            self.first_cycle = False

        mel, self.audio_tail = log_mel_spectrogram_step(chunk, self.audio_tail)
        new_embeds, self.conv1_tail, self.conv2_tail, self.encoder_cache, self.ds_buf = (
            self.model.encode_step(mel, self.conv1_tail, self.conv2_tail, self.encoder_cache, self.ds_buf)
        )
        if new_embeds is not None:
            mx.eval(new_embeds)
            if self.audio_embeds is not None:
                self.audio_embeds = mx.concatenate([self.audio_embeds, new_embeds])
            else:
                self.audio_embeds = new_embeds

    def _decode_available(self) -> None:
        if self.audio_embeds is None:
            return
        safe_total = N_LEFT_PAD_TOKENS + self.n_audio_samples_fed // SAMPLES_PER_TOKEN
        n_decodable = min(self.audio_embeds.shape[0], safe_total - self.n_total_decoded)
        if n_decodable <= 0:
            return

        if not self.prefilled:
            if self.audio_embeds.shape[0] < self.prefix_len:
                return
            self.cache = [RotatingKVCache(SLIDING_WINDOW) for _ in range(self.n_layers)]
            prefix_embeds = (self.text_embeds + self.audio_embeds[: self.prefix_len])[None, :, :]
            logits = self.model.decode(prefix_embeds, self.t_cond, "causal", self.cache)
            mx.eval(logits)
            self.y = self._sample(logits)
            mx.async_eval(self.y)
            self.audio_embeds = self.audio_embeds[self.prefix_len :]
            self.n_total_decoded += self.prefix_len
            self.prefilled = True
            n_decodable = min(self.audio_embeds.shape[0], safe_total - self.n_total_decoded)
            if n_decodable <= 0:
                return

        consumed = 0
        for i in range(n_decodable):
            token_embed = self.model.language_model.embed(self.y.reshape(1, 1))[0, 0]
            step_embed = (self.audio_embeds[i] + token_embed)[None, None, :]
            logits = self.model.decode(step_embed, self.t_cond, mask=None, cache=self.cache)
            next_y = self._sample(logits)
            mx.async_eval(next_y)

            token_id = self.y.item()
            consumed = i + 1
            if token_id == self.eos_token_id:
                # A pause can make the model close the utterance; in a live
                # preview that must not end the session — keep going.
                self.y = next_y
                continue
            self.text += self.sp.decode([token_id], special_token_policy=SpecialTokenPolicy.IGNORE)
            self.y = next_y

        self.audio_embeds = self.audio_embeds[consumed:]
        self.n_total_decoded += consumed
        mx.clear_cache()

    def feed(self, pcm16: bytes) -> str:
        """Append raw little-endian Int16 mono 16kHz samples; returns text so far."""
        with self.lock:
            samples = np.frombuffer(pcm16, dtype=np.int16).astype(np.float32) / 32768.0
            self.pending_audio = np.append(self.pending_audio, samples)
            self._encode_pending()
            self._decode_available()
            return self.text

    def finish(self) -> str:
        """Flush trailing audio (plus right padding) and return the final text."""
        with self.lock:
            pad = (SAMPLES_PER_TOKEN - (len(self.pending_audio) % SAMPLES_PER_TOKEN)) % SAMPLES_PER_TOKEN
            pad += N_RIGHT_PAD_TOKENS * SAMPLES_PER_TOKEN
            self.pending_audio = np.append(self.pending_audio, np.zeros(pad, dtype=np.float32))
            self._encode_pending()
            self._decode_available()
            return self.text.strip()
