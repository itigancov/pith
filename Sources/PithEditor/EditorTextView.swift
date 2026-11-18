import AppKit

/// Plain-text Markdown editor view. Always runs on TextKit 2.
public final class EditorTextView: NSTextView {
    /// Restyles the text after every edit of the storage, however it is made.
    public let styler = Styler()

    public convenience init() {
        self.init(usingTextLayoutManager: true)
        configure()
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        if let textStorage {
            assert(textStorage.delegate == nil, "the text storage already has a delegate")
            styler.attach(to: textStorage)
        }
        typingAttributes = styler.theme.baseAttributes

        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        smartInsertDeleteEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isGrammarCheckingEnabled = false
        isContinuousSpellCheckingEnabled = true

        #if DEBUG
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(layoutManagerWillSwitch),
            name: NSTextView.willSwitchToNSLayoutManagerNotification,
            object: self
        )
        #endif
    }

    #if DEBUG
    @objc private func layoutManagerWillSwitch(_ notification: Notification) {
        assertionFailure("EditorTextView fell back to TextKit 1: something touched layoutManager")
    }
    #endif

    /// Typed text always starts from the base style; the Styler restyles it within the same edit.
    public override var typingAttributes: [NSAttributedString.Key: Any] {
        get { super.typingAttributes }
        set { super.typingAttributes = styler.theme.baseAttributes }
    }

    // AppKit announces plain text under the legacy name, not the `.string` UTI.
    private static let stringTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("NSStringPboardType"),
        .string,
    ]

    // Plain text only: also narrows drag-and-drop.
    public override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { Self.stringTypes }

    public override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { Self.stringTypes }

    public override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        super.writeSelection(to: pboard, types: types.filter(Self.stringTypes.contains))
    }

    // MARK: Input methods

    // While input method text is composed, the Styler holds off; once the composition is committed or cancelled,
    // it restyles everything the composition changed at once.

    public override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        styler.beginComposition()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        // Empty marked text cancels the composition.
        endCompositionIfDone()
    }

    public override func unmarkText() {
        super.unmarkText()
        endCompositionIfDone()
    }

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        endCompositionIfDone()
    }

    private func endCompositionIfDone() {
        guard !hasMarkedText(), let textStorage else { return }
        styler.endComposition(in: textStorage)
    }

    // MARK: Block behavior

    /// Enter continues a list item or quote; ⇧Enter and Enter elsewhere insert a plain line break.
    public override func insertNewline(_ sender: Any?) {
        let isShifted = NSApp?.currentEvent.map { $0.type == .keyDown && $0.modifierFlags.contains(.shift) } ?? false
        if isShifted || !run(BlockCommands.newline) { super.insertNewline(sender) }
    }

    /// Tab nests a list item; outside list items it inserts a tab.
    public override func insertTab(_ sender: Any?) {
        if !run(BlockCommands.indent) { super.insertTab(sender) }
    }

    /// ⇧Tab unnests a list item.
    public override func insertBacktab(_ sender: Any?) {
        if !run(BlockCommands.outdent) { super.insertBacktab(sender) }
    }

    /// ⌘] nests the selected list items; does nothing outside them.
    public override func indent(_ sender: Any?) {
        _ = run(BlockCommands.indent)
    }

    /// ⌘[ unnests the selected list items; does nothing outside them.
    @objc public func outdent(_ sender: Any?) {
        _ = run(BlockCommands.outdent)
    }

    // MARK: Formatting

    // Inline Toggles; each does nothing in code. The names stay clear of NSTextView's own actions, such as `underline:`.

    @objc public func toggleBold(_ sender: Any?) { _ = run(InlineCommands.toggle(.strong)) }
    @objc public func toggleItalic(_ sender: Any?) { _ = run(InlineCommands.toggle(.emphasis)) }
    @objc public func toggleHighlight(_ sender: Any?) { _ = run(InlineCommands.toggle(.highlight)) }
    @objc public func toggleStrikethrough(_ sender: Any?) { _ = run(InlineCommands.toggle(.strikethrough)) }
    @objc public func toggleCode(_ sender: Any?) { _ = run(InlineCommands.toggle(.code)) }
    @objc public func toggleLink(_ sender: Any?) { _ = run(InlineCommands.toggleLink) }

    // Block Toggles; each but the code block one does nothing in a code block.

    @objc public func toggleHeading1(_ sender: Any?) { _ = run(BlockCommands.toggle(.heading(level: 1))) }
    @objc public func toggleHeading2(_ sender: Any?) { _ = run(BlockCommands.toggle(.heading(level: 2))) }
    @objc public func toggleHeading3(_ sender: Any?) { _ = run(BlockCommands.toggle(.heading(level: 3))) }
    @objc public func toggleBulletList(_ sender: Any?) { _ = run(BlockCommands.toggle(.bullet)) }
    @objc public func toggleOrderedList(_ sender: Any?) { _ = run(BlockCommands.toggle(.ordered)) }
    @objc public func toggleTaskList(_ sender: Any?) { _ = run(BlockCommands.toggle(.task)) }
    @objc public func toggleQuote(_ sender: Any?) { _ = run(BlockCommands.toggle(.quote)) }
    @objc public func toggleCodeBlock(_ sender: Any?) { _ = run(BlockCommands.toggle(.codeBlock)) }

    // MARK: Tasks

    /// ⌘K toggles the tasks the selection touches; does nothing outside them.
    @objc public func toggleTask(_ sender: Any?) {
        _ = run(TaskCommands.toggle)
    }

    /// A single plain click on a task's checkbox toggles the task and leaves the selection.
    /// A single plain press on a url opens it, or selects it if long; one that moves is a standard drag.
    /// Any other click is standard.
    public override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if event.clickCount == 1, modifiers.isEmpty, !hasMarkedText() {
            let point = convert(event.locationInWindow, from: nil)
            if let index = checkboxCharacter(at: point), toggleTask(atCharacter: index) {
                // The standard click would have focused the editor.
                window?.makeFirstResponder(self)
                return
            }
            if let index = urlCharacter(at: point) {
                trackURLPress(event, atCharacter: index)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Follows the press that `down` starts on a url until the button goes up, or hands it to the standard drag once it moves.
    private func trackURLPress(_ down: NSEvent, atCharacter index: Int) {
        guard let window else { return super.mouseDown(with: down) }
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let distance = hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y)
            let gesture = Links.gesture(duration: event.timestamp - down.timestamp, distance: distance)
            if gesture == .drag {
                // The standard tracking starts from the press and sees this event too.
                window.postEvent(event, atStart: true)
                super.mouseDown(with: down)
                return
            }
            if event.type == .leftMouseUp {
                window.makeFirstResponder(self)
                _ = follow(gesture, atCharacter: index)
                return
            }
        }
    }

    /// The first character of the task checkbox whose glyphs are under `point` (view coordinates), if any.
    /// `nil` while input method text is being composed.
    func checkboxCharacter(at point: NSPoint) -> Int? {
        guard !hasMarkedText(), let layout = textLayoutManager else { return nil }
        let location = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard let paragraph = layout.paragraphRange(at: location) else { return nil }
        return styler.blocks
            .filter { NSIntersectionRange($0.range, paragraph).length > 0 }
            .compactMap(\.taskCheckbox)
            .first { layout.glyphs(of: $0, contain: location) }?
            .location
    }

    /// Toggles the task whose checkbox holds the character at `index`, leaving the selection where it is.
    /// `false` when the character is not in a task's checkbox or input method text is being composed.
    func toggleTask(atCharacter index: Int) -> Bool {
        guard !hasMarkedText(),
              let box = styler.blocks.lazy.compactMap(\.taskCheckbox).first(where: { NSLocationInRange(index, $0) }),
              var edit = TaskCommands.toggle(text: string, selection: NSRange(location: box.location, length: 0))
        else { return false }
        // The text keeps its length, so the selection before the click is still valid.
        edit.selection = selectedRange()
        apply(edit)
        return true
    }

    // MARK: Links

    /// Opens a url's address; the default hands it to the system.
    public var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    // A pointing hand over every clickable url, with or without modifiers; the standard cursor elsewhere.

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if isOverURL(event) {
            NSCursor.pointingHand.set()
        } else if NSCursor.current == NSCursor.pointingHand {
            // Leaving a url: the hand is ours to take back.
            NSCursor.iBeam.set()
        }
    }

    public override func cursorUpdate(with event: NSEvent) {
        if isOverURL(event) { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }

    private func isOverURL(_ event: NSEvent) -> Bool {
        urlCharacter(at: convert(event.locationInWindow, from: nil)) != nil
    }

    /// The first character of the clickable url whose glyphs are under `point` (view coordinates), if any.
    /// `nil` while input method text is being composed: the pointer stays standard.
    func urlCharacter(at point: NSPoint) -> Int? {
        guard !hasMarkedText(), let layout = textLayoutManager else { return nil }
        let location = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard let paragraph = layout.paragraphRange(at: location) else { return nil }
        let text = string
        let blocks = styler.blocks
        return blocks
            .filter { !$0.isCodeBlock && NSIntersectionRange($0.range, paragraph).length > 0 }
            .flatMap { InlineParser.parse(text, in: $0.content) }
            .filter { $0.kind == .url }
            .first { layout.glyphs(of: $0.range, contain: location) && Links.url(in: text, at: $0.range.location, blocks: blocks) != nil }?
            .range.location
    }

    /// Follows a press on the url that holds the character at `index`: `.open` opens it and leaves the selection,
    /// `.select` selects the whole url. `false` when there is no clickable url there, input method text is being composed,
    /// or the gesture is a drag.
    func follow(_ gesture: Links.Gesture, atCharacter index: Int) -> Bool {
        guard !hasMarkedText(), let (range, url) = Links.url(in: string, at: index, blocks: styler.blocks) else { return false }
        switch gesture {
        case .open:
            openURL(url)
        case .select:
            setSelectedRange(range)
        case .drag:
            return false
        }
        return true
    }

    /// Runs a Command on the text and applies its result; `false` when it declines or input method text is being composed.
    private func run(_ command: (String, NSRange) -> TextEdit?) -> Bool {
        guard !hasMarkedText(), let edit = command(string, selectedRange()) else { return false }
        apply(edit)
        return true
    }

    /// Applies a Command's result as one undo step of its own; the Styler restyles through the storage delegate.
    private func apply(_ edit: TextEdit) {
        guard let textStorage, !edit.replacements.isEmpty else { return }
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        // From the last, so the ranges of the others stay valid.
        for replacement in edit.replacements.reversed()
        where shouldChangeText(in: replacement.range, replacementString: replacement.string) {
            textStorage.replaceCharacters(in: replacement.range, with: replacement.string)
            didChangeText()
        }
        setSelectedRange(edit.selection)
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
    }
}

private extension NSTextLayoutManager {
    /// The text range (UTF-16) of the laid-out paragraph under `point`, in text container coordinates.
    func paragraphRange(at point: CGPoint) -> NSRange? {
        guard let fragment = textLayoutFragment(for: point) else { return nil }
        let range = fragment.rangeInElement
        return NSRange(
            location: offset(from: documentRange.location, to: range.location),
            length: offset(from: range.location, to: range.endLocation)
        )
    }

    /// Whether the glyphs of the characters in `range` (UTF-16) cover `point`, in text container coordinates.
    func glyphs(of range: NSRange, contain point: CGPoint) -> Bool {
        guard let start = location(documentRange.location, offsetBy: range.location),
              let end = location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return false }
        var contains = false
        enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            contains = frame.contains(point)
            return !contains
        }
        return contains
    }
}
