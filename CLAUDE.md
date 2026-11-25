# Pith

Prototype of a live-Markdown editor for macOS (NSTextView + TextKit 2). Vocabulary: [GLOSSARY.md](GLOSSARY.md), decisions: [docs/adr/](docs/adr/).

## Commands

- `make test` — `swift test` (`Pith` package, Swift Testing)
- `make build` — xcodegen + xcodebuild of `Pith.app` into `.build/xcode`
- `make run` — build, then open `Pith.app` (it shows the Panel; ⌥Space toggles it) with `-PithFixture $(FIXTURE)` (default `Fixtures/Demo.md`, `FIXTURE=<path>` for another text, both in a throwaway in-memory database; `FIXTURE=` (empty) for the real one in Application Support); `CONFIG=Release` for both to check performance by hand
- `make shots` — build, then PNGs of the real window in light and dark at 540 × 440 into `~/.scratch/pith/mvp/shots/<worktree>/` (`main` outside a worktree), for comparing with the artboards; needs Screen Recording for the terminal. `SURFACE=context-menu` for the open context menu (the PNG shows the window with the menu), `text-size` for the size pill at 17 pt, `save-failure` for the alert, `recorder` for the test window of the Shortcut recorder (three states in both themes); `FIXTURE=<path>` (default `Fixtures/Panel.md`) and `OUT=<folder>` override. A tiling window manager resizes the window: float Pith first. A new surface is a `case` in `showSurface` (`AppDelegate.swift`)
- `make bench` — restyle (also for a new text size), storage (autosave, open) and search (queries on 2000 Notes, reindexing after an edit) timings in release (`Sources/PithBench`); fails on a missed budget. `make test` asserts no timings

## Layout

- `Sources/PithEditor`, `Tests/PithEditorTests` — the core, no dependencies
- `Sources/PithNotes`, `Tests/PithNotesTests` — `Note`, `NoteStore` (SQLite, search: `Folding`, `SearchQuery`, FTS5 trigram), `Autosaver`; no AppKit; `PithApp` uses it
- `Sources/PithApp`, `Tests/PithAppTests` — AppKit shell (`PithApp.run()`): Panel and its Screens, Hotkey, menus, launch flags; default isolation MainActor
- `App` — Xcode target `Pith`, `main.swift` and `AppIcon.icon` (Icon Composer); `project.yml` generates `.xcodeproj` (not committed)
- `Fixtures` — sample texts for `make run` (`Demo.md`) and `make shots` (`Panel.md`, the text of the Main artboard; `TextSize.md`; `Empty.md` for the placeholder), not bundled
- `scripts` — `shots.sh` behind `make shots`

## Rules

- All repo content is in English: docs, comments, commit messages, PR descriptions. Conversations may be in any language.
- Never touch `layoutManager` on `EditorTextView` (it falls back to TextKit 1).
- Logic lives in the package; `App/` holds only `main.swift` and the app icon.

## Workflow

- `main` changes only through squash-merged pull requests; never commit on or push to `main` (`.claude/hooks/guard-main.sh` blocks it, a GitHub ruleset rejects it).
- One ticket = one worktree = one branch = one PR. Start with `claude -w <ticket-slug>` from the repo root; the worktree lives in `.claude/worktrees/<ticket-slug>`.
- Before opening a PR: `make test` passes, branch rebased on `origin/main`. Open it with `gh pr create`; CI (`.github/workflows/test.yml`) runs `make test` and `make build` on the `xcode-27` runner.
- Merge only when the user asks: `gh pr merge <n> --squash --delete-branch`.
