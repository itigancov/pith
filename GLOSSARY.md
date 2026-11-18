# Pith

A quick-notes app for macOS: Markdown notes with visible markup. This glossary is the shared vocabulary for code, tickets and conversations.

## Language

**Note**:
A single note: plain Markdown text that the user sees and edits as is.
_Avoid_: Document, file, page

**Stack**:
An ordered set of Notes that the user pages through. Out of scope for the prototype.
_Avoid_: Notebook, list of notes

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

**Toggle**:
A command that wraps text in a Marker or removes the wrapping in one action.
_Avoid_: Format, wrap, switch
