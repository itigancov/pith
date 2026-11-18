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
}
