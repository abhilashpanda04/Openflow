#!/usr/bin/env bash
set -euo pipefail

# Openflow DMG Creator
# Creates a distributable DMG (app only, no bundled backend)
# Prerequisites: Release build must exist (run 'make release' first)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
echo "Openflow DMG Creator (App Only)"
echo "========================================="
echo ""

# Check if release build exists
if [ ! -d "$RELEASE_APP_BUNDLE" ]; then
  echo "Error: Release .app bundle not found."
  echo "Run 'make release' or './packaging/build-app.sh release yes' first."
  exit 1
fi

echo "Step 1: Preparing distribution directory..."
rm -rf "$APP_BUNDLE" "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DIST_DIR"

# Copy the pre-built .app bundle
echo "  Copying release .app bundle..."
cp -R "$RELEASE_APP_BUNDLE" "$APP_BUNDLE"
echo "  ✓ App bundle copied"

echo ""
echo "Step 2: Bundling backend source code..."
BACKEND_RESOURCES="$APP_BUNDLE/Contents/Resources/backend"
mkdir -p "$BACKEND_RESOURCES"
echo "  Copying backend source files..."
cp "$ROOT_DIR/services/backend/qwen_server.py" "$BACKEND_RESOURCES/"
cp "$ROOT_DIR/services/backend/app.py" "$BACKEND_RESOURCES/"
cp "$ROOT_DIR/services/backend/pyproject.toml" "$BACKEND_RESOURCES/"
echo "  ✓ Backend source bundled (qwen_server.py, app.py, pyproject.toml)"

echo ""
echo "Step 3: Re-signing app bundle..."
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
echo "  ✓ Backend source code (qwen_server.py, app.py, pyproject.toml)"
echo "  ✓ Applications symlink"
echo ""
echo "Note: Backend dependencies and models NOT bundled."
echo "App will auto-install Python (if needed) and dependencies on first launch."
echo ""
echo "Next steps:"
echo "  1. Test the DMG: open dist/Openflow.dmg"
echo "  2. Drag app to Applications"
echo "  3. Launch - app will auto-install dependencies (~15-25 min first time)"
echo "  4. Grant microphone access when prompted"
echo ""
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "Note: This DMG uses ad-hoc signing."
  echo "For distribution, set CODESIGN_IDENTITY and NOTARY_PROFILE."
fi
