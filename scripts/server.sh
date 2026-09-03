#!/bin/bash
# Start the local Voxtral transcription server (idempotent — exits if already running).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${VOXI_PORT:-48765}"
if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  echo "voxi-server already running on port ${PORT}"
  exit 0
fi
exec "$ROOT/server/.venv/bin/python" "$ROOT/server/voxi_server.py"
