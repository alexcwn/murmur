#!/bin/bash
# Creates a stable self-signed code signing identity in the login keychain.
#
# Why this exists: macOS keys Accessibility / Input Monitoring / Microphone
# grants to bundle ID *and* code signature. Ad-hoc signing (`codesign -s -`)
# produces a new signature on every build, so every rebuild silently drops your
# permissions and you re-approve in System Settings forever. Signing with one
# stable identity means you approve once.
#
# Run once. macOS will ask for your login password to trust the certificate.
set -euo pipefail

CERT_NAME="${1:-Murmur Dev}"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
	echo "✓ Code signing identity '$CERT_NAME' already exists."
	exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▸ Generating certificate '$CERT_NAME'…"

# extendedKeyUsage=codeSigning is the part that makes codesign accept it;
# basicConstraints CA:true lets it be its own root.
cat > "$WORK/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $CERT_NAME

[ ext ]
basicConstraints       = critical,CA:true
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
	-keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
	-config "$WORK/openssl.cnf" 2>/dev/null

# Apple's importer rejects OpenSSL 3's defaults: it can't read a SHA-256 MAC or
# AES-based PBE, and an empty password makes the MAC check fail outright
# ("MAC verification failed during PKCS12 import"). Pin the legacy SHA-1/3DES
# combination and use a real passphrase. The passphrase protects nothing here —
# the file lives in a temp dir for one second — it just has to be non-empty.
P12_PASS="murmur-transient"
openssl pkcs12 -export -legacy \
	-macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES \
	-inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-out "$WORK/bundle.p12" -passout "pass:$P12_PASS" 2>/dev/null

echo "▸ Importing into login keychain…"
security import "$WORK/bundle.p12" \
	-k "$KEYCHAIN" -P "$P12_PASS" \
	-T /usr/bin/codesign -T /usr/bin/security >/dev/null

# Optional: pre-authorize codesign to use the key without a GUI prompt. Needs
# your login password, so it's opt-in:  LOGIN_PASSWORD=… ./scripts/make-cert.sh
# Skipping it just means one "Always Allow" click on your first build.
if [ -n "${LOGIN_PASSWORD:-}" ]; then
	security set-key-partition-list \
		-S apple-tool:,apple:,codesign: -s -k "$LOGIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 \
		&& echo "▸ Pre-authorized codesign for this key." \
		|| echo "⚠ Could not set the key partition list; expect one keychain prompt."
fi

echo "▸ Marking it trusted for code signing (macOS will ask for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
	echo "✓ '$CERT_NAME' is ready. Run: make run"
	echo "  (The first build may show one keychain prompt — click 'Always Allow'.)"
else
	cat <<EOF
⚠ The certificate was imported but isn't showing as a valid identity yet.

Open Keychain Access → login → Certificates → "$CERT_NAME",
double-click it, expand "Trust", set "Code Signing" to "Always Trust",
then re-run: security find-identity -v -p codesigning
EOF
fi
