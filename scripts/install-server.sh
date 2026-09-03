#!/bin/bash
# Install the Voxtral server runtime into ~/Library/Application Support/Voxi
# (outside TCC-protected folders, so the app can start it without a Files
# permission prompt).
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Library/Application Support/Voxi"
mkdir -p "$DEST"
cp "$SRC/server/voxi_server.py" "$DEST/"
if [ ! -x "$DEST/venv/bin/python" ]; then
  python3 -m venv "$DEST/venv"
fi
"$DEST/venv/bin/pip" -q install --upgrade voxmlx
cat > "$DEST/server.sh" <<'RUN'
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${VOXI_PORT:-48765}"
if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  exit 0
fi
exec "$DIR/venv/bin/python" "$DIR/voxi_server.py"
RUN
chmod +x "$DEST/server.sh"
echo "Installed server runtime to $DEST"
