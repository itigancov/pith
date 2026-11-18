import AppKit

/// Plain-text Markdown editor view. Always runs on TextKit 2.
public final class EditorTextView: NSTextView {
    public convenience init() {
        self.init(usingTextLayoutManager: true)
        configure()
    }

    private func configure() {
        isRichText = false
        importsGraphics = false

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
