import AppKit
import SwiftUI

/// The compact Shortcut recorder of the Panel's rows, in SwiftUI. The Shortcut is the store's: the recorder shows it and
/// follows `.shortcutsDidChange`, so two rows of one action stay equal.
struct ShortcutRecorder: NSViewRepresentable {
    let store: ShortcutStore
    let action: ShortcutAction
    /// The text of a rejection for the caption under the row, `nil` to clear it.
    let onRejection: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView(variant: .compact, shortcut: store.shortcut(for: action))
        view.onCommit = { [store, action] in store.assign($0, to: action) }
        view.onRecordingChange = { [store] in store.setRecording($0) }
        view.onRejection = { [weak coordinator = context.coordinator] text in coordinator?.onRejection(text) }
        context.coordinator.onRejection = onRejection
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .shortcutsDidChange, object: store, queue: .main
        ) { [weak view, store, action] _ in
            MainActor.assumeIsolated { view?.shortcut = store.shortcut(for: action) }
        }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        context.coordinator.onRejection = onRejection
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShortcutRecorderView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class Coordinator {
        var onRejection: (String?) -> Void = { _ in }
        var observer: NSObjectProtocol?

        isolated deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

/// A row with the Shortcut recorder of one action: label (and caption) on the left, the recorder on the right, the text
/// of a rejection under the row.
struct ShortcutRow: View {
    let store: ShortcutStore
    let action: ShortcutAction
    var title: String?
    var caption: String?
    @State private var rejection: String?

    var body: some View {
        let label = title ?? action.title
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RowLabel(title: label, caption: caption)
                Spacer(minLength: 12)
                ShortcutRecorder(store: store, action: action) { rejection = $0 }
            }
            if let rejection {
                Text(rejection)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsColors.error)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The label of a row, 13 pt, with the caption of 12 pt under it.
struct RowLabel: View {
    let title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13))
            if let caption {
                Text(caption).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

enum SettingsColors {
    /// The red of a rejection's caption.
    static let error = Color(nsColor: NSColor(name: "caption.error") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
            : NSColor(srgbRed: 0xD7 / 255, green: 0, blue: 0x15 / 255, alpha: 1)
    })
}

/// "− 14 pt +": the Text size, the model's own.
struct TextSizeCapsule: View {
    let model: TextSizeModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 2) {
            stepButton(symbol: "minus", label: "Smaller text", isDisabled: model.size <= TextSizeModel.range.lowerBound) { model.smaller() }
            value
            stepButton(symbol: "plus", label: "Larger text", isDisabled: model.size >= TextSizeModel.range.upperBound) { model.bigger() }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Text size")
        .accessibilityValue("\(model.size) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.bigger()
            case .decrement: model.smaller()
            @unknown default: break
            }
        }
    }

    private var value: some View {
        Text("\(model.size) pt")
            .font(.system(size: 12).monospacedDigit())
            .frame(minWidth: 48, minHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color.white)
                    .shadow(color: .black.opacity(0.10), radius: 0, x: 0, y: 0.5)
                    .shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 1)
            )
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
    }

    private func stepButton(symbol: String, label: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}
