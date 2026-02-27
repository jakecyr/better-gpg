.DEFAULT_GOAL := help
.PHONY: generate build-dev build-prod run run-dev run-prod clean help

SCHEME := GPGeze
CONFIG_DEV := Debug
CONFIG_PROD := Release
BUILD_DIR := build
DEV_APP := $(BUILD_DIR)/Build/Products/$(CONFIG_DEV)/GPGeze.app
PROD_APP := $(BUILD_DIR)/Build/Products/$(CONFIG_PROD)/GPGeze.app

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

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -rf GPGeze.xcodeproj
	rm -rf GPGeze.xcworkspace

# Default target
help:
	@echo "GPGeze Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make generate    - Generate Xcode project from project.yml"
	@echo "  make dev         - Build Debug (development) configuration"
	@echo "  make prod        - Build Release (production) configuration"
	@echo "  make run         - Build dev and run the app"
	@echo "  make run-dev     - Same as run"
	@echo "  make run-prod    - Build prod and run the app"
	@echo "  make clean       - Remove build artifacts and generated project"
	@echo "  make help        - Show this help"
