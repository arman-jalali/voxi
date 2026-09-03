# Privacy

## The promise

Your voice never leaves your Mac. The speech model runs locally, in a process
the app starts on your own machine. There is no cloud API, no account, no
middleman server, no analytics, no telemetry. The code is open — verify all of
this.

## What leaves your machine (the complete list)

1. **Nothing while you dictate.** The app's only network connection is to
   `127.0.0.1:48765` — the local Voxtral model server — over the loopback
   interface. That traffic never reaches a network card.
2. **One download, once:** `scripts/install-server.sh` (or the first launch)
   fetches the model weights from Hugging Face
   (`mlx-community/Voxtral-Mini-4B-Realtime-6bit`, ~2.7 GB) into the standard
   Hugging Face cache. It contains no audio and sends nothing about you beyond
   an ordinary HTTPS download.

That is the whole list.

## What never leaves

- Audio, transcripts, history, dictionary — none of it is ever transmitted.
- Which apps you use, when you dictate, or anything you type.
- Keystrokes: the event tap watches your dictation key, plus — only while a
  dictation is active — Esc (cancel), Space (the hands-free gesture), and the
  *fact that* another key was pressed (the accidental-chord guard; which key it
  was is never examined beyond its keycode, never logged, never stored). When
  you're not dictating, other keys pass through untouched.
- Screenshots: never taken. The app contains no screen-capture code.
- Telemetry: there is none. No analytics SDK, no crash uploader, no phone-home.

## What's stored locally, and your controls

- One folder per dictation (`~/Library/Application Support/Voxi/recordings/`):
  crash-safe audio, transcript, metadata — this is what makes Retry and recovery
  work.
- Settings → Privacy & Storage: audio retention (24h / 7d / 30d / forever /
  never — "never" disables Retry), plus one-click **Delete all history**.
- The model server runtime (Python venv, weights cache) lives alongside, in
  `~/Library/Application Support/Voxi/` and `~/.cache/huggingface/`.
- Local files are protected by FileVault if enabled; they are not separately
  encrypted (stated honestly).

## Secure input

When a password field is focused (secure input), dictation refuses to start, and
a transcript in flight is held in History only — never inserted, never placed on
the clipboard.

## Verify it

- Build from source (`./scripts/build-app.sh`).
- Watch traffic with Little Snitch or `nettop` while dictating — you'll see
  **no** remote host. The only connection is to `127.0.0.1:48765`.
- Read the server: [`server/voxi_server.py`](../server/voxi_server.py) binds to
  `127.0.0.1` only and has no outbound code path.
