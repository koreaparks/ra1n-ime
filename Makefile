APP_NAME    := ra1nIME
BUILD_DIR   := build
BUNDLE      := $(BUILD_DIR)/$(APP_NAME).app
BUNDLE_NAME := $(APP_NAME).app
CONTENTS    := $(BUNDLE)/Contents
EXEC        := $(CONTENTS)/MacOS/$(APP_NAME)
INFO        := $(CONTENTS)/Info.plist
SOURCES     := Sources/main.swift \
               Sources/HangulInputController.swift \
               Sources/HangulAutomaton.swift \
               Sources/Keymap.swift \
               Sources/Preferences.swift \
               Sources/PreferencesWindow.swift \
               Sources/GlobalKeyTap.swift \
               Sources/ClickMonitor.swift \
               Sources/StatusBarController.swift \
               Sources/PermissionChecker.swift

# Default install: system-wide (sudo required). Override for user-local:
#   make install INSTALL_DIR="$$HOME/Library/Input Methods" SUDO=
INSTALL_DIR ?= /Library/Input Methods
SUDO        ?= sudo

SWIFTC      := xcrun -sdk macosx swiftc
SWIFTFLAGS  := -O -target arm64-apple-macos13.0 -framework Cocoa -framework Carbon -framework InputMethodKit

# Code signing identity — defaults to first "Apple Development" cert in keychain.
# Override with: make CODESIGN_IDENTITY="Developer ID Application: ..."
CODESIGN_IDENTITY ?= $(shell security find-identity -p codesigning -v 2>/dev/null | grep -m1 "Apple Development" | sed -E 's/.*"([^"]+)"/\1/')
ifeq ($(strip $(CODESIGN_IDENTITY)),)
CODESIGN_IDENTITY := -
endif

.PHONY: all clean install refresh reload uninstall help pkg

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) Info.plist ra1nIME.entitlements res/AppIcon.icns res/MenuIcon.tiff
	@mkdir -p $(CONTENTS)/MacOS \
	          $(CONTENTS)/Resources/Base.lproj \
	          $(CONTENTS)/Resources/ko.lproj \
	          $(CONTENTS)/Resources/en.lproj
	cp Info.plist $(INFO)
	cp res/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	cp res/MenuIcon.tiff $(CONTENTS)/Resources/MenuIcon.tiff
	printf 'APPL????' > $(CONTENTS)/PkgInfo
	# Localized InfoPlist.strings — single mode key.
	printf 'CFBundleDisplayName = "ra1n IME";\nCFBundleName = "ra1n IME";\n"kr.ra1n.inputmethod.ra1nime.korean" = "ra1n IME";\n' \
	  > $(CONTENTS)/Resources/en.lproj/InfoPlist.strings
	printf 'CFBundleDisplayName = "ra1n IME";\nCFBundleName = "ra1n IME";\n"kr.ra1n.inputmethod.ra1nime.korean" = "ra1n IME";\n' \
	  > $(CONTENTS)/Resources/ko.lproj/InfoPlist.strings
	printf 'CFBundleDisplayName = "ra1n IME";\nCFBundleName = "ra1n IME";\n"kr.ra1n.inputmethod.ra1nime.korean" = "ra1n IME";\n' \
	  > $(CONTENTS)/Resources/Base.lproj/InfoPlist.strings
	$(SWIFTC) $(SWIFTFLAGS) -o $(EXEC) $(SOURCES)
	codesign --force --deep --options runtime --timestamp=none --entitlements ra1nIME.entitlements --sign "$(CODESIGN_IDENTITY)" $(BUNDLE)
	@touch $(BUNDLE)

install: $(BUNDLE)
	$(SUDO) rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	$(SUDO) mkdir -p "$(INSTALL_DIR)"
	$(SUDO) cp -R $(BUNDLE) "$(INSTALL_DIR)/"
	@echo "Installed to: $(INSTALL_DIR)/$(BUNDLE_NAME)"

# One-shot: build, install, and refresh all relevant caches without logout.
refresh:
	@rm -rf $(BUNDLE)
	@$(MAKE) all install
	@-killall $(APP_NAME) 2>/dev/null || true
	@-killall TextInputMenuAgent 2>/dev/null || true
	@-killall cfprefsd 2>/dev/null || true
	@$(SUDO) touch "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
	    -f "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@echo "Refreshed. Open System Settings > Keyboard > Input Sources to re-check."

# Lightweight: just restart the IME process (for Swift code changes only).
reload: install
	@-killall $(APP_NAME) 2>/dev/null || true
	@echo "$(APP_NAME) reloaded. Switch input source to retrigger."

uninstall:
	@-killall $(APP_NAME) 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
	    -u "$(INSTALL_DIR)/$(BUNDLE_NAME)" 2>/dev/null || true
	$(SUDO) rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@-killall TextInputMenuAgent cfprefsd 2>/dev/null || true
	@echo "Uninstalled. Remove from System Settings > Keyboard > Input Sources if still listed."

pkg: $(BUNDLE)
	@mkdir -p $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/$(APP_NAME).pkg
	@rm -rf /tmp/$(APP_NAME)-pkgroot /tmp/$(APP_NAME)-scripts /tmp/$(APP_NAME)-dist
	@mkdir -p /tmp/$(APP_NAME)-pkgroot/Library/Input\ Methods
	@mkdir -p /tmp/$(APP_NAME)-scripts
	@mkdir -p /tmp/$(APP_NAME)-dist
	@cp -R $(BUNDLE) /tmp/$(APP_NAME)-pkgroot/Library/Input\ Methods/
	@cp scripts/postinstall /tmp/$(APP_NAME)-scripts/postinstall
	@cp scripts/distribution.xml /tmp/$(APP_NAME)-dist/distribution.xml
	pkgbuild \
		--root /tmp/$(APP_NAME)-pkgroot \
		--identifier kr.ra1n.inputmethod.ra1nime \
		--version 1.0.0 \
		--install-location / \
		--scripts /tmp/$(APP_NAME)-scripts \
		/tmp/$(APP_NAME)-dist/component.pkg
	productbuild \
		--distribution /tmp/$(APP_NAME)-dist/distribution.xml \
		--package-path /tmp/$(APP_NAME)-dist \
		$(BUILD_DIR)/$(APP_NAME).pkg
	@rm -rf /tmp/$(APP_NAME)-pkgroot /tmp/$(APP_NAME)-scripts /tmp/$(APP_NAME)-dist
	@echo "Created $(BUILD_DIR)/$(APP_NAME).pkg"

help:
	@echo "make           build the .app bundle ($(BUNDLE))"
	@echo "make install   sudo-copy to /Library/Input Methods/ (system-wide; default)"
	@echo "make refresh   install + flush TIS caches"
	@echo "make reload    install + restart IME process (Swift-only changes)"
	@echo "make uninstall remove from $(INSTALL_DIR)"
	@echo "make pkg       build an installer package ($(BUILD_DIR)/$(APP_NAME).pkg)"
	@echo "make clean     delete build artifacts"
	@echo ""
	@echo "Override default install target with: make refresh INSTALL_DIR=... SUDO=..."

clean:
	rm -rf $(BUILD_DIR) /tmp/_makeicon
