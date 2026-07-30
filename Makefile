# MacTorn Makefile
# Run tests and build commands for local development

.PHONY: test test-unit test-ui test-all build analyze clean coverage coverage-gate help \
	release verify-release release-signed diagnose-xctest hooks scan quick-test watch \
	open test-summary

RELEASE_DERIVED_DATA ?= DerivedData/Release
RELEASE_APP := $(RELEASE_DERIVED_DATA)/Build/Products/Release/MacTorn.app

# Default target
help:
	@echo "MacTorn Build Commands:"
	@echo ""
	@echo "  make test            - Run all unit tests"
	@echo "  make test-ui         - Run UI tests"
	@echo "  make build           - Build the app in Debug mode"
	@echo "  make analyze         - Run Xcode static analysis"
	@echo "  make release         - Build the app in Release mode (ad-hoc signed, dev only)"
	@echo "  make verify-release  - Verify universal architectures and strict ad-hoc signature"
	@echo "  make release-signed  - Build Release signed with Developer ID (set DEVELOPER_ID)"
	@echo "  make diagnose-xctest - Collect read-only local XCTest runner diagnostics"
	@echo "  make clean           - Clean build artifacts"
	@echo "  make coverage        - Run tests with code coverage"
	@echo "  make coverage-gate   - Enforce >=80% coverage on critical modules"
	@echo "  make hooks           - Install the gitleaks pre-commit secret scan"
	@echo "  make scan            - Scan full git history for secrets"
	@echo ""
	@echo "  Example:"
	@echo "    make release-signed DEVELOPER_ID=\"Developer ID Application: NAME (TEAMID)\""
	@echo ""

# Run unit tests
test:
	xcodebuild test \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-destination 'platform=macOS' \
		-only-testing:MacTornTests \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO

# Run unit tests (alias)
test-unit: test

# Run UI tests
test-ui:
	xcodebuild test \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-destination 'platform=macOS' \
		-only-testing:MacTornUITests \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO

# Run all tests (unit + UI)
test-all:
	xcodebuild test \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO

# Build Debug
build:
	xcodebuild build \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-configuration Debug \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO

# Run Xcode static analysis
analyze:
	xcodebuild analyze \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-configuration Debug \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO

# Build Release (Universal Binary for Intel + Apple Silicon, strict ad-hoc signed)
# This is fine for local development. For distribution use `release-signed` below.
release:
	xcodebuild build \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-derivedDataPath '$(RELEASE_DERIVED_DATA)' \
		ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_ALLOWED=YES \
		CODE_SIGNING_REQUIRED=YES

# Verify that the local Release gate produced both architectures and only an ad-hoc signature.
verify-release:
	@test -d '$(RELEASE_APP)' || { echo "Release app not found: $(RELEASE_APP). Run 'make release' first."; exit 2; }
	@archs="$$(lipo -archs '$(RELEASE_APP)/Contents/MacOS/MacTorn')"; \
		echo "Architectures: $$archs"; \
		printf '%s\n' "$$archs" | grep -qw arm64; \
		printf '%s\n' "$$archs" | grep -qw x86_64
	codesign --verify --deep --strict --verbose=2 '$(RELEASE_APP)'
	@codesign -dv --verbose=4 '$(RELEASE_APP)' 2>&1 | grep -q '^Signature=adhoc$$'
	@echo "Release verification passed: universal and strict ad-hoc signed."

# Build Release signed with Developer ID (Universal Binary). Required for distribution
# so users can verify the publisher. Notarization is a follow-up — without it, Gatekeeper
# on recent macOS will still warn on first launch (right-click → Open is required).
#
# Usage:
#   make release-signed DEVELOPER_ID="Developer ID Application: NAME (TEAMID)"
#
# To list available identities:
#   security find-identity -v -p codesigning
release-signed:
ifndef DEVELOPER_ID
	$(error DEVELOPER_ID is not set. Example: make release-signed DEVELOPER_ID="Developer ID Application: NAME (TEAMID)")
endif
	xcodebuild build \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="$(DEVELOPER_ID)" \
		OTHER_CODE_SIGN_FLAGS="--options=runtime --timestamp" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES
	@echo ""
	@echo "Verify the signed bundle:"
	@echo "  codesign -dvv build/Build/Products/Release/MacTorn.app"
	@echo "  spctl --assess --verbose=4 build/Build/Products/Release/MacTorn.app"
	@echo "  (spctl will report 'rejected ... no notarization' until F-04 follow-up adds notarytool.)"

# Clean build artifacts
clean:
	xcodebuild clean \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn
	rm -rf build/
	rm -rf DerivedData/
	rm -rf TestResults/

# Run tests with code coverage
coverage:
	xcodebuild test \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-destination 'platform=macOS' \
		-enableCodeCoverage YES \
		-resultBundlePath TestResults.xcresult \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO
	@echo ""
	@echo "Coverage report generated in TestResults.xcresult"
	@echo "Open TestResults.xcresult to view in Xcode"

# Enforce >=80% line coverage on reliability-critical modules (Etap G / ISC-20).
# Runs the unit suite with coverage, then the gate. Views are intentionally excluded.
coverage-gate:
	rm -rf TestResults.xcresult
	xcodebuild test \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-destination 'platform=macOS' \
		-only-testing:MacTornTests \
		-resultBundlePath TestResults.xcresult \
		-enableCodeCoverage YES \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO
	bash scripts/coverage-gate.sh TestResults.xcresult 80

# Quick test - faster iteration
quick-test:
	xcodebuild test \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-destination 'platform=macOS' \
		-only-testing:MacTornTests \
		-parallel-testing-enabled YES \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		2>&1 | xcpretty --color

# Watch for changes and run tests (requires fswatch)
watch:
	@echo "Watching for changes... (requires fswatch)"
	fswatch -o MacTorn/MacTorn MacTorn/MacTornTests | xargs -n1 -I{} make quick-test

# Open project in Xcode
open:
	open MacTorn/MacTorn.xcodeproj

# Install git hooks (gitleaks secret scan on every commit)
hooks:
	@command -v gitleaks >/dev/null 2>&1 || { echo "❌ gitleaks not found. Install with: brew install gitleaks"; exit 1; }
	git config core.hooksPath .githooks
	chmod +x .githooks/*
	@echo "✅ Git hooks installed (core.hooksPath -> .githooks). gitleaks runs on every commit."

# Scan the entire git history for secrets
scan:
	@command -v gitleaks >/dev/null 2>&1 || { echo "❌ gitleaks not found. Install with: brew install gitleaks"; exit 1; }
	gitleaks git --no-banner --redact -v --config .gitleaks.toml

# Collect environment and service state without restarting or killing XCTest services.
# Pass RESULT_BUNDLE=/path/to/result.xcresult to include its test summary.
diagnose-xctest:
	bash scripts/diagnose-xctest.sh '$(RESULT_BUNDLE)'

# Show test summary
test-summary:
	@echo "Test Summary:"
	@echo "============="
	@find . -name "*.swift" -path "*/MacTornTests/*" | xargs grep -l "func test" | wc -l | xargs echo "Test files:"
	@find . -name "*.swift" -path "*/MacTornTests/*" | xargs grep "func test" | wc -l | xargs echo "Test cases:"
