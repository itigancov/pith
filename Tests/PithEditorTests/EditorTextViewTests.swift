import AppKit
import Testing
@testable import PithEditor

@MainActor
struct EditorTextViewTests {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("local.pith.test.\(UUID().uuidString)"))
    }

    @Test func usesTextKit2() {
        let view = EditorTextView()
        #expect(view.textLayoutManager != nil)
    }

    @Test func pasteInsertsPlainTextOnly() throws {
        let view = EditorTextView()
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let rich = NSAttributedString(string: "hello", attributes: [
            .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 30), toHaveTrait: .boldFontMask),
            .foregroundColor: NSColor.red,
        ])
        let rtf = try rich.data(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString("hello", forType: .string)

        #expect(view.readSelection(from: pasteboard))

        let storage = try #require(view.textStorage)
        #expect(storage.string == "hello")
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color != NSColor.red)
        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize != 30)
    }

    @Test func copyWritesPlainTextOnly() throws {
        let view = EditorTextView()
        view.string = "**raw** markdown"
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        let legacyString = NSPasteboard.PasteboardType("NSStringPboardType")
        #expect(view.writeSelection(to: pasteboard, types: [.rtf, .rtfd, .html, legacyString]))

        #expect(pasteboard.string(forType: .string) == "**raw** markdown")
        #expect(pasteboard.data(forType: .rtf) == nil)
        #expect(pasteboard.data(forType: .rtfd) == nil)
        #expect(pasteboard.data(forType: .html) == nil)
    }

    @Test func settingTheStringStylesIt() throws {
        let view = EditorTextView()
        view.string = "# a\n**b**"
        let storage = try #require(view.textStorage)
        #expect(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont == .systemFont(ofSize: 14, weight: .bold))
        #expect(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == .monospacedSystemFont(ofSize: 13, weight: .regular))
        #expect(view.textLayoutManager != nil)
    }

    @Test func typingAttributesAreTheBaseOnes() {
        let view = EditorTextView()
        view.string = "# heading"
        view.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(view.typingAttributes[.font] as? NSFont == .systemFont(ofSize: 14))
        #expect(view.typingAttributes[.foregroundColor] as? NSColor == .labelColor)
        #expect((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple == 1.25)
    }

    @Test func typedTextIsStyled() throws {
        let view = EditorTextView()
        view.string = "a *b"
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.insertText("*", replacementRange: view.selectedRange())
        let storage = try #require(view.textStorage)
        #expect(storage.string == "a *b*")
        let traits = (storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits
        #expect(traits?.contains(.italic) == true)
    }

    @Test func undoRestoresTheTextAndItsStyle() throws {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let view = EditorTextView()
        view.allowsUndo = true
        window.contentView = view
        view.string = "a *b"
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.insertText("*", replacementRange: view.selectedRange())
        let undo = try #require(view.undoManager)
        undo.undo()
        let storage = try #require(view.textStorage)
        #expect(storage.string == "a *b")
        #expect(storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont == .systemFont(ofSize: 14))
        undo.redo()
        #expect(storage.string == "a *b*")
        #expect(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont == .monospacedSystemFont(ofSize: 13, weight: .regular))
    }

    @Test func autoSubstitutionsAreOffAndSpellCheckingIsOn() {
        let view = EditorTextView()
        #expect(!view.isAutomaticQuoteSubstitutionEnabled)
        #expect(!view.isAutomaticDashSubstitutionEnabled)
        #expect(!view.isAutomaticTextReplacementEnabled)
        #expect(!view.isAutomaticSpellingCorrectionEnabled)
        #expect(!view.smartInsertDeleteEnabled)
        #expect(!view.isAutomaticLinkDetectionEnabled)
        #expect(!view.isAutomaticDataDetectionEnabled)
        #expect(!view.isGrammarCheckingEnabled)
        #expect(view.isContinuousSpellCheckingEnabled)
    }
}
