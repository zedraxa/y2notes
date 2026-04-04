# Y2Notes — Developer Makefile
# ──────────────────────────────────────────────────────────────────
# Common development commands. Requires Xcode CLI tools installed.
#
# Usage:
#   make build          Build for iPad Simulator
#   make test           Run unit tests
#   make lint           Run SwiftLint
#   make clean          Clean derived data
#   make help           Show all targets
# ──────────────────────────────────────────────────────────────────

.DEFAULT_GOAL := help
SHELL := /bin/bash

# ── Variables ─────────────────────────────────────────────────────

PROJECT      := Y2Notes.xcodeproj
SCHEME       := Y2Notes
DESTINATION  := platform=iOS Simulator,name=iPad Pro 13-inch (M4)
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData
SDK          := iphonesimulator

# ── Build ─────────────────────────────────────────────────────────

.PHONY: build
build: ## Build for iPad Simulator
	xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-sdk $(SDK) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		| xcpretty || true

.PHONY: build-release
build-release: ## Build Release configuration for iPad Simulator
	xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-sdk $(SDK) \
		-configuration Release \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		| xcpretty || true

.PHONY: build-clean
build-clean: clean build ## Clean then build

# ── Test ──────────────────────────────────────────────────────────

.PHONY: test
test: ## Run all tests
	xcodebuild test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-sdk $(SDK) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		| xcpretty || true

.PHONY: test-verbose
test-verbose: ## Run all tests with verbose output
	xcodebuild test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-sdk $(SDK) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO

# ── Lint ──────────────────────────────────────────────────────────

.PHONY: lint
lint: ## Run SwiftLint
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --config .swiftlint.yml; \
	else \
		echo "⚠️  SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

.PHONY: lint-fix
lint-fix: ## Run SwiftLint with auto-fix
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --fix --config .swiftlint.yml; \
	else \
		echo "⚠️  SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

.PHONY: lint-strict
lint-strict: ## Run SwiftLint in strict mode (warnings become errors)
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --strict --config .swiftlint.yml; \
	else \
		echo "⚠️  SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

# ── Clean ─────────────────────────────────────────────────────────

.PHONY: clean
clean: ## Clean Xcode derived data
	xcodebuild clean \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		2>/dev/null || true
	@echo "✅ Cleaned derived data"

.PHONY: clean-all
clean-all: ## Remove ALL Xcode derived data (all projects)
	rm -rf "$(DERIVED_DATA)"
	@echo "✅ Removed all derived data"

# ── Project Info ──────────────────────────────────────────────────

.PHONY: info
info: ## Show project info (schemes, targets, build settings)
	@echo "──── Schemes ────"
	@xcodebuild -project "$(PROJECT)" -list 2>/dev/null | head -20
	@echo ""
	@echo "──── Swift Files ────"
	@find Y2Notes -name "*.swift" | wc -l | xargs echo "Count:"
	@echo ""
	@echo "──── Lines of Code ────"
	@find Y2Notes -name "*.swift" -exec cat {} + | wc -l | xargs echo "Swift:"
	@find docs -name "*.md" -exec cat {} + 2>/dev/null | wc -l | xargs echo "Documentation:"
	@echo ""
	@echo "──── Localizable Keys ────"
	@grep -c '=' Y2Notes/en.lproj/Localizable.strings 2>/dev/null || echo "0"

.PHONY: loc
loc: ## Count lines of code by file type
	@echo "Swift source files:"
	@find Y2Notes -name "*.swift" | wc -l
	@echo "Swift lines of code:"
	@find Y2Notes -name "*.swift" -exec cat {} + | wc -l
	@echo ""
	@echo "Documentation (Markdown):"
	@find docs -name "*.md" | wc -l
	@echo "Documentation lines:"
	@find docs -name "*.md" -exec cat {} + 2>/dev/null | wc -l
	@echo ""
	@echo "YAML config:"
	@find . -maxdepth 1 -name "*.yaml" -o -name "*.yml" | wc -l
	@echo "Localization keys:"
	@grep -c '=' Y2Notes/en.lproj/Localizable.strings 2>/dev/null || echo "0"

# ── Format ────────────────────────────────────────────────────────

.PHONY: format
format: ## Format Swift files with swift-format (if installed)
	@if command -v swift-format >/dev/null 2>&1; then \
		find Y2Notes -name "*.swift" -exec swift-format -i {} +; \
		echo "✅ Formatted all Swift files"; \
	else \
		echo "⚠️  swift-format not installed. Install with: brew install swift-format"; \
	fi

# ── Validation ────────────────────────────────────────────────────

.PHONY: validate-pbxproj
validate-pbxproj: ## Validate project.pbxproj structure
	@if command -v ruby >/dev/null 2>&1 && ruby -e 'require "xcodeproj"' 2>/dev/null; then \
		ruby -e 'require "xcodeproj"; Xcodeproj::Project.open("$(PROJECT)"); puts "✅ pbxproj valid"'; \
	else \
		echo "⚠️  xcodeproj gem not installed. Install with: gem install xcodeproj"; \
	fi

.PHONY: validate-strings
validate-strings: ## Check Localizable.strings for duplicate keys
	@echo "Checking for duplicate localisation keys..."
	@awk -F'"' '/^"/ {print $$2}' Y2Notes/en.lproj/Localizable.strings | sort | uniq -d | \
		{ read -r line; if [ -n "$$line" ]; then echo "❌ Duplicate keys found:"; echo "$$line"; while read -r l; do echo "$$l"; done; exit 1; else echo "✅ No duplicate keys"; fi; }

.PHONY: validate
validate: validate-pbxproj validate-strings lint ## Run all validation checks

# ── Help ──────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@echo "Y2Notes — Developer Commands"
	@echo "────────────────────────────────────────────────"
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
