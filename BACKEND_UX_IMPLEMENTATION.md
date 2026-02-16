# Backend Startup UX - Implemented So Far

This document captures what has been implemented in the macOS app to support backend startup, warm-up UX, and readiness handling.

## Scope

Implemented in the Swift macOS app (`mac-app/`) for Openflow.

## Completed Features

### 1) Backend process supervisor

- Added `BackendSupervisor` in `Sources/QuickASRMac/BackendSupervisor.swift`.
- Supports managed local backend start/stop using `Process`.
- Launch strategy:
  - Preferred: `uv run python qwen_server.py`
  - Fallback: `./.venv/bin/python qwen_server.py`
- Resolves backend directory automatically and validates `qwen_server.py` exists.
- Captures backend stdout/stderr and logs lines via `NSLog`.

### 2) Backend startup state machine

- Added backend lifecycle states in `Sources/QuickASRMac/AppDelegate.swift`:
  - `notStarted`
  - `starting`
  - `warming`
  - `ready`
  - `failed(String)`
- Recording intent is queued if user starts recording before backend is ready.
- When backend becomes ready, queued recording starts automatically.

### 3) Warm-up polling and timeout behavior

- Added readiness polling (`/health`) during startup.
- Poll interval: ~1.5 seconds.
- Warm-up timeout: 180 seconds.
- Long-warmup notice after ~45 seconds.
- Readiness transitions update menu state and overlay in real time.

### 4) Menu UX improvements

- Added menu actions in `Sources/QuickASRMac/AppDelegate.swift`:
  - `Start Backend` (or `Wait for External Backend` for non-local URLs)
  - `Stop Backend`
  - `Retry Startup`
  - `Refresh Backend Status`
- Added backend status line states:
  - `Backend: not started`
  - `Backend: starting service...`
  - `Backend: loading speech model...`
  - `Backend: healthy`
  - `Backend: needs attention`
- Added non-modal backend notice line in the menu for actionable guidance.

### 5) External URL (manual backend) mode

- If backend URL is local loopback (`localhost`, `127.0.0.1`, `::1`), app can manage process lifecycle.
- If backend URL is external:
  - App does not spawn/kill backend process.
  - `Start Backend` becomes readiness watcher (`Wait for External Backend`).
  - User manually starts backend; app waits for `/health` readiness.

### 6) Warm-up overlay UX

- Extended recording overlay in `Sources/QuickASRMac/TranscriptPanelController.swift` with `.warming` mode.
- Added dynamic subtitle support for contextual messaging.
- Warm-up copy explains expected delay and queued recording behavior.

### 7) Reduced blocking alerts

- Replaced several startup-status alerts with in-menu notices and warm-up overlay messaging.
- Kept modal alerts for critical user-facing failures only.

### 8) Readiness notifications

- Added local notification permission request and ready notification in `Sources/QuickASRMac/AppDelegate.swift`.
- Notification text:
  - Title: `Openflow is ready`
  - Body: `Speech engine loaded. You can record now.`

### 9) Menu bar icon animation during warm-up

- Added icon animation while backend is in `starting/warming` and app is idle.
- Uses a cycling hourglass symbol set with orange tint.
- Animation starts/stops automatically with backend state transitions.

### 10) Settings and docs updates

- `Sources/QuickASRMac/SettingsView.swift` now explains local-managed vs external-manual backend behavior under Backend URL.
- Updated `README.md` with startup flow, warm-up expectations, and external URL behavior.

## Files Changed

- `Sources/QuickASRMac/BackendSupervisor.swift` (new)
- `Sources/QuickASRMac/AppDelegate.swift`
- `Sources/QuickASRMac/TranscriptPanelController.swift`
- `Sources/QuickASRMac/SettingsView.swift`
- `README.md`

## Validation Performed

- Ran `swift build` in `mac-app/` after each change batch.
- Final build status: success.

## Current UX Behavior (User-facing)

1. User clicks `Start Backend` (or `Wait for External Backend`).
2. App enters warm-up and shows progress messaging.
3. Menu icon animates during warm-up.
4. If user tries recording early, recording is queued.
5. When backend reports ready, app notifies user and queued recording starts automatically.

## Known Gaps / Potential Next Enhancements

- Add a dedicated `View Backend Logs` menu action.
- Add optional toggle: `Auto-start backend on app launch`.
- Add a lightweight non-modal toast/badge system for all backend notices.
- Expose warm-up timeout value in settings.
