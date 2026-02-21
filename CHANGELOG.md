# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Apache 2.0 license headers across all Swift and Python source files
- `CODE_OF_CONDUCT.md` based on Contributor Covenant 2.1
- `CHANGELOG.md` to track version history
- GitHub issue templates for bug reports and feature requests
- GitHub pull request template

## [0.1.0] - 2025-01-01

### Added
- Initial open-source release
- macOS menu bar application for low-friction speech-to-text
- Global hotkey recording control (`Cmd+Shift+Space` by default)
- Menu bar backend actions (`Start`, `Stop`, `Retry`, `Refresh`)
- Readiness and warm-up state tracking with user-visible status
- Output routing to clipboard, active app, both, or none
- Support for both managed local backend and external backend URL modes
- Python ASR backend using Qwen3-ASR models
- Configurable settings: backend URL, output mode, hotkey, API token, timeout, retry, upload limit
- Apache 2.0 license
- CI/CD via GitHub Actions (build, test, release)
- DMG packaging for distribution

[Unreleased]: https://github.com/abhilashpanda04/Openflow/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/abhilashpanda04/Openflow/releases/tag/v0.1.0
