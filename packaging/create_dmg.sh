#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/../backend"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Openflow"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_STAGING="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
BIN_PATH="$ROOT_DIR/.build/arm64-apple-macosx/release/$APP_NAME"
ICON_PATH="$ROOT_DIR/packaging/icon/Openflow.icns"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [ ! -x "$BIN_PATH" ]; then
  echo "Release binary not found. Run: swift build -c release"
  exit 1
fi

if [ ! -x "$BACKEND_DIR/.venv/bin/python3" ]; then
  echo "Backend runtime missing at backend/.venv/bin/python3"
  exit 1
fi

PYTHON_HOME_BIN="$(awk -F' = ' '/^home = / { print $2 }' "$BACKEND_DIR/.venv/pyvenv.cfg" || true)"
if [ -z "$PYTHON_HOME_BIN" ]; then
  echo "Could not resolve Python home from backend/.venv/pyvenv.cfg"
  exit 1
fi

PYTHON_HOME_ROOT="$(cd "$(dirname "$PYTHON_HOME_BIN")" && pwd)"
if [ ! -x "$PYTHON_HOME_ROOT/bin/python3" ]; then
  echo "Python home missing executable: $PYTHON_HOME_ROOT/bin/python3"
  exit 1
fi

SITE_PACKAGES_DIR=""
for candidate in "$BACKEND_DIR/.venv"/lib/python*/site-packages; do
  if [ -d "$candidate" ]; then
    SITE_PACKAGES_DIR="$candidate"
    break
  fi
done

if [ -z "$SITE_PACKAGES_DIR" ]; then
  echo "Could not locate site-packages in backend/.venv/lib/python*/site-packages"
  exit 1
fi

rm -rf "$APP_BUNDLE" "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/backend-runtime"

if [ ! -f "$ICON_PATH" ]; then
  "$ROOT_DIR/packaging/generate_icon.sh"
fi

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/Openflow.icns"

# Bundle a relocatable runtime layout:
# - full Python home (stdlib + interpreter)
# - backend site-packages
# - backend entrypoint
rsync -aL --delete "$PYTHON_HOME_ROOT/" "$APP_BUNDLE/Contents/Resources/backend-runtime/python-home/"
rsync -aL --delete "$SITE_PACKAGES_DIR/" "$APP_BUNDLE/Contents/Resources/backend-runtime/site-packages/"
cp "$BACKEND_DIR/qwen_server.py" "$APP_BUNDLE/Contents/Resources/backend-runtime/"

if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "Signing app ad-hoc (set CODESIGN_IDENTITY for Developer ID signing)..."
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  echo "Signing app with identity: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

if [ "$SIGN_IDENTITY" != "-" ]; then
  echo "Signing DMG with identity: $SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [ -n "$NOTARY_PROFILE" ]; then
  echo "Submitting DMG for notarization using profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler staple "$DMG_PATH"
fi

echo "Created DMG at: $DMG_PATH"
