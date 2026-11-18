# TextKit 2 and attributes in NSTextStorage

The editor is built on `NSTextView` with TextKit 2 (`init(usingTextLayoutManager: true)`). Styling is applied as attributes directly in `NSTextStorage`: `parse(text) -> [Span]`, then `theme.attributes(kind)`, then applying them to the storage. The text stays plain, so ⌘C yields raw Markdown. Any access to `layoutManager` silently switches the view to TextKit 1, so it must not be touched: in DEBUG a fallback is caught by `assertionFailure`, and a test checks `textLayoutManager != nil`.
