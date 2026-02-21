# Contributing to Openflow

Thanks for contributing.

## Development Setup

- macOS 13+
- Swift 5.9+
- Python 3.12+ (for the backend)

### macOS app

From the repo root:

```bash
swift build
swift run Openflow
```

### Backend (local)

```bash
cd services/backend
python3 -m venv .venv
source .venv/bin/activate
./.venv/bin/pip install -e .
./.venv/bin/python qwen_server.py
```

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
