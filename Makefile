DERIVED := .build/xcode
# `make run CONFIG=Release` for the manual performance check.
CONFIG ?= Debug
APP := $(DERIVED)/Build/Products/$(CONFIG)/Pith.app
# `make run FIXTURE=/path/to/note.md` opens another text in an in-memory database; `make run FIXTURE=` (empty)
# opens the real database in Application Support, which `make run` and `make shots` otherwise never touch.
FIXTURE ?= $(CURDIR)/Fixtures/Demo.md

# Release is universal; the default destination would build only the host's architecture.
ifeq ($(CONFIG),Release)
DESTINATION := -destination 'generic/platform=macOS'
endif

# `make shots`: SURFACE=context-menu|text-size|save-failure for another surface, FIXTURE=<path> for another text
# (`Fixtures/Empty.md` for the placeholder), OUT=<folder> for the PNGs.
SURFACE ?= window
SHOTS_DEFAULT_FIXTURE := $(if $(filter text-size,$(SURFACE)),TextSize.md,Panel.md)
SHOTS_FIXTURE ?= $(if $(filter file,$(origin FIXTURE)),$(CURDIR)/Fixtures/$(SHOTS_DEFAULT_FIXTURE),$(FIXTURE))

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
	open -n $(APP) $(if $(FIXTURE),--args -PithFixture "$(FIXTURE)")

# Light and dark PNGs of the real window, see scripts/shots.sh.
shots: build
	SURFACE="$(SURFACE)" FIXTURE="$(SHOTS_FIXTURE)" OUT="$(OUT)" scripts/shots.sh "$(APP)"
