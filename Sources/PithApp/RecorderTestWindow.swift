import AppKit

/// An ordinary window with the seven Shortcut rows and the large recorder of the Hotkey, to try the recorder and to
/// photograph it (`-PithShow recorder`). The Settings (12) and onboarding (14) screens replace it.
final class RecorderTestWindow {
    let window: NSWindow
    private let store: ShortcutStore
    private var recorders: [(action: ShortcutAction, view: ShortcutRecorderView)] = []
    private var observer: NSObjectProtocol?

    /// `state` puts the Hotkey's two recorders in that state without any key pressed.
    init(store: ShortcutStore, size: CGSize?, state: ShortcutRecorderModel.State?) {
        self.store = store
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size ?? CGSize(width: 480, height: 400)),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Shortcut Recorder"
        window.isReleasedWhenClosed = false

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10
        rows.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        for action in ShortcutAction.allCases {
            let recorder = ShortcutRecorderView(variant: .compact, shortcut: store.shortcut(for: action))
            rows.addArrangedSubview(row(label: action.title, recorder: recorder, action: action))
        }
        let large = ShortcutRecorderView(variant: .large, shortcut: store.shortcut(for: .hotkey))
        let largeBlock = block(recorder: large, action: .hotkey)
        rows.addArrangedSubview(largeBlock)
        rows.setCustomSpacing(24, after: rows.arrangedSubviews[rows.arrangedSubviews.count - 2])

        let restore = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        rows.addArrangedSubview(restore)

        window.contentView = rows
        if size == nil { window.setContentSize(rows.fittingSize) }
        window.center()

        observer = NotificationCenter.default.addObserver(forName: .shortcutsDidChange, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }

        if let state {
            for entry in recorders where entry.action == .hotkey { entry.view.showState(state) }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reload() {
        for entry in recorders { entry.view.shortcut = store.shortcut(for: entry.action) }
    }

    @objc private func restoreDefaults() { store.restoreDefaults() }

    /// A label on the left, the recorder on the right, the rejection under the row.
    private func row(label: String, recorder: ShortcutRecorderView, action: ShortcutAction) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let line = NSStackView(views: [title, spacer, recorder])
        line.orientation = .horizontal
        line.alignment = .centerY
        return captioned(line, width: 440, recorder: recorder, action: action)
    }

    private func block(recorder: ShortcutRecorderView, action: ShortcutAction) -> NSView {
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return captioned(recorder, width: 360, recorder: recorder, action: action)
    }

    /// The caption under `content`: 12 pt, red for a rejection, hidden when empty.
    private func captioned(_ content: NSView, width: CGFloat, recorder: ShortcutRecorderView, action: ShortcutAction) -> NSView {
        let caption = NSTextField(labelWithString: "")
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = NSColor(name: "caption.error") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
                : NSColor(srgbRed: 0xD7 / 255, green: 0, blue: 0x15 / 255, alpha: 1)
        }
        caption.isHidden = true
        recorder.onCommit = { [store] in store.assign($0, to: action) }
        recorder.onRecordingChange = { [store] in store.setRecording($0) }
        recorder.onRejection = { text in
            caption.stringValue = text ?? ""
            caption.isHidden = text == nil
        }
        recorders.append((action, recorder))
        let stack = NSStackView(views: [content, caption])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }
}
