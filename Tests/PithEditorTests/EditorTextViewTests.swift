import AppKit
import Testing
@testable import PithEditor

struct FormattingCase: Sendable, CustomTestStringConvertible {
    let name: String
    let before: String
    let after: String
    let perform: @MainActor @Sendable (EditorTextView) -> Void

    var testDescription: String { name }
}

private let formattingCases: [FormattingCase] = [
    .init(name: "toggleBold", before: "a «b» c", after: "a **«b»** c") { $0.toggleBold(nil) },
    .init(name: "toggleItalic", before: "a «b» c", after: "a *«b»* c") { $0.toggleItalic(nil) },
    .init(name: "toggleHighlight", before: "a «b» c", after: "a ==«b»== c") { $0.toggleHighlight(nil) },
    .init(name: "toggleStrikethrough", before: "a «b» c", after: "a ~~«b»~~ c") { $0.toggleStrikethrough(nil) },
    .init(name: "toggleCode", before: "a «b» c", after: "a `«b»` c") { $0.toggleCode(nil) },
    .init(name: "toggleLink", before: "a «b» c", after: "a [b](|) c") { $0.toggleLink(nil) },
    .init(name: "toggleHeading1", before: "a|", after: "# a|") { $0.toggleHeading1(nil) },
    .init(name: "toggleHeading2", before: "a|", after: "## a|") { $0.toggleHeading2(nil) },
    .init(name: "toggleHeading3", before: "a|", after: "### a|") { $0.toggleHeading3(nil) },
    .init(name: "toggleBulletList", before: "«a\nb»", after: "- «a\n- b»") { $0.toggleBulletList(nil) },
    .init(name: "toggleOrderedList", before: "«a\nb»", after: "1. «a\n2. b»") { $0.toggleOrderedList(nil) },
    .init(name: "toggleTaskList", before: "«a\nb»", after: "- [ ] «a\n- [ ] b»") { $0.toggleTaskList(nil) },
    .init(name: "toggleQuote", before: "«a\nb»", after: "> «a\n> b»") { $0.toggleQuote(nil) },
    .init(name: "toggleCodeBlock", before: "«a\nb»", after: "```|\na\nb\n```") { $0.toggleCodeBlock(nil) },
]

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

    // MARK: Tasks

    @Test func toggleTaskActionTogglesAndKeepsTheSelection() {
        let (view, window) = makeEditor("- [ ] a\n- [ ] b", selection: NSRange(location: 3, length: 9))
        view.toggleTask(nil)
        #expect(view.string == "- [x] a\n- [x] b")
        #expect(view.selectedRange() == NSRange(location: 3, length: 9))
        _ = window
    }

    @Test func oneUndoRevertsAToggleAndRedoRepeatsIt() throws {
        let (view, window) = makeEditor("- [ ] a\n- [x] b\n- [ ] c", selection: NSRange(location: 0, length: 23))
        let undo = try #require(view.undoManager)
        view.toggleTask(nil)
        endEvent(undo)
        #expect(view.string == "- [x] a\n- [x] b\n- [x] c")
        undo.undo()
        #expect(view.string == "- [ ] a\n- [x] b\n- [ ] c")
        undo.redo()
        #expect(view.string == "- [x] a\n- [x] b\n- [x] c")
        _ = window
    }

    @Test func toggleIsNotCoalescedWithTyping() throws {
        let (view, window) = makeEditor("- [ ] a", selection: NSRange(location: 7, length: 0))
        let undo = try #require(view.undoManager)
        view.insertText("b", replacementRange: view.selectedRange())
        endEvent(undo)
        view.toggleTask(nil)
        endEvent(undo)
        #expect(view.string == "- [x] ab")
        undo.undo()
        #expect(view.string == "- [ ] ab")
        undo.undo()
        #expect(view.string == "- [ ] a")
        _ = window
    }

    @Test func toggleTaskDoesNothingWhileComposing() {
        let (view, window) = makeEditor("- [ ] a", selection: NSRange(location: 7, length: 0))
        view.setMarkedText("b", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.toggleTask(nil)
        #expect(view.string == "- [ ] ab")
        #expect(view.hasMarkedText())
        _ = window
    }

    @Test func toggleRestylesTheTask() throws {
        let (view, window) = makeEditor("- [ ] a", selection: NSRange(location: 7, length: 0))
        let storage = try #require(view.textStorage)
        #expect(storage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor == .labelColor)
        view.toggleTask(nil)
        #expect(storage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor == .secondaryLabelColor)
        view.toggleTask(nil)
        #expect(storage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor == .labelColor)
        _ = window
    }

    @Test func clickOnACheckboxCharacterTogglesAndKeepsTheSelection() throws {
        let (view, window) = makeEditor("text\n  - [ ] a\n- [x] b", selection: NSRange(location: 1, length: 2))
        let undo = try #require(view.undoManager)
        for index in 9...11 {
            #expect(view.toggleTask(atCharacter: index))
            endEvent(undo)
            #expect(view.selectedRange() == NSRange(location: 1, length: 2))
        }
        #expect(view.string == "text\n  - [x] a\n- [x] b")
        #expect(view.toggleTask(atCharacter: 17))
        #expect(view.string == "text\n  - [x] a\n- [ ] b")
        #expect(view.selectedRange() == NSRange(location: 1, length: 2))
        undo.undo()
        #expect(view.string == "text\n  - [x] a\n- [x] b")
        #expect(view.selectedRange() == NSRange(location: 1, length: 2))
        _ = window
    }

    @Test func clickOutsideACheckboxCharacterDoesNotToggle() {
        let text = "text\n  - [ ] a\n- [x] b\n1. [ ] n"
        let (view, window) = makeEditor(text, selection: NSRange(location: 1, length: 0))
        for index in [0, 5, 6, 7, 8, 12, 13, 14, 15, 16, 20, 21, 22, 26, 27] {
            #expect(!view.toggleTask(atCharacter: index), "index \(index)")
        }
        #expect(view.string == text)
        _ = window
    }

    /// Lays the view out and returns where its glyphs are, in view coordinates.
    /// Markers are monospaced; glyphs start after the line fragment padding, indent spaces are in the text font.
    private func layOut(_ view: EditorTextView) throws -> (_ column: CGFloat, _ line: Int, _ indentSpaces: Int) -> NSPoint {
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        let layout = try #require(view.textLayoutManager)
        layout.ensureLayout(for: layout.documentRange)
        let mono = NSFont.monospacedSystemFont(ofSize: Theme().monoSize, weight: .regular)
        let columnWidth = ("0" as NSString).size(withAttributes: [.font: mono]).width
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: Theme().textSize)]).width
        let left = view.textContainerOrigin.x + (view.textContainer?.lineFragmentPadding ?? 0)
        let lineHeight = try #require(layout.textLayoutFragment(for: layout.documentRange.location)).layoutFragmentFrame.height
        let top = view.textContainerOrigin.y
        return { column, line, indentSpaces in
            NSPoint(x: left + CGFloat(indentSpaces) * spaceWidth + column * columnWidth, y: top + (CGFloat(line) + 0.5) * lineHeight)
        }
    }

    @Test func pointOnACheckboxHitsIt() throws {
        let (view, window) = makeEditor("- [ ] a\n  - [x] b", selection: NSRange(location: 0, length: 0))
        let point = try layOut(view)
        #expect(view.checkboxCharacter(at: point(2.2, 0, 0)) == 2)
        #expect(view.checkboxCharacter(at: point(3.5, 0, 0)) == 2)
        #expect(view.checkboxCharacter(at: point(4.8, 0, 0)) == 2)
        #expect(view.checkboxCharacter(at: point(1.5, 0, 0)) == nil)
        #expect(view.checkboxCharacter(at: point(5.5, 0, 0)) == nil)
        #expect(view.checkboxCharacter(at: point(7, 0, 0)) == nil)
        #expect(view.checkboxCharacter(at: point(3.5, 1, 2)) == 12)
        #expect(view.checkboxCharacter(at: point(1, 1, 2)) == nil)
        #expect(view.checkboxCharacter(at: point(3.5, 3, 0)) == nil)
        _ = window
    }

    @Test func plainClickOnACheckboxTogglesWithoutMovingTheCaretAndFocusesTheEditor() throws {
        let (view, window) = makeEditor("- [ ] a", selection: NSRange(location: 7, length: 0))
        let point = try layOut(view)
        window.makeFirstResponder(nil)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: view.convert(point(3.5, 0, 0), to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        view.mouseDown(with: event)
        #expect(view.string == "- [x] a")
        #expect(view.selectedRange() == NSRange(location: 7, length: 0))
        #expect(window.firstResponder === view)
    }

    // MARK: Links

    /// An editor whose opener records the addresses instead of opening them.
    private func makeLinkEditor(_ text: String, selection: NSRange) -> (EditorTextView, NSWindow, () -> [String]) {
        let (view, window) = makeEditor(text, selection: selection)
        var opened: [String] = []
        view.openURL = { opened.append($0.absoluteString) }
        return (view, window, { opened })
    }

    @Test func openOnAURLOpensItAndKeepsTheTextAndSelection() {
        let text = "a [t](x.com) https://y.com"
        let (view, window, opened) = makeLinkEditor(text, selection: NSRange(location: 1, length: 2))
        #expect(view.follow(.open, atCharacter: 7))
        #expect(view.follow(.open, atCharacter: 13))
        #expect(opened() == ["https://x.com", "https://y.com"])
        #expect(view.string == text)
        #expect(view.selectedRange() == NSRange(location: 1, length: 2))
        _ = window
    }

    @Test func selectOnAURLSelectsExactlyIt() {
        let (view, window, opened) = makeLinkEditor("a [t](x.com) b", selection: NSRange(location: 0, length: 0))
        #expect(view.follow(.select, atCharacter: 10))
        #expect(Marked(text: view.string, selection: view.selectedRange()) == Marked("a [t](«x.com») b"))
        #expect(opened() == [])
        _ = window
    }

    @Test func pressOutsideAClickableURLDoesNothing() {
        let text = "a [t](x.com) [e]() `https://z.com` [w](http://[x)"
        let (view, window, opened) = makeLinkEditor(text, selection: NSRange(location: 1, length: 0))
        for index in [0, 3, 5, 11, 17, 25, 40] {
            #expect(!view.follow(.open, atCharacter: index), "index \(index)")
            #expect(!view.follow(.select, atCharacter: index), "index \(index)")
        }
        #expect(!view.follow(.drag, atCharacter: 7))
        #expect(opened() == [])
        #expect(view.string == text)
        #expect(view.selectedRange() == NSRange(location: 1, length: 0))
        _ = window
    }

    @Test func pressOnAURLDoesNothingWhileComposing() {
        let (view, window, opened) = makeLinkEditor("[t](x.com) ", selection: NSRange(location: 11, length: 0))
        view.setMarkedText("b", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.follow(.open, atCharacter: 5))
        #expect(!view.follow(.select, atCharacter: 5))
        #expect(opened() == [])
        #expect(view.hasMarkedText())
        _ = window
    }

    /// Lays the view out and returns the middle of the glyph of the character at an index, in view coordinates.
    private func glyphCenters(_ view: EditorTextView) throws -> (Int) throws -> NSPoint {
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        let layout = try #require(view.textLayoutManager)
        layout.ensureLayout(for: layout.documentRange)
        return { index in
            let start = try #require(layout.location(layout.documentRange.location, offsetBy: index))
            let range = try #require(NSTextRange(location: start, end: layout.location(start, offsetBy: 1)))
            var frame = CGRect.null
            layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, _, _ in
                frame = segment
                return false
            }
            return NSPoint(x: frame.midX + view.textContainerOrigin.x, y: frame.midY + view.textContainerOrigin.y)
        }
    }

    @Test func pointOnAURLsGlyphsHitsIt() throws {
        let (view, window) = makeEditor("[t](x.com) https://y.com\n- [ ] [e]() [w](http://[x) `https://z.com`", selection: NSRange(location: 0, length: 0))
        let center = try glyphCenters(view)
        #expect(view.urlCharacter(at: try center(4)) == 4)
        #expect(view.urlCharacter(at: try center(8)) == 4)
        #expect(view.urlCharacter(at: try center(11)) == 11)
        #expect(view.urlCharacter(at: try center(23)) == 11)
        for index in [0, 1, 3, 9, 10, 25, 31, 33, 39, 43, 56] {
            #expect(view.urlCharacter(at: try center(index)) == nil, "index \(index)")
        }
        // Past the end of the line.
        #expect(view.urlCharacter(at: NSPoint(x: 290, y: try center(23).y)) == nil)
        _ = window
    }

    @Test func aWrappedURLIsHitOnBothLines() throws {
        let url = "https://example.com/" + String(repeating: "abcdefgh/", count: 8)
        let (view, window) = makeEditor("see " + url, selection: NSRange(location: 0, length: 0))
        let center = try glyphCenters(view)
        let first = try center(4)
        let last = try center(3 + url.utf16.count)
        #expect(last.y > first.y)
        #expect(view.urlCharacter(at: first) == 4)
        #expect(view.urlCharacter(at: last) == 4)
        _ = window
    }

    // MARK: Blocks of the last scan

    @Test func hitTestingFindsTargetsShiftedByAnEdit() throws {
        let (view, window, opened) = makeLinkEditor("- [ ] a https://x.com", selection: NSRange(location: 0, length: 0))
        view.insertText("line\n\n", replacementRange: NSRange(location: 0, length: 0))
        #expect(view.string == "line\n\n- [ ] a https://x.com")
        let center = try glyphCenters(view)
        #expect(view.checkboxCharacter(at: try center(9)) == 8)
        #expect(view.checkboxCharacter(at: try center(3)) == nil)
        #expect(view.urlCharacter(at: try center(16)) == 14)
        #expect(view.urlCharacter(at: try center(10)) == nil)
        #expect(view.toggleTask(atCharacter: 9))
        #expect(!view.toggleTask(atCharacter: 3))
        #expect(view.string == "line\n\n- [x] a https://x.com")
        #expect(view.follow(.open, atCharacter: 20))
        #expect(!view.follow(.open, atCharacter: 2))
        #expect(opened() == ["https://x.com"])
        _ = window
    }

    @Test func nothingIsHitWhileComposing() throws {
        let (view, window) = makeEditor("- [ ] a https://x.com ", selection: NSRange(location: 22, length: 0))
        let center = try glyphCenters(view)
        let checkbox = try center(3)
        let url = try center(12)
        compose(view, "か")
        #expect(view.checkboxCharacter(at: checkbox) == nil)
        #expect(view.urlCharacter(at: url) == nil)
        commit(view, "か")
        #expect(view.checkboxCharacter(at: checkbox) == 2)
        #expect(view.urlCharacter(at: url) == 8)
        _ = window
    }

    // MARK: Input methods

    private func compose(_ view: EditorTextView, _ marked: String) {
        let length = (marked as NSString).length
        view.setMarkedText(marked, selectedRange: NSRange(location: length, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func commit(_ view: EditorTextView, _ text: String) {
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func font(_ view: EditorTextView, at index: Int) -> NSFont? {
        view.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func isItalic(_ view: EditorTextView, at index: Int) -> Bool {
        font(view, at: index)?.fontDescriptor.symbolicTraits.contains(.italic) == true
    }

    @Test func composingLeavesTheStylesAsTheyWereUntilCommit() {
        let (view, window) = makeEditor("*a", selection: NSRange(location: 2, length: 0))
        compose(view, "*")
        #expect(view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: 2, length: 1))
        #expect(!isItalic(view, at: 1))
        #expect(font(view, at: 2) == .systemFont(ofSize: Theme().textSize))
        commit(view, "*")
        #expect(!view.hasMarkedText())
        #expect(isItalic(view, at: 1))
        _ = window
    }

    @Test func markedTextInsideASpanHasTheBaseStyle() {
        let (view, window) = makeEditor("**ab**", selection: NSRange(location: 3, length: 0))
        compose(view, "か")
        #expect(font(view, at: 3) == .systemFont(ofSize: Theme().textSize))
        #expect(font(view, at: 2) == .systemFont(ofSize: Theme().textSize, weight: .bold))
        #expect(font(view, at: 4) == .systemFont(ofSize: Theme().textSize, weight: .bold))
        _ = window
    }

    @Test func aSeriesOfCompositionChangesKeepsTheMarkedText() {
        let (view, window) = makeEditor("**ab**", selection: NSRange(location: 3, length: 0))
        for marked in ["k", "か", "かn", "かな"] {
            compose(view, marked)
            #expect(view.hasMarkedText(), "\(marked)")
        }
        #expect(view.string == "**aかなb**")
        #expect(view.markedRange() == NSRange(location: 3, length: 2))
        _ = window
    }

    @Test func committedTextInsideStrongIsBold() {
        let (view, window) = makeEditor("**ab**", selection: NSRange(location: 3, length: 0))
        compose(view, "か")
        compose(view, "かんじ")
        commit(view, "漢字")
        #expect(view.string == "**a漢字b**")
        #expect(!view.hasMarkedText())
        #expect(font(view, at: 3) == .systemFont(ofSize: Theme().textSize, weight: .bold))
        #expect(font(view, at: 4) == .systemFont(ofSize: Theme().textSize, weight: .bold))
        _ = window
    }

    @Test func unmarkingCommitsTheMarkedTextStyled() {
        let (view, window) = makeEditor("*a", selection: NSRange(location: 2, length: 0))
        compose(view, "*")
        view.unmarkText()
        #expect(view.string == "*a*")
        #expect(!view.hasMarkedText())
        #expect(isItalic(view, at: 1))
        _ = window
    }

    @Test func cancellingLeavesTheNoteStyledAsBefore() {
        let (view, window) = makeEditor("*a", selection: NSRange(location: 2, length: 0))
        compose(view, "*")
        compose(view, "")
        #expect(view.string == "*a")
        #expect(!view.hasMarkedText())
        #expect(!isItalic(view, at: 1))
        // The next edit is styled as usual.
        view.insertText("*", replacementRange: view.selectedRange())
        #expect(isItalic(view, at: 1))
        _ = window
    }

    @Test func compositionThatShiftsTheBlocksBelowIsStyledOnCommit() {
        let (view, window) = makeEditor("a\n**b**\n# c", selection: NSRange(location: 1, length: 0))
        compose(view, "x")
        compose(view, "xy")
        commit(view, "Z")
        #expect(view.string == "aZ\n**b**\n# c")
        #expect(font(view, at: 5) == .systemFont(ofSize: Theme().textSize, weight: .bold))
        #expect(font(view, at: 11) == .systemFont(ofSize: Theme().textSize, weight: .bold))
        _ = window
    }

    @Test func settingTheStringWhileComposingStylesIt() {
        let (view, window) = makeEditor("a", selection: NSRange(location: 1, length: 0))
        compose(view, "か")
        view.string = "**b**"
        #expect(font(view, at: 2) == .systemFont(ofSize: Theme().textSize, weight: .bold))
        view.insertText("*c*", replacementRange: NSRange(location: 5, length: 0))
        #expect(isItalic(view, at: 6))
        _ = window
    }

    @Test(arguments: ["z", "ж"])
    func cyrillicInputStylesLikeLatin(_ letter: String) {
        let (view, window) = makeEditor("**ab** *c", selection: NSRange(location: 3, length: 0))
        view.insertText(letter, replacementRange: view.selectedRange())
        #expect(font(view, at: 3) == .systemFont(ofSize: Theme().textSize, weight: .bold))
        view.setSelectedRange(NSRange(location: 10, length: 0))
        view.insertText(letter + "*", replacementRange: view.selectedRange())
        #expect(isItalic(view, at: 9))
        #expect(isItalic(view, at: 10))
        _ = window
    }

    // MARK: Formatting

    @Test(arguments: formattingCases)
    func formattingActionAppliesItsCommandAsOneUndoStep(_ formatting: FormattingCase) throws {
        let before = Marked(formatting.before)
        let after = Marked(formatting.after)
        let (view, window) = makeEditor(before.text, selection: before.selection)
        let undo = try #require(view.undoManager)
        formatting.perform(view)
        endEvent(undo)
        #expect(Marked(text: view.string, selection: view.selectedRange()) == after)
        undo.undo()
        #expect(view.string == before.text)
        undo.redo()
        #expect(view.string == after.text)
        _ = window
    }

    @Test func formattingIsNotCoalescedWithTyping() throws {
        let (view, window) = makeEditor("a", selection: NSRange(location: 1, length: 0))
        let undo = try #require(view.undoManager)
        view.insertText("b", replacementRange: view.selectedRange())
        endEvent(undo)
        view.toggleBold(nil)
        endEvent(undo)
        view.insertText("c", replacementRange: view.selectedRange())
        endEvent(undo)
        #expect(view.string == "**abc**")
        undo.undo()
        #expect(view.string == "**ab**")
        undo.undo()
        #expect(view.string == "ab")
        _ = window
    }

    @Test func formattingDoesNothingWhileComposing() {
        let (view, window) = makeEditor("a ", selection: NSRange(location: 2, length: 0))
        view.setMarkedText("b", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.toggleBold(nil)
        view.toggleBulletList(nil)
        #expect(view.string == "a b")
        #expect(view.hasMarkedText())
        _ = window
    }

    @Test func formattingRestylesTheResult() throws {
        let (view, window) = makeEditor("a b", selection: NSRange(location: 2, length: 1))
        view.toggleBold(nil)
        let storage = try #require(view.textStorage)
        let traits = (storage.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits
        #expect(traits?.contains(.bold) == true)
        _ = window
    }

    // MARK: Plates

    /// A laid-out editor on `text`, 300pt wide with the demo's 16pt inset.
    private func makeLaidOutEditor(_ text: String) throws -> (EditorTextView, NSWindow) {
        let (view, window) = makeEditor(text, selection: NSRange(location: 0, length: 0))
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        let layout = try #require(view.textLayoutManager)
        layout.ensureLayout(for: layout.documentRange)
        return (view, window)
    }

    /// The frames of the glyphs of `range` (UTF-16), one per line, in view coordinates.
    private func glyphLines(_ view: EditorTextView, _ range: NSRange) throws -> [CGRect] {
        let layout = try #require(view.textLayoutManager)
        let start = try #require(layout.location(layout.documentRange.location, offsetBy: range.location))
        let textRange = try #require(NSTextRange(location: start, end: layout.location(start, offsetBy: range.length)))
        var lines: [CGRect] = []
        layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, segment, _, _ in
            lines.append(segment.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y))
            return true
        }
        return lines
    }

    private func range(_ substring: String, in view: EditorTextView) -> NSRange {
        (view.string as NSString).range(of: substring)
    }

    /// The left and right edges of the text in view coordinates: the container inside its line fragment padding.
    private func textEdges(_ view: EditorTextView) throws -> (left: CGFloat, right: CGFloat) {
        let container = try #require(view.textContainer)
        let left = view.textContainerOrigin.x + container.lineFragmentPadding
        return (left, view.textContainerOrigin.x + container.size.width - container.lineFragmentPadding)
    }

    @Test func shortHighlightIsOnePlateTwoPointsWiderThanItsGlyphsAndAsTallAsTheFont() throws {
        let (view, window) = try makeLaidOutEditor("a ==bc== d")
        let glyphs = try #require(try glyphLines(view, range("==bc==", in: view)).first)
        let plate = try #require(view.plates.first)
        #expect(view.plates.count == 1)
        #expect(plate.kind == .highlight)
        #expect(abs(plate.frame.minX - (glyphs.minX - 2)) < 0.01)
        #expect(abs(plate.frame.maxX - (glyphs.maxX + 2)) < 0.01)
        #expect(plate.frame.height > Theme().textSize)
        #expect(plate.frame.height < glyphs.height)
        #expect(plate.frame.minY > glyphs.minY)
        #expect(plate.roundsTop && plate.roundsBottom)
        _ = window
    }

    @Test func wrappedHighlightIsOneRoundedPlatePerLineAndThePlatesDoNotTouch() throws {
        let words = Array(repeating: "highlighted", count: 8).joined(separator: " ")
        let (view, window) = try makeLaidOutEditor("a ==\(words)== b")
        let lines = try glyphLines(view, range("==\(words)==", in: view))
        let plates = view.plates
        #expect(lines.count > 1)
        #expect(plates.count == lines.count)
        #expect(plates.allSatisfy { $0.kind == .highlight && $0.roundsTop && $0.roundsBottom })
        for (upper, lower) in zip(plates, plates.dropFirst()) {
            #expect(upper.frame.maxY < lower.frame.minY)
        }
        #expect(abs(plates[0].frame.minX - (lines[0].minX - 2)) < 0.01)
        let last = try #require(lines.last)
        #expect(abs(plates[plates.count - 1].frame.maxX - (last.maxX + 2)) < 0.01)
        _ = window
    }

    @Test func inlineCodeInsideAHighlightIsAPlateOnTopOfTheHighlightPlate() throws {
        let (view, window) = try makeLaidOutEditor("x ==a `b` c== y")
        let plates = view.plates
        #expect(plates.map(\.kind) == [.highlight, .inlineCode])
        let highlight = try #require(plates.first)
        let code = try #require(plates.last)
        #expect(highlight.frame.contains(code.frame))
        let codeGlyphs = try #require(try glyphLines(view, range("`b`", in: view)).first)
        #expect(abs(code.frame.minX - (codeGlyphs.minX - 2)) < 0.01)
        #expect(abs(code.frame.maxX - (codeGlyphs.maxX + 2)) < 0.01)
        _ = window
    }

    @Test func codeBlockIsOneRectangleSixPointsPastTheTextWithRoundedEnds() throws {
        let (view, window) = try makeLaidOutEditor("a\n```swift\nlet x = 1\n\n```\nb")
        let plates = view.plates
        let edges = try textEdges(view)
        // One plate per paragraph: both fences, the body line and the empty line.
        #expect(plates.count == 4)
        #expect(plates.allSatisfy { $0.kind == .codeBlock })
        for plate in plates {
            #expect(abs(plate.frame.minX - (edges.left - 6)) < 0.01)
            #expect(abs(plate.frame.maxX - (edges.right + 6)) < 0.01)
        }
        for (upper, lower) in zip(plates, plates.dropFirst()) {
            #expect(abs(upper.frame.maxY - lower.frame.minY) < 0.01)
        }
        #expect(plates.map(\.roundsTop) == [true, false, false, false])
        #expect(plates.map(\.roundsBottom) == [false, false, false, true])

        // Padding inside the plate; the paragraphs around it stay clear.
        let top = plates[0].frame.minY
        let bottom = plates[3].frame.maxY
        let opening = try #require(try glyphLines(view, range("```swift", in: view)).first)
        let closing = try #require(try glyphLines(view, NSRange(location: range("```\nb", in: view).location, length: 3)).first)
        #expect(opening.minY - top >= 4 - 0.01)
        #expect(bottom - closing.maxY >= 4 - 0.01)
        let before = try #require(try glyphLines(view, range("a", in: view)).first)
        let after = try #require(try glyphLines(view, NSRange(location: view.string.utf16.count - 1, length: 1)).first)
        #expect(top >= before.maxY - 0.01)
        #expect(bottom <= after.minY + 0.01)
        _ = window
    }

    @Test func codeTextLinesUpWithTheTextOfTheNote() throws {
        let (view, window) = try makeLaidOutEditor("a\n```\nlet x = 1\n```")
        let text = try #require(try glyphLines(view, range("a", in: view)).first)
        let code = try #require(try glyphLines(view, range("let", in: view)).first)
        #expect(abs(text.minX - code.minX) < 0.01)
        _ = window
    }

    @Test func longCodeLineWrapsInsideThePlateFromTheSameLeftEdge() throws {
        let line = Array(repeating: "let value = 1;", count: 6).joined(separator: " ")
        let (view, window) = try makeLaidOutEditor("```\n\(line)\n```")
        let lines = try glyphLines(view, range(line, in: view))
        let edges = try textEdges(view)
        #expect(lines.count > 1)
        #expect(lines.allSatisfy { abs($0.minX - lines[0].minX) < 0.01 && $0.maxX <= edges.right + 0.01 })
        #expect(view.plates.count == 3)
        _ = window
    }

    @Test func emptyCodeBlockHasAPlate() throws {
        let (view, window) = try makeLaidOutEditor("```\n```")
        let plates = view.plates
        #expect(plates.count == 2)
        #expect(plates.map(\.roundsTop) == [true, false])
        #expect(plates.map(\.roundsBottom) == [false, true])
        _ = window
    }

    @Test func unclosedCodeBlockPlateRunsToTheEndWithRoundedBottom() throws {
        let (view, window) = try makeLaidOutEditor("a\n```\nx\ny")
        let plates = view.plates
        #expect(plates.count == 3)
        #expect(plates.map(\.roundsBottom) == [false, false, true])
        _ = window
    }

    @Test func codeBlockAtTheStartOfTheNoteKeepsItsTopPadding() throws {
        let (view, window) = try makeLaidOutEditor("```\na\n```")
        let top = try #require(view.plates.first).frame.minY
        let opening = try #require(try glyphLines(view, NSRange(location: 0, length: 3)).first)
        #expect(abs(opening.minY - top - 4) < 0.01)
        _ = window
    }

    @Test func closedCodeBlockAtTheEndLeavesTheEmptyLastLineOffItsPlate() throws {
        let (view, window) = try makeLaidOutEditor("```\na\n```\n")
        let bottom = try #require(view.plates.last).frame.maxY
        let closing = try #require(try glyphLines(view, NSRange(location: 6, length: 3)).first)
        #expect(abs(bottom - closing.maxY - 4) < 0.01)
        _ = window
    }

    @Test func unclosedCodeBlockCoversTheEmptyLastLine() throws {
        let (view, window) = try makeLaidOutEditor("```\na\n")
        let plate = try #require(view.plates.last)
        // The empty line after the last line break belongs to the layout of the last paragraph.
        let layout = try #require(view.textLayoutManager)
        let lineStart = try #require(layout.location(layout.documentRange.location, offsetBy: 4))
        let last = try #require(layout.textLayoutFragment(for: lineStart))
        let emptyLine = try #require(last.textLineFragments.last)
        #expect(emptyLine.characterRange.length == 0)
        let emptyLineBottom = last.layoutFragmentFrame.minY + emptyLine.typographicBounds.maxY + view.textContainerOrigin.y
        #expect(plate.frame.maxY >= emptyLineBottom - 0.01)
        #expect(plate.roundsBottom)
        _ = window
    }

    @Test func adjacentCodeBlocksAreSeparatePlates() throws {
        let (view, window) = try makeLaidOutEditor("```\na\n```\n```\nb\n```")
        let plates = view.plates
        #expect(plates.map(\.roundsTop) == [true, false, false, true, false, false])
        #expect(plates.map(\.roundsBottom) == [false, false, true, false, false, true])
        _ = window
    }

    @Test func codeBlockCornersFollowEditsAroundIt() throws {
        let (view, window) = try makeLaidOutEditor("```\na\nb\n```\nc")
        #expect(view.plates.map(\.roundsBottom) == [false, false, false, true])
        // Without its closing fence the block runs on through `c`, to the end of the Note.
        let closing = (view.string as NSString).range(of: "```\n", options: .backwards)
        view.insertText("", replacementRange: closing)
        #expect(view.string == "```\na\nb\nc")
        #expect(view.plates.map(\.roundsTop) == [true, false, false, false])
        #expect(view.plates.map(\.roundsBottom) == [false, false, false, true])
        // A fence typed back after `a` closes the block there.
        view.insertText("```\n", replacementRange: NSRange(location: 6, length: 0))
        #expect(view.plates.map(\.roundsBottom) == [false, false, true])
        // Text appended after an unclosed block at the end joins it.
        view.string = "```\na"
        view.insertText("\nb", replacementRange: NSRange(location: 5, length: 0))
        #expect(view.plates.map(\.roundsBottom) == [false, false, true])
        _ = window
    }

    @Test func textOutsidePlatesGivesNoPlates() throws {
        let (view, window) = try makeLaidOutEditor("a **b** c\n- d\n> e [f](g.com)")
        #expect(view.plates.isEmpty)
        _ = window
    }

    @Test func platesFollowEdits() throws {
        let (view, window) = try makeLaidOutEditor("a ==b c")
        #expect(view.plates.isEmpty)
        view.setSelectedRange(NSRange(location: 7, length: 0))
        view.insertText("==", replacementRange: view.selectedRange())
        #expect(view.plates.map(\.kind) == [.highlight])
        view.insertText("\n```", replacementRange: view.selectedRange())
        #expect(view.plates.map(\.kind) == [.highlight, .codeBlock])
        _ = window
    }
}
