# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Live-Markdown editor core on TextKit 2 (`PithEditor`).
- macOS app shell `Pith` (`PithApp`), built from an xcodegen project.
- The Panel opens the latest Note, saves it as you type and restores the cursor and scroll position after a restart.
- Text size 10–48 pt with ⌘+, ⌘− and ⌘0, shown in a pill; caret and selection in the Ink color; a placeholder in an empty Note.
- Alerts when the notes cannot be opened, were damaged, or cannot be saved.
