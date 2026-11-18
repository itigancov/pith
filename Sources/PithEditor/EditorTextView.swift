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
