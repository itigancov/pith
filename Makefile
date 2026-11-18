DERIVED := .build/xcode
APP := $(DERIVED)/Build/Products/Debug/PithDemo.app

.PHONY: test build run

test:
	swift test

build:
	xcodegen generate
	xcodebuild -project PithDemo.xcodeproj -scheme PithDemo -configuration Debug \
		-derivedDataPath $(DERIVED) build

run: build
	open $(APP)
