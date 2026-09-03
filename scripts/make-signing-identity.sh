#!/bin/bash
# Create a local code-signing identity so Voxi keeps its macOS permissions
# across rebuilds.
#
# Why: an ad-hoc-signed app is identified by the hash of its binary, so every
# rebuild is a brand-new app to macOS — the Accessibility and Microphone grants
# you gave the previous build silently stop applying, while the old row still
# sits in System Settings looking granted. Signing with a stable (self-signed)
# certificate ties the grants to the certificate instead, so they survive.
#
# Run once. Safe to re-run (does nothing if the identity exists). macOS will
# ask for your login password once, to trust the certificate for code signing.
# Nothing leaves your Mac; the certificate is only ever used by codesign here.
set -euo pipefail

NAME="Voxi Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Identity \"$NAME\" already exists and is valid — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

echo "Creating certificate \"$NAME\" (valid 10 years)…"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout key.pem -out cert.pem -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1

# -legacy is needed on OpenSSL 3 for a p12 that macOS's `security` can read.
openssl pkcs12 -export -out id.p12 -inkey key.pem -in cert.pem -passout pass:voxi -legacy 2>/dev/null \
  || openssl pkcs12 -export -out id.p12 -inkey key.pem -in cert.pem -passout pass:voxi

echo "Importing into your login keychain…"
security import id.p12 -k "$KEYCHAIN" -P voxi -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "Trusting it for code signing (macOS will ask for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" cert.pem

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo
  echo "Done. Now run ./scripts/build-app.sh — it will sign with \"$NAME\"."
  echo "Grant Accessibility and Microphone one final time; future rebuilds keep them."
else
  echo "The identity was created but is not showing as valid." >&2
  echo "Open Keychain Access → login → My Certificates → \"$NAME\" → Trust → Code Signing: Always Trust, then re-run." >&2
  exit 1
fi
