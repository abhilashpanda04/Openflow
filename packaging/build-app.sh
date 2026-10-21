#!/usr/bin/env bash
set -euo pipefail

# Openflow .app Bundle Builder
# Creates a properly signed macOS app bundle from Swift Package Manager builds
# Usage: ./packaging/build-app.sh [debug|release] [yes|no]
#   - First arg: build configuration (default: debug)
#   - Second arg: whether to sign (default: yes)

# Configuration
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGING_DIR="$ROOT_DIR/packaging"
BUILD_CONFIG="${1:-debug}"  # debug or release
SIGN="${2:-yes}"            # yes or no

APP_NAME="Openflow"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$BUILD_CONFIG"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INFO_PLIST="$PACKAGING_DIR/Info.plist"
ENTITLEMENTS="$PACKAGING_DIR/entitlements.plist"
ICON_PATH="$PACKAGING_DIR/icon/Openflow.icns"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Openflow App Builder${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Validate configuration
if [[ "$BUILD_CONFIG" != "debug" && "$BUILD_CONFIG" != "release" ]]; then
    echo -e "${RED}Error: Build configuration must be 'debug' or 'release'${NC}"
    echo "Usage: $0 [debug|release] [yes|no]"
    exit 1
fi

if [[ "$SIGN" != "yes" && "$SIGN" != "no" ]]; then
    echo -e "${RED}Error: Sign option must be 'yes' or 'no'${NC}"
    echo "Usage: $0 [debug|release] [yes|no]"
    exit 1
fi

echo -e "${YELLOW}Configuration:${NC}"
echo "  Build config: $BUILD_CONFIG"
echo "  Code signing: $SIGN"
if [ "$SIGN" = "yes" ]; then
    echo "  Sign identity: $SIGN_IDENTITY"
fi
echo ""

# Step 1: Build Swift binary
echo -e "${YELLOW}[1/5] Building Swift binary...${NC}"
swift build -c "$BUILD_CONFIG"

SWIFT_BIN_DIR="$(swift build --show-bin-path -c "$BUILD_CONFIG" 2>/dev/null || true)"
BINARY_PATH=""
if [ -n "$SWIFT_BIN_DIR" ] && [ -x "$SWIFT_BIN_DIR/$APP_NAME" ]; then
    BINARY_PATH="$SWIFT_BIN_DIR/$APP_NAME"
elif [ -x "$BUILD_DIR/$APP_NAME" ]; then
    BINARY_PATH="$BUILD_DIR/$APP_NAME"
else
    BINARY_PATH="$(find "$ROOT_DIR/.build" -type f -name "$APP_NAME" -perm +111 2>/dev/null | grep -i "$BUILD_CONFIG" | head -n 1)"
fi

if [ -z "$BINARY_PATH" ] || [ ! -x "$BINARY_PATH" ]; then
    echo -e "${RED}Error: Build failed, binary not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Binary built: $BINARY_PATH${NC}"
echo ""

# Step 2: Create .app bundle structure
echo -e "${YELLOW}[2/5] Creating .app bundle structure...${NC}"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo -e "${GREEN}✓ Bundle directories created${NC}"
echo ""

# Step 3: Copy files into bundle
echo -e "${YELLOW}[3/5] Copying files into bundle...${NC}"

# Copy binary
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo "  ✓ Binary copied"

# Copy Info.plist
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

# Update version if git tag exists
VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.1.0-dev")
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
echo "  ✓ Info.plist copied (version: $VERSION, build: $BUILD_NUMBER)"

# Generate icon if needed
if [ ! -f "$ICON_PATH" ]; then
    echo "  Generating app icon..."
    "$PACKAGING_DIR/generate_icon.sh" > /dev/null 2>&1
fi
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/Openflow.icns"
echo "  ✓ Icon copied"

# Copy Sparkle Framework
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build" -name "Sparkle.framework" -type d | head -n 1)"
if [ -n "$SPARKLE_FRAMEWORK" ] && [ -d "$SPARKLE_FRAMEWORK" ]; then
    cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
    echo "  ✓ Sparkle.framework copied"
fi

echo -e "${GREEN}✓ All files copied into bundle${NC}"
echo ""

# Step 4: Code sign with entitlements
if [ "$SIGN" = "yes" ]; then
    echo -e "${YELLOW}[4/5] Signing app bundle...${NC}"
    
    if [ "$SIGN_IDENTITY" = "-" ]; then
        echo "  Using ad-hoc signature (for local testing only)"
    else
        echo "  Using identity: $SIGN_IDENTITY"
    fi

    # Sign frameworks first
    if [ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]; then
        codesign --force \
            --sign "$SIGN_IDENTITY" \
            --timestamp \
            "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
        echo "  ✓ Sparkle.framework signed"
    fi
    
    # Sign the binary
    codesign --force \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        --timestamp \
        "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    echo "  ✓ Binary signed"
    
    # Sign the bundle
    codesign --force --deep \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        --timestamp \
        "$APP_BUNDLE"
    echo "  ✓ Bundle signed"
    
    # Verify signature
    echo "  Verifying signature..."
    if codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1; then
        echo -e "${GREEN}✓ Signature verified${NC}"
    else
        echo -e "${RED}✗ Signature verification failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}[4/5] Skipping code signing (as requested)${NC}"
fi

if [ -n "$SWIFT_BIN_DIR" ] && [ "$SWIFT_BIN_DIR" != "$BUILD_DIR" ]; then
    mkdir -p "$SWIFT_BIN_DIR"
    ln -sfn "$APP_BUNDLE" "$SWIFT_BIN_DIR/$APP_NAME.app" 2>/dev/null || true
fi
echo ""

# Step 5: Display bundle info
echo -e "${YELLOW}[5/5] Gathering bundle information...${NC}"

# Get app size
APP_SIZE=$(du -sh "$APP_BUNDLE" | awk '{print $1}')
echo "  Bundle size: $APP_SIZE"

# Get entitlements
if [ "$SIGN" = "yes" ]; then
    echo "  Entitlements:"
    codesign -d --entitlements - "$APP_BUNDLE" 2>/dev/null | grep -A 1 "device.microphone" > /dev/null && \
        echo "    ✓ Microphone access enabled" || \
        echo "    ✗ Microphone access not found"
    codesign -d --entitlements - "$APP_BUNDLE" 2>/dev/null | grep -A 1 "network.client" > /dev/null && \
        echo "    ✓ Network client enabled" || \
        echo "    ✗ Network client not found"
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✓ Build complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${BLUE}Bundle location:${NC}"
echo "  $APP_BUNDLE"
echo ""
echo -e "${BLUE}To run the app:${NC}"
echo "  open \"$APP_BUNDLE\""
echo ""
echo -e "${BLUE}To test microphone permissions:${NC}"
echo "  1. Run: open \"$APP_BUNDLE\""
echo "  2. Grant microphone access when prompted"
echo "  3. Check System Settings > Privacy & Security > Microphone"
echo ""

if [ "$BUILD_CONFIG" = "debug" ]; then
    echo -e "${YELLOW}Note: This is a debug build. For distribution, use:${NC}"
    echo "  $0 release yes"
    echo ""
fi
