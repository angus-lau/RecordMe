.PHONY: build run clean

APP_NAME = RecordMe
BUILD_DIR = build
SCHEME = $(APP_NAME)
DESTINATION = platform=macOS
CONFIG = Release

build:
	@echo "Building $(APP_NAME)..."
	@xcodegen generate 2>/dev/null || true
	@xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		-allowProvisioningUpdates \
		build 2>&1 | tail -5
	@echo ""
	@echo "Built: $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app"

run: build
	@open "$(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app"

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned."

install: build
	@cp -R "$(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"
