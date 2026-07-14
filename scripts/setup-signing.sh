#!/bin/bash
# Creates a stable, self-signed code-signing certificate named "Lumen Dev".
#
# Why: an ad-hoc signature (codesign -s -) changes on every build, so macOS
# treats each rebuild as a brand-new app and forgets granted permissions
# (Screen Recording, Accessibility, …). Signing with a fixed certificate keeps
# the app's identity stable, so you grant permissions ONCE and they stick.
#
# Run this once. The login keychain must be unlocked (it is during a normal
# session). Then rebuild with ./make-app.sh.
set -e
CERT_NAME="Lumen Dev"

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "Valid signing identity '$CERT_NAME' already exists — nothing to do."
    exit 0
fi

# Remove any earlier broken attempt.
security delete-certificate -c "$CERT_NAME" -t "$KEYCHAIN" 2>/dev/null || true

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Self-signed cert with the key-usage flags macOS requires for code signing.
cat > "$TMP/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Lumen Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/openssl.cnf" 2>/dev/null

openssl pkcs12 -export -out "$TMP/lumen.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:lumen 2>/dev/null

# -A lets codesign use the key without repeated keychain prompts.
security import "$TMP/lumen.p12" -k "$KEYCHAIN" -P lumen -T /usr/bin/codesign -A

# Trust the cert for code signing (user domain; no sudo).
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>/dev/null || true

echo "Created stable signing identity '$CERT_NAME'."
echo "Now run: ./make-app.sh"
