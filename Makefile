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

# `make shots`: SURFACE=context-menu|context-menu-spelling|menu-bar|text-size|save-failure|recorder|stack|stack-new|jump-latest|search-all|search-results|search-empty|
# search-select|delete-undo|trash|trash-confirm|trash-delete|settings|settings-shortcuts|settings-login-approval|settings-outside-applications|move-alert|
# onboarding-hotkey|onboarding-ready|onboarding-ready-outside|welcome|scroller
# for another surface, FIXTURE=<path> for another text (`Fixtures/Empty.md` for the placeholder), OUT=<folder> for the PNGs.
SURFACE ?= window
SHOTS_FIXTURES_context-menu-spelling := ContextMenuSpelling.md
SHOTS_FIXTURES_menu-bar := Trash.json
SHOTS_FIXTURES_text-size := TextSize.md
SHOTS_FIXTURES_stack := Stack.md
SHOTS_FIXTURES_jump-latest := Standup.md
SHOTS_FIXTURES_search-all := Search.json
SHOTS_FIXTURES_search-results := Search.json
SHOTS_FIXTURES_search-empty := Search.json
SHOTS_FIXTURES_search-select := Search.json
SHOTS_FIXTURES_delete-undo := DeleteUndo.json
SHOTS_FIXTURES_trash := Trash.json
SHOTS_FIXTURES_trash-confirm := Trash.json
SHOTS_FIXTURES_trash-delete := Trash.json
SHOTS_FIXTURES_settings := Trash.json
SHOTS_FIXTURES_settings-shortcuts := Trash.json
SHOTS_FIXTURES_settings-login-approval := Trash.json
SHOTS_FIXTURES_settings-outside-applications := Trash.json
SHOTS_FIXTURES_onboarding-hotkey := Empty.md
SHOTS_FIXTURES_onboarding-ready := Empty.md
SHOTS_FIXTURES_onboarding-ready-outside := Empty.md
SHOTS_FIXTURES_welcome := Empty.md
SHOTS_FIXTURES_scroller := Scroller.md
SHOTS_DEFAULT_FIXTURE := $(or $(SHOTS_FIXTURES_$(SURFACE)),Panel.md)
SHOTS_FIXTURE ?= $(if $(filter file,$(origin FIXTURE)),$(CURDIR)/Fixtures/$(SHOTS_DEFAULT_FIXTURE),$(FIXTURE))

.PHONY: test bench build run shots readme-media release

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

# The README's pictures in docs/images: framed Panel PNGs and a GIF, light and dark (scripts/readme-media.sh).
readme-media: build
	scripts/readme-media.sh "$(APP)"

# `make release VERSION=0.1.0` on a clean main: universal Release, tag, GitHub Release, cask in the tap (scripts/release.sh).
# `DRY_RUN=1` stops before anything is published; `scripts/release.sh --check` is the build and the checks alone.
release:
	VERSION="$(VERSION)" DRY_RUN="$(DRY_RUN)" scripts/release.sh
