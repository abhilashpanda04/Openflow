# Openflow

<p align="center">
  <img src="assets/logo.svg" alt="Openflow logo" width="140" />
</p>

<p align="center">
  <a href="https://github.com/abhilashpanda04/Openflow/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/abhilashpanda04/Openflow"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2013%2B-black">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5.9%2B-orange">
  <img alt="License" src="https://img.shields.io/badge/license-Apache%202.0-blue">
</p>

Openflow is an open-source macOS menu bar application for low-friction speech-to-text. It captures microphone audio, sends it to an ASR backend, and returns transcript output to the clipboard or directly into the active application.

## Overview

Openflow is designed for users who need quick dictation without switching context. The app runs in the menu bar, supports a global hotkey workflow, and provides backend readiness visibility so transcription state is clear before recording begins.

## Key Capabilities

- Global hotkey recording control (`Cmd+Shift+Space` by default).
- Menu bar backend actions (`Start`, `Stop`, `Retry`, `Refresh`).
- Readiness and warm-up state tracking with user-visible status.
- Output routing to clipboard, active app, both, or none.
- Support for both managed local backend and external backend URL modes.

## Installation

### Option 1: Download a release build

Download the latest packaged build from GitHub Releases:

- https://github.com/abhilashpanda04/Openflow/releases/latest

### Option 2: Build from source

**Quick start:**
```bash
# Build debug .app with microphone permissions
make debug

# Run the app
open .build/arm64-apple-macosx/debug/Openflow.app
```

When the app launches, grant **Microphone** access when prompted by macOS.

**Full development setup:**
```bash
# Install dependencies
make install-deps

# Build and test microphone permissions
make test-mic

# Set up backend (in a separate terminal)
make backend
```

**Available build targets:**
```bash
make debug      # Quick debug build for testing
make release    # Optimized release build
make dmg        # Create distributable DMG
make clean      # Clean build artifacts
make help       # Show all available targets
```

## System Requirements

- macOS 13 or later
- Swift 5.9 or later (source builds)
- Local ASR backend reachable at configured backend URL

## Architecture At A Glance

- `Sources/OpenflowMac` - Swift macOS app source
- `services/backend` - Python ASR backend service
- `packaging/` - DMG/build scripts and app metadata
- `assets/` - repository assets (logo and visuals)

At runtime, the app communicates with a backend endpoint (`/health`, `/transcribe`) and can either manage a local backend process or monitor readiness for an externally managed backend.

## Backend (Local)

The repo includes a Python ASR backend in `services/backend`.

**Quick start with Makefile:**
```bash
make backend
```

**Manual setup:**
```bash
cd services/backend
python3 -m venv .venv
source .venv/bin/activate
./.venv/bin/pip install -e .
./.venv/bin/python qwen_server.py
```

Once running, the backend listens at `http://127.0.0.1:8001`. Keep the Openflow app pointed at this URL in Settings.

## Settings

Openflow is configured from the app menu: `Openflow` -> `Settings...`.

Key settings users can control:

- **Backend URL**: connect to a local backend or an external backend endpoint.
- **Output Mode**: choose where transcripts go (`Clipboard`, `Active App`, `Both`, or `None`).
- **Global Hotkey**: set your preferred key combination for start/stop recording.
- **API Token**: add a backend token when your server requires authenticated requests.
- **Request Timeout and Retry**: adjust request timeout and retry behavior for slower networks or backends.
- **Max Upload Size**: set the allowed audio upload limit per recording.

Settings are applied immediately after save.

## Open-Source Project Docs

- Contribution guide: `CONTRIBUTING.md`
- Security policy: `SECURITY.md`
- Third-party notices: `THIRD_PARTY_NOTICES.md`
- Citation metadata: `CITATION.cff`

## Model Attribution

Openflow can be used with the Qwen ASR model family. For `Qwen/Qwen3-ASR-1.7B`, see:

- Model page: `https://huggingface.co/Qwen/Qwen3-ASR-1.7B`
- License: Apache-2.0
- Research citation: `Qwen3-ASR Technical Report (arXiv:2601.21337)`

## Privacy And Data Handling

Openflow is designed for local-first usage with a user-configurable backend URL. Transcript handling depends on the backend you run or connect to; review your backend deployment and retention settings before production use.

## License

This project is licensed under the Apache License 2.0. See `LICENSE`.
