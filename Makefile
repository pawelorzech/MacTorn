# MacTorn Makefile
# Run tests and build commands for local development

.PHONY: test test-unit test-ui build clean coverage help

# Default target
help:
	@echo "MacTorn Build Commands:"
	@echo ""
	@echo "  make test       - Run all unit tests"
	@echo "  make test-ui    - Run UI tests"
	@echo "  make build      - Build the app in Debug mode"
	@echo "  make release    - Build the app in Release mode"
	@echo "  make clean      - Clean build artifacts"
	@echo "  make coverage   - Run tests with code coverage"
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

# Build Release (Universal Binary for Intel + Apple Silicon)
release:
	xcodebuild build \
		-project MacTorn/MacTorn.xcodeproj \
		-scheme MacTorn \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO

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
		-resultBundlePath TestResults \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO
	@echo ""
	@echo "Coverage report generated in TestResults/"
	@echo "Open TestResults/action.xccovreport to view in Xcode"

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

# Show test summary
test-summary:
	@echo "Test Summary:"
	@echo "============="
	@find . -name "*.swift" -path "*/MacTornTests/*" | xargs grep -l "func test" | wc -l | xargs echo "Test files:"
	@find . -name "*.swift" -path "*/MacTornTests/*" | xargs grep "func test" | wc -l | xargs echo "Test cases:"
