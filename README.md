# Openflow

<p align="center">
  <img src="assets/logo.svg" alt="Openflow logo" width="140" />
</p>

Openflow is a macOS menu bar app for fast speech-to-text. It records from your microphone, sends audio to a local ASR backend, and returns transcript text to clipboard or the active app.

## Highlights

- Global hotkey start/stop recording (`Cmd+Shift+Space` by default).
- Backend lifecycle controls directly in the menu bar (`Start`, `Stop`, `Retry`, `Refresh`).
- Warm-up UX with readiness states and progress feedback.
- Supports managed local backend and external backend URL modes.
- Packaging flow for `.app` and `.dmg` distribution.

## Project Structure

- `Sources/OpenflowMac` - Swift macOS app source.
- `packaging/` - DMG/build packaging scripts and metadata.
- `assets/` - repository assets (logo, visuals for docs).

## Quick Start

From `mac-app/`:

```bash
swift build
swift run Openflow
```

When prompted, grant Microphone access in macOS.

## Backend Startup

Openflow can start the backend for you from the menu:

- Click `Start Backend`.
- Openflow tracks readiness via `/health`.
- Once loaded, you will see `Openflow is ready`.

Bundled runtime layout used by packaged app:

```text
<App Resources>/backend-runtime/
  bin/python3
  qwen_server.py
```

If bundled runtime is unavailable (dev mode), Openflow falls back to local launchers (`uv` then `backend/.venv/bin/python`).

If `Backend URL` points to an external host, Openflow does not manage the process and instead waits for readiness.

## Environment Variables

Openflow reads these optional environment variables at startup:

- `OPENFLOW_BACKEND_URL` (default: `http://127.0.0.1:8001`)
- `OPENFLOW_TIMEOUT_SECONDS` (default: `45`)
- `OPENFLOW_RETRY_COUNT` (default: `2`)
- `OPENFLOW_RETRY_BASE_DELAY_MS` (default: `250`)
- `OPENFLOW_AUTO_COPY` (`true`/`false`, default: `true`)
- `OPENFLOW_OUTPUT_MODE` (`clipboard`, `active-app`, `both`, `none`)
- `OPENFLOW_HOTKEY` (default: `Cmd+Shift+Space`)
- `OPENFLOW_API_TOKEN` (optional, sent as `X-API-Token`)
- `OPENFLOW_MAX_UPLOAD_BYTES` (default: `26214400`)

## Packaging

From `mac-app/`:

```bash
swift build -c release
./packaging/create_dmg.sh
```

Optional signing/notarization inputs:

- `CODESIGN_IDENTITY`: Developer ID Application certificate name.
- `NOTARY_PROFILE`: profile configured for `xcrun notarytool`.

Example:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="openflow-notary" \
./packaging/create_dmg.sh
```
