DERIVED := .build/xcode
# `make run CONFIG=Release` for the manual performance check.
CONFIG ?= Debug
APP := $(DERIVED)/Build/Products/$(CONFIG)/PithDemo.app

.PHONY: test bench build run

test:
	swift test

# Restyle timings against the budgets of spec 09; fails on a missed budget.
bench:
	swift run -c release PithBench

build:
	xcodegen generate
	xcodebuild -project PithDemo.xcodeproj -scheme PithDemo -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) build

run: build
	open $(APP)
