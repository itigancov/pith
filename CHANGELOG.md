# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-27

### Added

- Live-Markdown editor core on TextKit 2 (`PithEditor`) and the macOS app shell `Pith` (`PithApp`).
- The Panel, a floating window that ⌥Space opens and hides without taking focus from the app you were in; Esc hides it, and it can be moved and resized.
- Notes in SQLite (`~/Library/Application Support/io.github.itigancov.pith`), saved as you type, with the cursor and scroll position restored after a restart; alerts when the notes cannot be opened, were damaged, or cannot be saved.
- Text size 10–48 pt with ⌘+, ⌘− and ⌘0, shown in a pill; Appearance (system, light or dark).
- The Stack of Notes: ⌘N for a new Note, swipe or ⇧⌘[ / ⇧⌘] to page, ⌘1 to jump to the latest Note, and a footer with dots and a counter.
- Search (⌘F) across all Notes with highlighted snippets, ⌘G / ⇧⌘G to step through matches, and selecting several results with ⇧ and ⌘ to move them to the Trash at once.
- Trash: ⌘⌫ moves a Note there with a toast to undo, Restore, Delete permanently and Empty Trash.
- The menu bar icon with its menu, a context menu of the editor and the main menu.
- Settings (⌘,): a recorder for the Open Pith Hotkey, Open at login, Appearance, text size, Trash, seven reassignable shortcuts and what “Go to latest note” means.
- Open at login, and an offer to move Pith to Applications when it starts from elsewhere.
- Onboarding on the first launch and a welcome Note in the first Stack.
- App icon and menu bar icon.
- Install with `brew install --cask itigancov/tap/pith`, or from the zip of a GitHub Release (universal, ad-hoc signed, not notarized).

[Unreleased]: https://github.com/itigancov/pith/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/itigancov/pith/releases/tag/v0.1.0
