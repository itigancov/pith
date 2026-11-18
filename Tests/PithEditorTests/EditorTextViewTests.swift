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

    // MARK: Block behavior

    /// A view in a window, so it has an undo manager.
    private func makeEditor(_ text: String, selection: NSRange) -> (EditorTextView, NSWindow) {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let view = EditorTextView()
        view.allowsUndo = true
        window.contentView = view
        view.string = text
        view.setSelectedRange(selection)
        return (view, window)
    }

    /// Closes the undo group of the current event, as the run loop does after each key press.
    private func endEvent(_ undo: UndoManager) {
        RunLoop.current.run(mode: .default, before: Date())
    }

    @Test func newlineContinuesTheList() {
        let (view, window) = makeEditor("1. a\n2. b", selection: NSRange(location: 4, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "1. a\n2. \n3. b")
        #expect(view.selectedRange() == NSRange(location: 8, length: 0))
        _ = window
    }

    @Test func newlineOutsideAListIsPlain() {
        let (view, window) = makeEditor("text", selection: NSRange(location: 4, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "text\n")
        _ = window
    }

    @Test func oneUndoRevertsTheWholeCommandAndRedoRepeatsIt() throws {
        let (view, window) = makeEditor("1. a\n2. b\n3. c", selection: NSRange(location: 4, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "1. a\n2. \n3. b\n4. c")
        let undo = try #require(view.undoManager)
        undo.undo()
        #expect(view.string == "1. a\n2. b\n3. c")
        undo.redo()
        #expect(view.string == "1. a\n2. \n3. b\n4. c")
        _ = window
    }

    @Test func commandIsNotCoalescedWithTyping() throws {
        let (view, window) = makeEditor("- a", selection: NSRange(location: 3, length: 0))
        let undo = try #require(view.undoManager)
        view.insertText("b", replacementRange: view.selectedRange())
        endEvent(undo)
        view.insertNewline(nil)
        endEvent(undo)
        view.insertText("c", replacementRange: view.selectedRange())
        endEvent(undo)
        #expect(view.string == "- ab\n- c")
        undo.undo()
        #expect(view.string == "- ab\n- ")
        undo.undo()
        #expect(view.string == "- ab")
        _ = window
    }

    @Test func markedTextGetsTheStandardNewline() {
        let (view, window) = makeEditor("- a", selection: NSRange(location: 3, length: 0))
        view.setMarkedText("b", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        view.insertNewline(nil)
        #expect(!view.string.contains("\n- "))
        _ = window
    }

    @Test func tabNestsAndBacktabUnnestsAnItem() throws {
        let (view, window) = makeEditor("1. a\n2. b\n3. c", selection: NSRange(location: 9, length: 0))
        let undo = try #require(view.undoManager)
        view.insertTab(nil)
        endEvent(undo)
        #expect(view.string == "1. a\n  1. b\n2. c")
        #expect(view.selectedRange() == NSRange(location: 11, length: 0))
        view.insertBacktab(nil)
        endEvent(undo)
        #expect(view.string == "1. a\n2. b\n3. c")
        #expect(view.selectedRange() == NSRange(location: 9, length: 0))
        undo.undo()
        #expect(view.string == "1. a\n  1. b\n2. c")
        _ = window
    }

    @Test func tabOutsideAnItemInsertsATab() {
        let (view, window) = makeEditor("text", selection: NSRange(location: 4, length: 0))
        view.insertTab(nil)
        #expect(view.string == "text\t")
        _ = window
    }

    @Test func backtabAtLevelZeroDoesNothing() {
        let (view, window) = makeEditor("- a", selection: NSRange(location: 3, length: 0))
        view.insertBacktab(nil)
        #expect(view.string == "- a")
        _ = window
    }

    @Test func indentAndOutdentActions() {
        let (view, window) = makeEditor("- a\n- b", selection: NSRange(location: 7, length: 0))
        view.indent(nil)
        #expect(view.string == "- a\n  - b")
        view.outdent(nil)
        #expect(view.string == "- a\n- b")
        _ = window
    }

    @Test func indentOutsideAnItemDoesNothing() {
        let (view, window) = makeEditor("text", selection: NSRange(location: 4, length: 0))
        view.indent(nil)
        view.outdent(nil)
        #expect(view.string == "text")
        _ = window
    }

    @Test func commandRestylesTheChangedLines() throws {
        let (view, window) = makeEditor("- a\n- b", selection: NSRange(location: 7, length: 0))
        view.insertTab(nil)
        let storage = try #require(view.textStorage)
        let style = storage.attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.headIndent ?? 0) > (storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0)
        _ = window
    }
}
