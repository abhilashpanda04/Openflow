# Contributing to Openflow

Thanks for contributing.

## Development Setup

**Requirements:**
- macOS 13+
- Swift 5.9+
- Python 3.12+ (for the backend)
- Xcode Command Line Tools

### Quick Start

**1. Install dependencies:**
```bash
make install-deps
```

**2. Build debug app:**
```bash
make debug
```

**3. Run backend (in a separate terminal):**
```bash
make backend
```

**4. Launch app and test:**
```bash
make test-mic
```

### Build System

The project uses a Makefile-based build system:

```bash
make help           # Show all available targets
make debug          # Build debug .app with proper entitlements
make release        # Build optimized release .app
make dmg            # Create distributable DMG
make clean          # Clean all build artifacts
make verify-signature  # Verify code signature
make info           # Show build environment info
```

### Manual Build

**macOS app:**
```bash
# Build Swift app
swift build -c debug

# Create .app bundle with entitlements
./packaging/build-app.sh debug yes

# Launch
open .build/arm64-apple-macosx/debug/Openflow.app
```

**Backend:**
```bash
cd services/backend
python3 -m venv .venv
source .venv/bin/activate
./.venv/bin/pip install -e .
./.venv/bin/python qwen_server.py
```

### Troubleshooting

**Microphone permission issues:**
- The app must be signed with proper entitlements (`packaging/entitlements.plist`)
- Use `make debug` instead of `swift build` to ensure entitlements are applied
- Check System Settings > Privacy & Security > Microphone

**Backend not starting:**
- Ensure Python 3.12+ is installed: `python3 --version`
- Check backend logs in terminal
- Verify backend is listening: `curl http://127.0.0.1:8001/health`

**Build failures:**
- Clean build artifacts: `make clean`
- Verify Xcode is installed: `xcodebuild -version`
- Check Swift version: `swift --version`

## Pull Request Guidelines

- Keep changes focused and minimal.
- Follow existing naming and file conventions.
- Update docs when behavior or configuration changes.
- Include validation notes in the PR description (`swift build`, smoke checks, etc.).

## Reporting Issues

When reporting a bug, include:

- macOS version
- app version/commit SHA
- reproduction steps
- expected vs actual behavior
- relevant logs (without secrets)
