# Openflow

Openflow is a macOS Swift app that toggles recording with a global hotkey and transcribes audio through a local Qwen ASR server.

Implementation notes for backend startup UX are tracked in `BACKEND_UX_IMPLEMENTATION.md`.

## Hotkey

- `Cmd+Shift+Space` toggles start/stop recording globally.

## What it does

- Starts/stops microphone recording from a menu-bar app.
- Sends WAV audio to local backend: `http://127.0.0.1:8001/transcribe`.
- Shows transcript in a small floating panel.
- Copies transcript to clipboard automatically.

## 1) Start Qwen backend

Openflow can start the backend for you from the menu bar:

- Open the app menu and click `Start Backend`.
- During first load, Openflow shows `Preparing speech engine` and polls readiness.
- When model warm-up finishes, you'll get `Openflow is ready` and recording becomes available.
- Warm-up status shows elapsed time so users know the app is still progressing.

If `Backend URL` points to an external host (not localhost/127.0.0.1), Openflow switches to manual mode:

- `Start Backend` becomes a readiness watcher (it does not spawn a process).
- Start your backend manually at that URL, and Openflow will mark itself ready once `/health` reports `model_loaded=true`.

If you prefer manual startup, from `backend/`:

```bash
uv run python qwen_server.py
# or
./.venv/bin/python qwen_server.py
```

Notes:

- On Apple Silicon, server uses `mps` + `float16` automatically.
- On Intel/no-MPS, server falls back to `cpu` + `float32`.

## 2) Run Swift app

From `mac-app/`:

```bash
swift build
swift run Openflow
```

Grant microphone access when macOS prompts.

## Runtime configuration

The app reads optional environment variables at startup:

- `QUICKASR_BACKEND_URL` (default: `http://127.0.0.1:8001`)
- `QUICKASR_TIMEOUT_SECONDS` (default: `45`)
- `QUICKASR_RETRY_COUNT` (default: `2`)
- `QUICKASR_RETRY_BASE_DELAY_MS` (default: `250`)
- `QUICKASR_AUTO_COPY` (`true`/`false`, default: `true`)
- `QUICKASR_OUTPUT_MODE` (`clipboard`, `active-app`, `both`, `none`)
- `QUICKASR_HOTKEY` (default: `Cmd+Shift+Space`, examples: `cmd+option+r`, `cmd+shift+space`)
- `QUICKASR_API_TOKEN` (optional, sent as `X-API-Token`)
- `QUICKASR_MAX_UPLOAD_BYTES` (default: `26214400`)

When using `QUICKASR_OUTPUT_MODE=active-app` or `both`, Openflow pastes transcript text into the app that was focused when recording started.
macOS Accessibility permission may be required for simulated paste (`Cmd+V`).

## User settings

- Open `Settings...` from the menu bar app menu.
- Users can configure backend URL, output mode, hotkey, token, timeout/retry, and upload size.
- Saved settings apply immediately (hotkey is re-registered after save).
- Environment variables still override saved settings.

At startup the app probes backend health and surfaces readiness in the status menu.
Use `Start Backend`, `Stop Backend`, or `Refresh Backend Status` from the menu to control and re-check backend readiness.
For external URLs, `Stop Backend` is disabled because Openflow does not own that process.

If recording is requested before backend warm-up completes, Openflow queues the action and starts recording automatically once backend health reports ready.
