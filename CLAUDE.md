# Pith

Prototype of a live-Markdown editor for macOS (NSTextView + TextKit 2). Vocabulary: [GLOSSARY.md](GLOSSARY.md), decisions: [docs/adr/](docs/adr/).

## Commands

- `make test` — `swift test` (`PithEditor` package, Swift Testing)
- `make build` — xcodegen + xcodebuild of the demo into `.build/xcode`
- `make run` — build, then open `PithDemo.app`

## Layout

- `Sources/PithEditor`, `Tests/PithEditorTests` — the core, no dependencies
- `Demo` — thin AppKit app; `project.yml` generates `.xcodeproj` (not committed)

## Rules

- All repo content is in English: docs, comments, commit messages, PR descriptions. Conversations may be in any language.
- Never touch `layoutManager` on `EditorTextView` (it falls back to TextKit 1).
- Logic lives in the package; the demo is throwaway.
