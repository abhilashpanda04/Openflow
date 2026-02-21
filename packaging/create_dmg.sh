#!/usr/bin/env bash
set -euo pipefail

# Openflow DMG Creator
# Creates a distributable DMG with bundled Python backend
# Prerequisites: Release build must exist (run 'make release' first)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/services/backend"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Openflow"
RELEASE_APP_BUNDLE="$ROOT_DIR/.build/arm64-apple-macosx/release/$APP_NAME.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_STAGING="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ENTITLEMENTS="$ROOT_DIR/packaging/entitlements.plist"

echo "========================================="
echo "Openflow DMG Creator"
echo "========================================="
echo ""

# Check if release build exists
if [ ! -d "$RELEASE_APP_BUNDLE" ]; then
  echo "Error: Release .app bundle not found."
  echo "Run 'make release' or './packaging/build-app.sh release yes' first."
  exit 1
fi

if [ ! -x "$BACKEND_DIR/.venv/bin/python3" ]; then
  echo "Error: Backend runtime missing at $BACKEND_DIR/.venv/bin/python3"
  echo "Set up the backend first:"
  echo "  cd services/backend"
  echo "  python3 -m venv .venv"
  echo "  .venv/bin/pip install -e ."
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

echo "Step 1: Preparing distribution directory..."
rm -rf "$APP_BUNDLE" "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DIST_DIR"

# Copy the pre-built .app bundle
echo "  Copying release .app bundle..."
cp -R "$RELEASE_APP_BUNDLE" "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/Resources/backend-runtime"
echo "  ✓ App bundle copied"

echo ""
echo "Step 2: Bundling Python backend runtime..."
# Bundle a relocatable runtime layout:
# - full Python home (stdlib + interpreter)
# - backend site-packages
# - backend entrypoint
echo "  Copying Python home from: $PYTHON_HOME_ROOT"
rsync -aL --delete "$PYTHON_HOME_ROOT/" "$APP_BUNDLE/Contents/Resources/backend-runtime/python-home/"
echo "  ✓ Python home bundled"

echo "  Copying site-packages from: $SITE_PACKAGES_DIR"
rsync -aL --delete "$SITE_PACKAGES_DIR/" "$APP_BUNDLE/Contents/Resources/backend-runtime/site-packages/"
echo "  ✓ Site packages bundled"

echo "  Copying backend scripts..."
cp "$BACKEND_DIR/qwen_server.py" "$APP_BUNDLE/Contents/Resources/backend-runtime/"
echo "  ✓ Backend runtime complete"

echo ""
echo "Step 3: Re-signing app bundle with backend..."
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "  Signing with ad-hoc signature (for local testing)"
  echo "  Set CODESIGN_IDENTITY for Developer ID signing"
  codesign --force --deep \
    --entitlements "$ENTITLEMENTS" \
    --sign - \
    "$APP_BUNDLE"
else
  echo "  Signing with identity: $SIGN_IDENTITY"
  codesign --force --deep \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"
fi

echo "  Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "  ✓ Signature verified"

echo ""
echo "Step 4: Creating DMG..."
mkdir -p "$DMG_STAGING"
echo "  Staging app bundle..."
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
echo "  ✓ DMG staging ready"

echo "  Creating disk image..."
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" > /dev/null
echo "  ✓ DMG created"

echo ""
echo "Step 5: Signing DMG..."
if [ "$SIGN_IDENTITY" != "-" ]; then
  echo "  Signing DMG with identity: $SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
  echo "  ✓ DMG signed"
else
  echo "  Skipping DMG signing (ad-hoc signature)"
fi

if [ -n "$NOTARY_PROFILE" ]; then
  echo ""
  echo "Step 6: Notarizing DMG..."
  echo "  Submitting for notarization (this may take several minutes)..."
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "  Stapling notarization ticket to app..."
  xcrun stapler staple "$APP_BUNDLE"
  echo "  Stapling notarization ticket to DMG..."
  xcrun stapler staple "$DMG_PATH"
  echo "  ✓ Notarization complete"
fi

DMG_SIZE=$(du -sh "$DMG_PATH" | awk '{print $1}')

echo ""
echo "========================================="
echo "✓ DMG Creation Complete!"
echo "========================================="
echo ""
echo "DMG Location:"
echo "  $DMG_PATH"
echo ""
echo "DMG Size: $DMG_SIZE"
echo ""
echo "Contents:"
echo "  ✓ Openflow.app (signed)"
echo "  ✓ Bundled Python backend runtime"
echo "  ✓ Applications symlink"
echo ""
echo "Next steps:"
echo "  1. Test the DMG: open dist/Openflow.dmg"
echo "  2. Drag app to Applications"
echo "  3. Launch and grant permissions"
echo ""
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "Note: This DMG uses ad-hoc signing."
  echo "For distribution, set CODESIGN_IDENTITY and NOTARY_PROFILE."
fi
