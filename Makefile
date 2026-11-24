DERIVED := .build/xcode
# `make run CONFIG=Release` for the manual performance check.
CONFIG ?= Debug
APP := $(DERIVED)/Build/Products/$(CONFIG)/Pith.app
# `make run FIXTURE=/path/to/note.md` opens another text.
FIXTURE ?= $(CURDIR)/Fixtures/Demo.md

# Release is universal; the default destination would build only the host's architecture.
ifeq ($(CONFIG),Release)
DESTINATION := -destination 'generic/platform=macOS'
endif

.PHONY: test bench build run

test:
	swift test

# Restyle timings against the budgets of spec 09; fails on a missed budget.
bench:
	swift run -c release PithBench

build:
	xcodegen generate
	xcodebuild -project Pith.xcodeproj -scheme Pith -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) $(DESTINATION) build

# `-n` so the arguments arrive even if the app is already running.
run: build
	open -n $(APP) --args -PithFixture "$(FIXTURE)"
