.PHONY: build bundle run clean cert release install reset-tcc

APP := .build/Murmur.app

## Install target. ~/Applications needs no sudo and is indexed by Spotlight and
## Finder just like /Applications. Override for a system-wide install:
##     make install INSTALL_DIR=/Applications   (will prompt for sudo)
INSTALL_DIR ?= $(HOME)/Applications

build:
	swift build

bundle:
	./scripts/bundle.sh

release:
	CONFIG=release ./scripts/bundle.sh

run: bundle
	@pkill -x Murmur 2>/dev/null || true
	@sleep 0.3
	open $(APP)
	@echo ""
	@echo "Murmur is running. Its menu bar icon reflects state:"
	@echo "    (!)  warning triangle  -> permissions needed (expected on first run)"
	@echo "    mic                    -> ready, hold your hotkey to dictate"
	@echo ""
	@echo "On first run click the warning triangle -> Settings... and grant all three."

## Copy into $(INSTALL_DIR). TCC grants follow the bundle ID + signature, not
## the path, so moving the app does not cost you your permissions.
install: release
	@pkill -x Murmur 2>/dev/null || true
	@mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/Murmur.app"
	cp -R $(APP) "$(INSTALL_DIR)/Murmur.app"
	open "$(INSTALL_DIR)/Murmur.app"
	@echo "Installed to $(INSTALL_DIR)/Murmur.app"

cert:
	./scripts/make-cert.sh

## Last resort if permissions get into a bad state. You will have to re-approve.
reset-tcc:
	tccutil reset Accessibility com.alexchoo.murmur || true
	tccutil reset ListenEvent com.alexchoo.murmur || true
	tccutil reset Microphone com.alexchoo.murmur || true

clean:
	rm -rf .build
