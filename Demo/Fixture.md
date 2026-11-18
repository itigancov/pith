# Pith fixture
## Every supported element, as a visual checklist
### Third-level heading with **bold** and `code` inside

Plain paragraph text in SF Pro 14 with a line height multiple of 1.25. It is long enough to wrap onto a second line in a normal window, so the line spacing is visible.

Inline: **bold**, __bold too__, *italic*, _italic too_, ***bold italic***, ~~struck through~~, ==highlighted==, `inline code`.
Nesting: **bold with *italic* inside**, **a *b***, **bold `code`**, *italic `code`*, ==highlight with **bold**==, ~~struck **bold**~~.
Links: [link text](https://example.com/path), [**bold** link](https://example.com), bare https://example.com/page?q=1 and http://example.org.
Escapes: \*not italic\*, \_not italic\_, \`not code\`.
Lone and unpaired Markers stay text: a * b * c, snake_case_name, 2 * 3 = 6, **unclosed, *also unclosed, ~~open.
Emoji 🎉 inside **bold 🚀** and `code 🧪`.

- Bullet item
- Bullet item long enough to wrap onto the next line, so the wrapped part should line up with the text after the Marker, not with the Marker.
  - Nested bullet, two spaces in, also long enough to wrap so the hanging indent includes the leading spaces.
    - Third level
* Star bullet
+ Plus bullet

1. First
2. Second, long enough to wrap onto the next line so the wrapped text lines up after the number and its dot.
10. Tenth

- [ ] Open task
- [x] Done task: secondary color, no strikethrough, even with **bold** and https://example.com
- [ ] Open task long enough to wrap onto the next line, so the wrapped part lines up after the checkbox.
  - [x] Nested done task

> Quote with *italic* and a long enough line to wrap onto the next line, so the wrapped part lines up after the Marker.

```swift
let greeting = "**not bold** inside code"

func hello() { print(greeting) }
```

```
Code block without a language.
```

Last paragraph after the code blocks.
