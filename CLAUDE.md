# Pith

Prototype of a live-Markdown editor for macOS (NSTextView + TextKit 2). Vocabulary: [GLOSSARY.md](GLOSSARY.md), decisions: [docs/adr/](docs/adr/).

## Commands

- `make test` — `swift test` (`Pith` package, Swift Testing)
- `make build` — xcodegen + xcodebuild of `Pith.app` into `.build/xcode`
- `make run` — build, then open `Pith.app` (it shows the Panel; ⌥Space toggles it) with `-PithFixture $(FIXTURE)` (default `Fixtures/Demo.md`, `FIXTURE=<path>` for another text, both in a throwaway in-memory database; `FIXTURE=` (empty) for the real one in Application Support). `-PithStackSize N -PithStackIndex <i>|blank` fill that database with N short notes, the fixture at place i (from 1), and open it, or a Blank; `-PithLatest newest|last-edited` sets what ⌘1 jumps to; `CONFIG=Release` for both to check performance by hand
- `make shots` — build, then PNGs of the real window in light and dark at 540 × 440 into `~/.scratch/pith/mvp/shots/<worktree>/` (`main` outside a worktree), for comparing with the artboards; needs Screen Recording for the terminal. `SURFACE=context-menu` for the open context menu (the PNG shows the window with the menu), `context-menu-spelling` for it on the misspelled word “tetsers” (`Fixtures/ContextMenuSpelling.md`), `menu-bar` for the open menu of the menu bar icon (`Fixtures/Trash.json`, three Notes in the Trash), `text-size` for the size pill at 17 pt, `save-failure` for the alert, `recorder` for the test window of the Shortcut recorder (three states in both themes), `stack` (note 12 of 40, `Fixtures/Stack.md`), `stack-new` (a Blank after 7 notes) and `jump-latest` (note 10 of 10, `Fixtures/Standup.md`) for the lit footer of the Stack, `search-all` / `search-results` (query “region”) / `search-empty` (query “invoice”) / `search-select` (rows 2–4 selected, the 4th active) for Search (default `Fixtures/Search.json`, “now” fixed by `-PithNow`), `delete-undo` (⌘⌫ on the open Note of `Fixtures/DeleteUndo.json`, the toast held), `trash` (`Fixtures/Trash.json`, three deleted Notes), `trash-confirm` (Empty Trash alert) and `trash-delete` (Delete permanently alert), `settings` / `settings-shortcuts` (the Settings window on its tabs, own size, `Fixtures/Trash.json`, text size 14), `settings-login-approval` / `settings-outside-applications` (Settings on General with the Open at login row needing approval / outside Applications, by `-PithLoginItemState on|off|approval|outside|error`, which a fake login item answers, nothing is registered) and `move-alert` (the alert “Move Pith to Applications?”, moves nothing), `onboarding-hotkey` / `onboarding-ready` / `onboarding-ready-outside` (the onboarding window on its steps, the recorder of step 1 recording, nothing registered or stored; the last with Open at login outside Applications) and `welcome` (the Panel on the welcome Note, in an empty in-memory database, `Fixtures/Empty.md`); `FIXTURE=<path>` (default `Fixtures/Panel.md`) and `OUT=<folder>` override. A tiling window manager resizes the window: float Pith first. A new surface is a `case` in `showSurface` (`AppDelegate.swift`)
- `make bench` — restyle (also for a new text size), storage (autosave, open), search (queries on 2000 Notes, reindexing after an edit) and opening a 5k-line Note in the editor timings in release (`Sources/PithBench`); fails on a missed budget. `make test` asserts no timings

## Layout

- `Sources/PithEditor`, `Tests/PithEditorTests` — the core, no dependencies
- `Sources/PithNotes`, `Tests/PithNotesTests` — `Note`, `NoteStore` (SQLite, search: `Folding`, `SearchQuery`, FTS5 trigram), `Autosaver`, `Stack` and `StackDots` (paging and the footer's dots, pure), `TrashUndo` (the toast after ⌘⌫, pure); no AppKit; `PithApp` uses it
- `Sources/PithApp`, `Tests/PithAppTests` — AppKit shell (`PithApp.run()`): Panel and its Screens, Hotkey, menus, Settings (SwiftUI tabs in an `NSTabViewController`), launch flags; `LoginItem` (Open at login over `SMAppService`, the wish in `UserDefaults`), `InstallLocation` (in Applications or not), `ApplicationMover` and `MoveOffer` (the move to Applications at a launch from elsewhere, Release only), `LaunchEvent` (a login launch is quiet), `OnboardingModel` (whether the first-launch onboarding shows, its two steps, finishing, and the welcome Note put into an empty Stack; `OnboardingWindowController` and `OnboardingViews` are the window over it, `WelcomeNote` the text); default isolation MainActor
- `App` — Xcode target `Pith`, `main.swift` and `AppIcon.icon` (Icon Composer); `project.yml` generates `.xcodeproj` (not committed)
- `Fixtures` — sample texts for `make run` (`Demo.md`) and `make shots` (`Panel.md`, the text of the Main artboard; `TextSize.md`; `Stack.md`, `Standup.md`; `ContextMenuSpelling.md`, `Panel.md` with “tetsers”; `Empty.md` for the placeholder; `Search.json`, several Notes with `updatedAt` for the Search artboards, which `-PithFixture` also takes; `Trash.json`, the same with `deletedAt` for Notes in the Trash; `DeleteUndo.json`, two Notes with `Panel.md` last), not bundled
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
