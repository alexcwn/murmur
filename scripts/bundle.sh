#!/bin/bash
# Assembles Sources/ into a real Murmur.app and signs it.
#
# Stands in for Xcode's build phases until Xcode is installed. Everything here
# works with Command Line Tools alone.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP_NAME="Murmur"
IDENTITY="${CODESIGN_IDENTITY:-Murmur Dev}"

BUILD_DIR="$ROOT/.build/$CONFIG"
APP="$ROOT/.build/$APP_NAME.app"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Bundled faces — ATSApplicationFontsPath points at Contents/Resources/Fonts.
if [ -d "$ROOT/Resources/Fonts" ]; then
	mkdir -p "$APP/Contents/Resources/Fonts"
	cp "$ROOT/Resources/Fonts/"*.ttf "$APP/Contents/Resources/Fonts/"
fi

# CFBundleIconFile is declared in Info.plist; regenerate with scripts/make-icon.swift
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
	cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
	echo "  (no AppIcon.icns — run: swift scripts/make-icon.swift)"
fi

echo "▸ Signing as '$IDENTITY'…"
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
	cat >&2 <<EOF

  No code signing identity named "$IDENTITY".

  Run  ./scripts/make-cert.sh  first. Without a stable identity, macOS will
  drop this app's Accessibility and Input Monitoring grants on every rebuild.

EOF
	exit 1
fi

codesign --force --deep \
	--options runtime \
	--entitlements "$ROOT/Resources/$APP_NAME.entitlements" \
	--sign "$IDENTITY" \
	"$APP"

codesign --verify --verbose=2 "$APP"

echo "▸ Built $APP"
