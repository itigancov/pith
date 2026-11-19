# Pith

A quick-notes app for macOS: Markdown notes with visible markup. This glossary is the shared vocabulary for code, tickets and conversations.

## Language

**Note**:
A single note: plain Markdown text that the user sees and edits as is.
_Avoid_: Document, file, page

**Panel**:
The window Pith shows over all apps when the user presses the hotkey. It holds one Note at a time and hides when the user leaves it.
_Avoid_: Window, popup, HUD

**Stack**:
All Notes not in the Trash, in the order they were created, that the user pages through. Editing a Note never moves it.
_Avoid_: Notebook, list of notes

**Blank**:
The empty Note at the end of the Stack, shown when the user creates a Note or pages past the last one. It becomes a Note only once the user types; a Note that is left empty stops being one.
_Avoid_: Draft, placeholder, new note

**Latest**:
The Note that ⌘1 jumps to: either the newest Note in the Stack or the last edited one, as the user chooses.
_Avoid_: Last, recent, current

**Trash**:
The Notes the user has deleted. They stay there until restored to their place in the Stack or deleted for good.
_Avoid_: Recently deleted, bin, archive

**Search**:
Finding Notes in the Stack by any piece of their text, ignoring case and accents. It lists the matching Notes, most recently edited first.
_Avoid_: Find, filter, lookup

**Block**:
A line-level unit of a Note: paragraph, heading, list item, task, quote. A code block is the one multi-line exception.
_Avoid_: Paragraph, section

**Inline**:
Markup inside a Block's paragraph: bold, italic, strikethrough, highlight, code, link, bare `http(s)://` URL. Never crosses a paragraph boundary.
_Avoid_: Run, style, format

**Span**:
A range of a Note's text together with its markup kind, produced by parsing the Note.
_Avoid_: Token, range, annotation

**Marker**:
The markup characters that stay in the text and are always visible: `**`, `#`, `- `, `> `.
_Avoid_: Delimiter, syntax, sigil

**Plate**:
A rounded fill drawn behind a highlight, an inline code or a whole code block, Markers included. Its kinds stack: inline code inside a highlight lies on a plate of its own on top of the highlight's.
_Avoid_: Background, box, pill

**Toggle**:
A command that wraps text in a Marker or removes the wrapping in one action.
_Avoid_: Format, wrap, switch

**Command**:
A pure edit of a Note, `(text, selection) -> TextEdit`, that the editor applies as one undo step.
_Avoid_: Action, operation
