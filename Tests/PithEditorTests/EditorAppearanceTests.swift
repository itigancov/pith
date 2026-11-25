import AppKit
import Testing
@testable import PithEditor

/// Theme changes, caret and selection colors, and the placeholder of `EditorTextView`.
@MainActor
struct EditorAppearanceTests {
    private func makeEditor(_ text: String) -> (EditorTextView, NSWindow) {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let view = EditorTextView()
        view.allowsUndo = true
        window.contentView = view
        view.string = text
        return (view, window)
    }

    private func font(_ view: EditorTextView, at index: Int) -> NSFont? {
        view.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    // MARK: Theme

    @Test func newThemeRestylesTheWholeNote() {
        let (view, window) = makeEditor("plain\n\n# head\n\nsome `code` here\n")
        view.theme = Theme(textSize: 20)
        #expect(font(view, at: 0) == .systemFont(ofSize: 20))
        let heading = (view.string as NSString).range(of: "head").location
        #expect(font(view, at: heading) == .systemFont(ofSize: 20, weight: .bold))
        let code = (view.string as NSString).range(of: "code").location
        #expect(font(view, at: code) == .monospacedSystemFont(ofSize: 19, weight: .regular))
        let last = view.string.utf16.count - 1
        #expect(font(view, at: last) == .systemFont(ofSize: 20))
        _ = window
    }

    @Test func newThemeChangesTypingAttributesAndLaterEdits() {
        let (view, window) = makeEditor("a")
        view.theme = Theme(textSize: 30)
        #expect(view.typingAttributes[.font] as? NSFont == .systemFont(ofSize: 30))
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(font(view, at: 1) == .systemFont(ofSize: 30))
        _ = window
    }

    @Test func newThemeKeepsPlatesAndTheirTextRestyled() throws {
        let (view, window) = makeEditor("a ==bc== d\n\n```\ncode\n```\n")
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        let before = view.plates.map(\.kind)
        view.theme = Theme(textSize: 24)
        #expect(view.plates.map(\.kind) == before)
        #expect(!view.plates.isEmpty)
        let tall = try #require(view.plates.first { $0.kind == .highlight })
        #expect(tall.frame.height > 24)
        _ = window
    }

    @Test func newThemeKeepsTheSelection() {
        let (view, window) = makeEditor("hello world")
        view.setSelectedRange(NSRange(location: 2, length: 3))
        view.theme = Theme(textSize: 18)
        #expect(view.selectedRange() == NSRange(location: 2, length: 3))
        _ = window
    }

    // MARK: Caret and selection

    @Test func caretIsInk() {
        #expect(EditorTextView().insertionPointColor == Theme.ink)
    }

    @Test func selectionIsOnlyABackgroundAndKeepsTheTextColor() {
        let attributes = EditorTextView().selectedTextAttributes
        #expect(Set(attributes.keys) == [.backgroundColor])
    }

    @Test func selectionIsInkAt22PercentInLightAnd30InDark() throws {
        func resolved(_ name: NSAppearance.Name) throws -> (rgb: [Int], alpha: Int) {
            var color: NSColor?
            let attributes = EditorTextView().selectedTextAttributes
            try #require(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
                color = (attributes[.backgroundColor] as? NSColor)?.usingColorSpace(.sRGB)
            }
            let c = try #require(color)
            return ([c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }, Int((c.alphaComponent * 100).rounded()))
        }
        let light = try resolved(.aqua)
        let dark = try resolved(.darkAqua)
        #expect(light.rgb == [0x3B, 0x5B, 0xDB] && light.alpha == 22)
        #expect(dark.rgb == [0x8D, 0xA2, 0xF5] && dark.alpha == 30)
    }

    // MARK: Placeholder

    @Test func placeholderShowsOnlyWhileTheNoteIsEmpty() {
        let (view, window) = makeEditor("")
        view.placeholder = "Start typing"
        #expect(view.isShowingPlaceholder)
        view.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.isShowingPlaceholder)
        view.string = ""
        #expect(view.isShowingPlaceholder)
        _ = window
    }

    @Test func placeholderHidesWhileInputMethodTextIsComposed() {
        let (view, window) = makeEditor("")
        view.placeholder = "Start typing"
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.isShowingPlaceholder)
        view.insertText("か", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.isShowingPlaceholder)
        _ = window
    }

    @Test func noPlaceholderTextMeansNothingToShow() {
        let (view, window) = makeEditor("")
        #expect(!view.isShowingPlaceholder)
        _ = window
    }

    @Test func accessibilityGetsTheNoteLabelAndThePlaceholder() {
        let view = EditorTextView()
        view.placeholder = "Start typing"
        #expect(view.accessibilityLabel() == "Note")
        #expect(view.accessibilityPlaceholderValue() == "Start typing")
    }
}
