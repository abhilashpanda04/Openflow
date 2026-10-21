#!/usr/bin/env bash
set -euo pipefail

# Openflow One-Line Installer for macOS
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/abhilashpanda04/Openflow/main/install.sh | bash
#   or
#   curl -fsSL https://abhilashpanda04.github.io/Openflow/install.sh | bash

# Terminal Colors
BOLD='\033[1m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "   ____                   __ _                 "
echo "  / __ \____  ___  ____  / // /___ _      __    "
echo " / / / / __ \/ _ \/ __ \/ // // __ \ | /| / /    "
echo "/ /_/ / /_/ /  __/ / / /_  _// /_/ / |/ |/ /     "
echo "\____/ .___/\___/_/ /_/ /_/  \____/|__/|__/      "
echo "    /_/                                         "
echo -e "${NC}"
echo -e "${BOLD}Supercharged On-Device Voice Dictation for macOS${NC}\n"

# 1. OS check
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
  echo -e "${RED}Error: Openflow requires macOS.${NC}"
  echo "Current operating system: $OS"
  exit 1
fi

# 2. Architecture check
ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
  echo -e "${YELLOW}Warning: Openflow is optimized for Apple Silicon (M1/M2/M3/M4).${NC}"
  echo "Detected architecture: $ARCH"
fi

# 3. macOS Version check
SW_VERS="$(sw_vers -productVersion 2>/dev/null || echo '0')"
MAJOR_VERS="$(echo "$SW_VERS" | cut -d. -f1)"
if [ "$MAJOR_VERS" -lt 14 ]; then
  echo -e "${YELLOW}Warning: Openflow requires macOS 14.0 (Sonoma) or later for CoreML WhisperKit.${NC}"
  echo "Current version: $SW_VERS"
fi

TMP_DIR="$(mktemp -d -t openflow-install-XXXXXX)"
cleanup() {
  if [ -d "$TMP_DIR" ]; then
    if mount | grep -q "/Volumes/Openflow"; then
      hdiutil detach "/Volumes/Openflow" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

DMG_URL="https://github.com/abhilashpanda04/Openflow/releases/latest/download/Openflow.dmg"
DMG_FILE="$TMP_DIR/Openflow.dmg"

echo -e "${BLUE}==>${NC} ${BOLD}Downloading latest Openflow release...${NC}"
if command -v curl >/dev/null 2>&1; then
  curl -fL --progress-bar "$DMG_URL" -o "$DMG_FILE"
else
  echo -e "${RED}Error: curl is required.${NC}"
  exit 1
fi

echo -e "${BLUE}==>${NC} ${BOLD}Mounting disk image...${NC}"
MOUNT_OUT="$(hdiutil attach -nobrowse -readonly "$DMG_FILE" 2>/dev/null)"
MOUNT_DIR="$(echo "$MOUNT_OUT" | grep "/Volumes/Openflow" | head -n1 | awk '{print $NF}' || echo "/Volumes/Openflow")"

if [ ! -d "$MOUNT_DIR/Openflow.app" ]; then
  # Fallback check for /Volumes/Openflow
  if [ -d "/Volumes/Openflow/Openflow.app" ]; then
    MOUNT_DIR="/Volumes/Openflow"
  else
    echo -e "${RED}Error: Openflow.app not found inside DMG.${NC}"
    exit 1
  fi
fi

echo -e "${BLUE}==>${NC} ${BOLD}Installing Openflow into /Applications...${NC}"
if pgrep -x "Openflow" >/dev/null 2>&1; then
  echo -e "   Closing currently running Openflow..."
  killall Openflow 2>/dev/null || true
  sleep 1
fi

rm -rf "/Applications/Openflow.app"
cp -R "$MOUNT_DIR/Openflow.app" "/Applications/Openflow.app"

echo -e "${BLUE}==>${NC} ${BOLD}Configuring security attributes...${NC}"
xattr -cr "/Applications/Openflow.app" 2>/dev/null || true

echo -e "${BLUE}==>${NC} ${BOLD}Unmounting disk image...${NC}"
hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true

echo -e "\n${GREEN}✓ Openflow has been successfully installed into /Applications!${NC}\n"

echo -e "${BLUE}==>${NC} ${BOLD}Launching Openflow...${NC}"
open "/Applications/Openflow.app"

echo -e "\n${CYAN}------------------------------------------------------------${NC}"
echo -e "${BOLD}Quick Setup:${NC}"
echo -e "  1. Grant ${BOLD}Microphone${NC} and ${BOLD}Accessibility${NC} permissions when prompted."
echo -e "  2. Look for the Openflow icon in your macOS menu bar."
echo -e "  3. Hold ${BOLD}Right Option${NC} (or press ${BOLD}⌘⇧Space${NC}) and start speaking anywhere!"
echo -e "${CYAN}------------------------------------------------------------${NC}\n"
