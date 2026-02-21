.PHONY: help debug release dmg clean test-mic backend install-deps

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Openflow Build System$(NC)"
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make debug          # Quick local development build"
	@echo "  make release        # Production build with optimizations"
	@echo "  make dmg            # Create distributable DMG"
	@echo "  make test-mic       # Build and test microphone permissions"
	@echo ""

debug: ## Build debug .app bundle for local testing
	@echo "$(BLUE)Building debug .app bundle...$(NC)"
	@./packaging/build-app.sh debug yes

release: ## Build optimized release .app bundle
	@echo "$(BLUE)Building release .app bundle...$(NC)"
	@./packaging/build-app.sh release yes

dmg: release ## Create distribution DMG (app only, no bundled backend)
	@echo "$(BLUE)Creating release DMG...$(NC)"
	@./packaging/create_dmg.sh

test-mic: debug ## Build and launch app to test microphone permissions
	@echo "$(BLUE)Testing microphone permissions...$(NC)"
	@echo "$(YELLOW)The app will launch. Grant microphone access when prompted.$(NC)"
	@echo ""
	@sleep 2
	@open .build/arm64-apple-macosx/debug/Openflow.app
	@echo ""
	@echo "$(GREEN)App launched!$(NC)"
	@echo "Expected behavior:"
	@echo "  1. macOS shows microphone permission dialog"
	@echo "  2. Grant access"
	@echo "  3. App appears in System Settings > Privacy & Security > Microphone"
	@echo "  4. Recording works when you press the hotkey (Cmd+Shift+Space)"
	@echo ""

backend: ## Set up and run the Python backend
	@echo "$(BLUE)Setting up backend...$(NC)"
	@cd services/backend && \
		(test -d .venv || python3 -m venv .venv) && \
		.venv/bin/pip install -q --upgrade pip && \
		.venv/bin/pip install -q -e . && \
		echo "$(GREEN)Backend ready!$(NC)" && \
		echo "" && \
		echo "$(YELLOW)Starting backend server on http://127.0.0.1:8001$(NC)" && \
		echo "Press Ctrl+C to stop." && \
		echo "" && \
		.venv/bin/python qwen_server.py

install-deps: ## Install development dependencies
	@echo "$(BLUE)Installing dependencies...$(NC)"
	@if ! command -v swift >/dev/null 2>&1; then \
		echo "$(YELLOW)Warning: Swift is not installed. Install Xcode or Swift toolchain.$(NC)"; \
		exit 1; \
	fi
	@if ! command -v python3 >/dev/null 2>&1; then \
		echo "$(YELLOW)Warning: Python 3 is not installed.$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Swift $(shell swift --version | head -1)$(NC)"
	@echo "$(GREEN)✓ Python $(shell python3 --version)$(NC)"
	@echo ""
	@echo "Setting up backend virtual environment..."
	@cd services/backend && \
		python3 -m venv .venv && \
		.venv/bin/pip install -q --upgrade pip && \
		.venv/bin/pip install -q -e .
	@echo "$(GREEN)✓ Backend dependencies installed$(NC)"
	@echo ""
	@echo "$(BLUE)All dependencies ready!$(NC)"
	@echo "Run 'make debug' to build the app."

clean: ## Clean all build artifacts
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@rm -rf .build/arm64-apple-macosx/*/Openflow.app
	@rm -rf dist/
	@rm -rf services/backend/.venv
	@rm -rf services/backend/__pycache__
	@rm -rf services/backend/uploads
	@echo "$(GREEN)✓ Build artifacts cleaned$(NC)"

# Advanced targets

run-debug: debug ## Build debug app and run it
	@open .build/arm64-apple-macosx/debug/Openflow.app

run-release: release ## Build release app and run it
	@open .build/arm64-apple-macosx/release/Openflow.app

verify-signature: ## Verify code signature of last build
	@if [ -d .build/arm64-apple-macosx/debug/Openflow.app ]; then \
		echo "$(BLUE)Verifying debug build signature...$(NC)"; \
		codesign --verify --deep --strict --verbose=2 .build/arm64-apple-macosx/debug/Openflow.app && \
		echo "$(GREEN)✓ Debug signature valid$(NC)"; \
	fi
	@if [ -d .build/arm64-apple-macosx/release/Openflow.app ]; then \
		echo "$(BLUE)Verifying release build signature...$(NC)"; \
		codesign --verify --deep --strict --verbose=2 .build/arm64-apple-macosx/release/Openflow.app && \
		echo "$(GREEN)✓ Release signature valid$(NC)"; \
	fi

show-entitlements: ## Show app entitlements
	@if [ -d .build/arm64-apple-macosx/debug/Openflow.app ]; then \
		echo "$(BLUE)Debug build entitlements:$(NC)"; \
		codesign -d --entitlements - .build/arm64-apple-macosx/debug/Openflow.app 2>/dev/null || \
		echo "$(YELLOW)No debug build found$(NC)"; \
	fi

info: ## Show build environment information
	@echo "$(BLUE)Build Environment$(NC)"
	@echo "  Swift:   $(shell swift --version | head -1)"
	@echo "  Xcode:   $(shell xcodebuild -version 2>/dev/null | head -1 || echo 'Not found')"
	@echo "  Python:  $(shell python3 --version 2>/dev/null || echo 'Not found')"
	@echo "  macOS:   $(shell sw_vers -productVersion)"
	@echo "  Arch:    $(shell uname -m)"
	@echo ""
	@echo "$(BLUE)Project Info$(NC)"
	@echo "  Version: $(shell git describe --tags --abbrev=0 2>/dev/null || echo '0.1.0-dev')"
	@echo "  Commit:  $(shell git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
	@echo "  Branch:  $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
