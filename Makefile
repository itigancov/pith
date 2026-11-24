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

# `make shots`: SURFACE=context-menu for the open menu, FIXTURE=<path> for another text, OUT=<folder> for the PNGs.
SURFACE ?= window
SHOTS_FIXTURE ?= $(if $(filter file,$(origin FIXTURE)),$(CURDIR)/Fixtures/Panel.md,$(FIXTURE))

.PHONY: test bench build run shots

test:
	swift test

# Restyle timings (spec 09) and NoteStore timings (spec 03) against their budgets; fails on a missed budget.
bench:
	swift run -c release PithBench

build:
	xcodegen generate
	xcodebuild -project Pith.xcodeproj -scheme Pith -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) $(DESTINATION) build

# `-n` so the arguments arrive even if the app is already running.
run: build
	open -n $(APP) --args -PithFixture "$(FIXTURE)"

# Light and dark PNGs of the real window, see scripts/shots.sh.
shots: build
	SURFACE="$(SURFACE)" FIXTURE="$(SHOTS_FIXTURE)" OUT="$(OUT)" scripts/shots.sh "$(APP)"
