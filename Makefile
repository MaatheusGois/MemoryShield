.PHONY: build generate run install fastlane-run fastlane-install clean help

PROJECT       := MemoryShield.xcodeproj
SCHEME        := MemoryShield
CONFIG        := Release
DERIVED_DATA  := build

BUILD_APP     := $(DERIVED_DATA)/Build/Products/$(CONFIG)/MemoryShield.app
GENERATED_APP := MemoryShield.app
GENERATED_DSYM := MemoryShield.app.dSYM.zip
INSTALL_PATH   := /Applications/MemoryShield.app

XCODEBUILD_FLAGS := \
	-project $(PROJECT) \
	-scheme $(SCHEME) \
	-configuration $(CONFIG) \
	-derivedDataPath $(DERIVED_DATA) \
	CODE_SIGN_IDENTITY="-" \
	CODE_SIGNING_ALLOWED=NO

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Local unsigned Release build (build/…)
	@echo "→ Building MemoryShield…"
	xcodebuild $(XCODEBUILD_FLAGS) build | xcbeautify --disable-colored-output || xcodebuild $(XCODEBUILD_FLAGS) build
	@test -d "$(BUILD_APP)" || (echo "✗ Build failed — $(BUILD_APP) not found" && exit 1)
	@echo "✓ $(BUILD_APP)"

run: build ## Build and launch
	@echo "→ Launching…"
	open "$(BUILD_APP)"

generate: ## Archive via fastlane (Developer ID export; requires signing)
	@echo "→ Generating release build (fastlane)…"
	fastlane release
	@test -d "$(GENERATED_APP)" || (echo "✗ Generate failed — $(GENERATED_APP) not found" && exit 1)
	@echo "✓ $(GENERATED_APP)"
	@test -f "$(GENERATED_DSYM)" && echo "✓ $(GENERATED_DSYM)"

install: build ## Build and copy to /Applications
	@echo "→ Installing to $(INSTALL_PATH)…"
	rm -rf "$(INSTALL_PATH)"
	cp -R "$(BUILD_APP)" "$(INSTALL_PATH)"
	@echo "✓ Installed at $(INSTALL_PATH)"

fastlane-run: generate ## Generate via fastlane and launch
	@echo "→ Launching $(GENERATED_APP)…"
	open "$(GENERATED_APP)"

fastlane-install: generate ## Generate via fastlane and copy to /Applications
	@echo "→ Installing $(GENERATED_APP) to $(INSTALL_PATH)…"
	rm -rf "$(INSTALL_PATH)"
	cp -R "$(GENERATED_APP)" "$(INSTALL_PATH)"
	@echo "✓ Installed at $(INSTALL_PATH)"
	open "$(INSTALL_PATH)"

clean: ## Remove local build artifacts
	rm -rf "$(DERIVED_DATA)" "$(GENERATED_APP)" "$(GENERATED_DSYM)"
