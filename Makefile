SHELL := /bin/bash
.DEFAULT_GOAL := build

# The Command Line Tools ship Swift Testing outside SwiftPM's default search path,
# so point the compiler and linker at it when CLT (not full Xcode) is the active toolchain.
# CLT also ships the Testing+Foundation cross-import overlay without its module, so it's disabled.
CLT_DIR := /Library/Developer/CommandLineTools
CLT_FRAMEWORKS := $(CLT_DIR)/Library/Developer/Frameworks
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT_DIR))
TEST_FLAGS := -Xswiftc -F$(CLT_FRAMEWORKS) -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
# SwiftLint looks for sourcekitdInProc in Xcode; under CLT it lives in $(CLT_DIR)/usr/lib.
SWIFTLINT_ENV := TOOLCHAIN_DIR=$(CLT_DIR)
endif

VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
DEV_APP := build/Kettle Dev.app

.PHONY: bootstrap build test test-release coverage lint format icons appicon whistle dev seed reset-dev logs memcheck profile release clean

bootstrap:
	@scripts/bootstrap.sh

build:
	swift build

# FILTER runs one suite or test, e.g. make test FILTER=TimerEngineTests
test:
	swift test --parallel $(if $(FILTER),--filter '$(FILTER)') $(TEST_FLAGS)

# The performance tests against optimised code (zero-allocation ticking needs -O).
test-release:
	swift test -c release -Xswiftc -enable-testing --filter PerformanceTests $(TEST_FLAGS)

coverage:
	@scripts/coverage.sh $(TEST_FLAGS)

lint:
	@command -v swiftformat >/dev/null || { echo "swiftformat not found: run make bootstrap"; exit 1; }
	@command -v swiftlint >/dev/null || { echo "swiftlint not found: run make bootstrap"; exit 1; }
	swiftformat --lint .
	$(SWIFTLINT_ENV) swiftlint lint --strict --quiet
	scripts/check-no-network.sh

format:
	swiftformat .

icons:
	swift run kettle-tools icons

appicon:
	swift run kettle-tools appicon

# Regenerates the time's-up sound and plays it.
whistle:
	swift run kettle-tools whistle
	afplay Resources/Whistle.wav

dev:
	@pkill -x "Kettle Dev" || true
	scripts/bundle.sh debug dev
	open $(if $(KETTLE_DATA_DIR),--env KETTLE_DATA_DIR="$(KETTLE_DATA_DIR)") "$(DEV_APP)"

seed:
	swift run kettle-tools seed

reset-dev:
	@scripts/reset-dev.sh

logs:
	log stream --predicate 'subsystem == "io.github.kettle"'

memcheck:
	@scripts/memcheck.sh

profile:
	@scripts/profile.sh

release:
	scripts/bundle.sh release prod
	cd build && rm -f "Kettle-$(VERSION).zip" && ditto -c -k --keepParent Kettle.app "Kettle-$(VERSION).zip"
	@echo "Built build/Kettle-$(VERSION).zip"

clean:
	rm -rf .build build
