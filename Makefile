.DEFAULT_GOAL := help
.PHONY: generate build-dev build-prod run run-dev run-prod install install-services clean help

SCHEME := BetterGPG
CONFIG_DEV := Debug
CONFIG_PROD := Release
BUILD_DIR := build
DEV_APP := $(BUILD_DIR)/Build/Products/$(CONFIG_DEV)/BetterGPG.app
PROD_APP := $(BUILD_DIR)/Build/Products/$(CONFIG_PROD)/BetterGPG.app

# Generate Xcode project from project.yml (requires xcodegen)
generate:
	xcodegen generate

# Build development (Debug) configuration
dev: generate
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG_DEV) -derivedDataPath $(BUILD_DIR) build

# Build production (Release) configuration
prod: generate
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG_PROD) -derivedDataPath $(BUILD_DIR) build

# Run the app (uses dev build by default)
run: dev
	open $(DEV_APP)

# Run development build
run-dev: dev
	open $(DEV_APP)

# Run production build
run-prod: prod
	open $(PROD_APP)

# Copy prod app to /Applications and refresh Finder services
install: prod
	rm -rf /Applications/BetterGPG.app
	cp -R $(PROD_APP) /Applications/BetterGPG.app
	@echo "Refreshing macOS services registration…"
	/System/Library/CoreServices/pbs -update
	@echo "Done. Open BetterGPG from /Applications — services will appear in Finder right-click."

# Refresh Finder services without reinstalling (run after first launch too)
install-services:
	/System/Library/CoreServices/pbs -update
	@echo "Services refreshed. You may need to re-launch Finder (killall Finder)."

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -rf BetterGPG.xcodeproj
	rm -rf BetterGPG.xcworkspace

# Default target
help:
	@echo "BetterGPG Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make generate    - Generate Xcode project from project.yml"
	@echo "  make dev         - Build Debug (development) configuration"
	@echo "  make prod        - Build Release (production) configuration"
	@echo "  make run         - Build dev and run the app"
	@echo "  make run-dev     - Same as run"
	@echo "  make run-prod    - Build prod and run the app"
	@echo "  make install          - Build prod, copy to /Applications, refresh services"
	@echo "  make install-services - Refresh Finder services registration only"
	@echo "  make clean            - Remove build artifacts and generated project"
	@echo "  make help             - Show this help"
