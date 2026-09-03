# Third-party notices

## Fonts

### Google Sans Flex
- File: `App/Resources/Fonts/GoogleSansFlex/GoogleSansFlex-Regular.ttf` (variable font)
- Copyright: Google LLC / Font Bureau (David Berlow)
- License: SIL Open Font License 1.1 — see `App/Resources/Fonts/GoogleSansFlex/OFL-GoogleSansFlex.txt`
- Source: served via Google Fonts (fonts.google.com/specimen/Google+Sans+Flex); binary
  pinned in-repo. The font is used unmodified (the OFL Reserved Font Name clause
  requires renaming if modified).

### Google Sans Code
- File: `App/Resources/Fonts/GoogleSansCode/GoogleSansCode-VF.ttf` (variable font, v7.001)
- Copyright: Google LLC
- License: SIL Open Font License 1.1 — see `App/Resources/Fonts/GoogleSansCode/OFL-GoogleSansCode.txt`
- Source: github.com/googlefonts/googlesans-code (release v7.001), unmodified.

## Sounds

None — no third-party audio ships in this app. The earcons are original works,
synthesized from scratch by `scripts/generate-earcons.py` (sine fundamentals plus
soft harmonics; no samples, no recorded material) and covered by this
repository's Apache 2.0 license. See `App/Resources/Sounds/ATTRIBUTION.md`.

## Swift packages

| Package | License |
|---|---|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (sindresorhus) | MIT |
| [Sauce](https://github.com/Clipy/Sauce) (Clipy) | MIT |
| [GRDB.swift](https://github.com/groue/GRDB.swift) (Gwendal Roué) | MIT |
| [Sparkle](https://github.com/sparkle-project/Sparkle) (from M8) | Sparkle License (permissive, MIT-style) |

## Local transcription (Voxi fork)

### Voxtral Mini 4B Realtime 2602 (model weights)
- Not in-repo: downloaded at first run to the Hugging Face cache
  (`mlx-community/Voxtral-Mini-4B-Realtime-6bit`, a quantised conversion of
  `mistralai/Voxtral-Mini-4B-Realtime-2602`).
- Copyright: Mistral AI
- License: Apache License 2.0

### voxmlx
- Python package installed into the server venv (not in-repo). `server/stream_session.py`
  adapts its realtime streaming loop.
- Copyright (c) 2026 Awni Hannun
- License: MIT — github.com/awni/voxmlx

### MLX, mistral-common, soundfile, numpy
- Python dependencies of the server venv (not in-repo).
- MLX: MIT (Apple). mistral-common: Apache 2.0 (Mistral AI). soundfile: BSD-3. numpy: BSD-3.

### KeyboardShortcuts (vendored, modified)
- `Vendor/KeyboardShortcuts/` is a copy of github.com/sindresorhus/KeyboardShortcuts
  with the `#Preview` blocks removed from `Recorder.swift` so it builds with
  Command Line Tools only. License: MIT — see `Vendor/KeyboardShortcuts/license`.

## Trademarks

"Google", the Google logo, the Gemini spark, and related marks are trademarks of
Google LLC. This repository ships no Google logo assets; the app icon and menu bar
glyph are original works.
