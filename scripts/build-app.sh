#!/bin/bash
# Build Voxi.app with SwiftPM + Command Line Tools (no Xcode needed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

# Stage under .build (not a browsable folder) and install straight into
# /Applications: a second Voxi.app lying around gets indexed by Spotlight and
# launched by mistake, with its own separate permission grants (bit us once).
APP="$ROOT/.build/staging/Voxi.app"
BIN="$ROOT/.build/$CONFIG/Voxi"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Voxi"
cp App/Resources/Jot.icns "$APP/Contents/Resources/"
cp -R App/Resources/Fonts "$APP/Contents/Resources/Fonts"
cp -R App/Resources/Sounds "$APP/Contents/Resources/Sounds"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Voxi</string>
	<key>CFBundleExecutable</key><string>Voxi</string>
	<key>CFBundleIconFile</key><string>Jot</string>
	<key>CFBundleIdentifier</key><string>com.voxi.app</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>Voxi</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.2.0</string>
	<key>CFBundleVersion</key><string>3</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSMicrophoneUsageDescription</key><string>Voxi records audio while you hold the dictation key, so it can transcribe what you say — entirely on this Mac.</string>
	<key>NSHumanReadableCopyright</key><string>Based on Jot (Apache 2.0, Google LLC). Local Voxtral fork.</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key><string>com.voxi.app.url</string>
			<key>CFBundleURLSchemes</key><array><string>jot</string></array>
		</dict>
	</array>
</dict>
</plist>
PLIST

# Ad-hoc signed: no Apple account needed. macOS ties permission grants to the
# signature, so each build is a new app to it — re-grant after installing.
codesign --force --sign - --entitlements App/Jot.entitlements "$APP"

INSTALL="/Applications/Voxi.app"
# Quit a running copy so the bundle can be replaced. Every step here may
# legitimately fail (not running, not scriptable) — none may abort the install.
if pgrep -x Voxi >/dev/null; then
  osascript -e 'tell application "Voxi" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x Voxi 2>/dev/null || true
fi
rm -rf "$INSTALL"
ditto "$APP" "$INSTALL"
rm -rf "$ROOT/.build/staging"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL" >/dev/null 2>&1 || true
echo "Installed $INSTALL"
echo "New build = new app to macOS: re-grant Accessibility and Microphone (remove the old Voxi rows first)."
