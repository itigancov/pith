import AppKit
import SwiftUI

/// Colors of the onboarding, from the artboards Onboarding-Hotkey and Onboarding-Ready. The dark values are proposed: where
/// there is one, a system color.
private enum OnboardingColors {
    private static func dynamic(name: String, light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: name) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static let ink = Color(nsColor: RecorderTheme.ink)
    static let background = dynamic(name: "onboarding.background", light: .white, dark: .windowBackgroundColor)
    static let title = dynamic(name: "onboarding.title", light: rgb(0x1D1D1F), dark: .labelColor)
    static let body = dynamic(name: "onboarding.body", light: rgb(0x55555A), dark: .secondaryLabelColor)
    static let caption = dynamic(name: "onboarding.caption", light: rgb(0x6A6A70), dark: .secondaryLabelColor)
    static let secondaryButton = dynamic(name: "onboarding.button.secondary", light: rgb(0xF0F0F1), dark: NSColor(white: 1, alpha: 0.10))
    static let pressedSecondary = dynamic(name: "onboarding.button.pressed", light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 0, alpha: 0.20))
    static let row = dynamic(name: "onboarding.row", light: rgb(0xF7F7F8), dark: NSColor(white: 1, alpha: 0.06))
    static let dot = dynamic(name: "onboarding.dot", light: NSColor(white: 0, alpha: 0.16), dark: NSColor(white: 1, alpha: 0.20))
    static let illustration = dynamic(name: "onboarding.illustration", light: rgb(0xF4F3F0), dark: NSColor(white: 1, alpha: 0.06))
    static let illustrationBar = dynamic(name: "onboarding.illustration.bar", light: NSColor(white: 1, alpha: 0.7), dark: NSColor(white: 1, alpha: 0.08))
    static let illustrationStub = dynamic(name: "onboarding.illustration.stub", light: NSColor(white: 0, alpha: 0.16), dark: NSColor(white: 1, alpha: 0.16))
    static let illustrationLine = dynamic(name: "onboarding.illustration.line", light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.08))
}

/// The window's content: the two steps, cross-fading. The window is 440 wide and as high as the step.
struct OnboardingView: View {
    let model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.step {
            case .hotkey: HotkeyStep(model: model).transition(.opacity)
            case .ready: ReadyStep(model: model).transition(.opacity)
            }
        }
        .frame(width: 440)
        .background(OnboardingColors.background.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.step)
    }
}

// MARK: Step 1

private struct HotkeyStep: View {
    let model: OnboardingModel
    @State private var rejection: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.16), radius: 0.25, x: 0, y: 0)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 6)
                .accessibilityHidden(true)
            OnboardingHeading(
                title: "Welcome to Pith", text: "A scratchpad that opens over any app. Paste, tidy up, copy, get back to work."
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("Shortcut to open Pith")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OnboardingColors.title)
                OnboardingRecorder(store: model.shortcuts, onRejection: { rejection = $0 }, onDefaultAction: { model.continue() })
                    .frame(height: 44)
                    .accessibilityLabel("Shortcut to open Pith")
                Text(rejection ?? "Press another combination to change it. You can do this later in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(rejection == nil ? OnboardingColors.caption : SettingsColors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            OnboardingFooter(step: 1) {
                Button("Continue") { model.continue() }
                    .buttonStyle(OnboardingButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(.top, 8)
        .padding(.horizontal, 40)
        .padding(.bottom, 32)
        .accessibilityElement(children: .contain)
    }
}

/// The large recorder of the Hotkey: listening as soon as it is on screen, assigning straight to the store.
private struct OnboardingRecorder: NSViewRepresentable {
    let store: ShortcutStore
    let onRejection: (String?) -> Void
    let onDefaultAction: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView(variant: .large, shortcut: store.shortcut(for: .hotkey))
        view.recordsWhenShown = true
        view.onCommit = { [store] in store.assign($0, to: .hotkey) }
        view.onRecordingChange = { [store] in store.setRecording($0) }
        let coordinator = context.coordinator
        view.onRejection = { [weak coordinator] in coordinator?.onRejection($0) }
        view.onDefaultAction = { [weak coordinator] in coordinator?.onDefaultAction() }
        coordinator.onRejection = onRejection
        coordinator.onDefaultAction = onDefaultAction
        coordinator.observer = NotificationCenter.default.addObserver(forName: .shortcutsDidChange, object: store, queue: .main) { [weak view, store] _ in
            MainActor.assumeIsolated { view?.shortcut = store.shortcut(for: .hotkey) }
        }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        context.coordinator.onRejection = onRejection
        context.coordinator.onDefaultAction = onDefaultAction
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShortcutRecorderView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 360, height: 44)
    }

    final class Coordinator {
        var onRejection: (String?) -> Void = { _ in }
        var onDefaultAction: () -> Void = {}
        var observer: NSObjectProtocol?

        isolated deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

// MARK: Step 2

private struct ReadyStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            MenuBarIllustration()
            VStack(spacing: 8) {
                OnboardingTitle(text: "Pith lives in the menu bar")
                hotkeyLine
            }
            LoginRow(model: model)
            OnboardingFooter(step: 2) {
                HStack(spacing: 8) {
                    Button("Back") { model.back() }
                        .buttonStyle(OnboardingButtonStyle(kind: .secondary))
                    Button("Open Pith") { model.openPith() }
                        .buttonStyle(OnboardingButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 2)
        }
        .padding(.top, 8)
        .padding(.horizontal, 40)
        .padding(.bottom, 32)
        .accessibilityElement(children: .contain)
    }

    /// "Press [chips] from any app. Press it again or Esc to hide." with the chips wrapping with the text; VoiceOver reads the words.
    private var hotkeyLine: some View {
        WrappingRow(spacing: 4) {
            Text("Press")
            ForEach(Array(model.hotkeyChips.enumerated()), id: \.offset) { _, chip in SmallKeycap(text: chip) }
            Text("from any app. Press it again or Esc to hide.")
        }
        .font(.system(size: 14))
        .foregroundStyle(OnboardingColors.body)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Press \(model.hotkeySpoken) from any app. Press it again or Esc to hide.")
    }
}

/// The Open at login row: the whole row is the switch's label. Its caption and the button to System Settings follow the
/// states of the row in Settings, with the onboarding's own plain caption.
private struct LoginRow: View {
    let model: OnboardingModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let row = model.loginItem.row
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open at login")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OnboardingColors.title)
                Text(row.caption(plain: "So the shortcut always works"))
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardingColors.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if row.showsApprovalButton {
                    Button("Open Login Items…") { model.loginItem.openSystemSettings() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .padding(.top, 2)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            Toggle("Open at login", isOn: Binding(get: { model.switchIsOn }, set: { model.openAtLogin = $0 }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(OnboardingColors.ink)
                .disabled(!model.switchIsAvailable)
                .accessibilityLabel("Open at login")
                .accessibilityHint(row.caption(plain: "So the shortcut always works"))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(OnboardingColors.row))
        .overlay {
            if contrast == .increased { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if model.switchIsAvailable { model.openAtLogin.toggle() }
        }
    }
}

/// The menu bar with Pith's icon and an arrow to it: a picture, nothing in it is read out.
private struct MenuBarIllustration: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).fill(OnboardingColors.illustration)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    stub(width: 16)
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(OnboardingColors.ink.opacity(0.14))
                        PithGlyph().stroke(OnboardingColors.ink, lineWidth: 1.6).frame(width: 15, height: 15)
                    }
                    .frame(width: 26, height: 20)
                    stub(width: 20)
                    stub(width: 54)
                }
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(OnboardingColors.illustrationBar)
                .overlay(alignment: .bottom) { Rectangle().fill(OnboardingColors.illustrationLine).frame(height: 1) }
                Spacer(minLength: 0)
            }
            Arrow()
                .stroke(OnboardingColors.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 20, height: 30)
                .offset(x: 360 - 111 - 20, y: 32)
        }
        .frame(width: 360, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(OnboardingColors.illustrationLine, lineWidth: 1) }
        .accessibilityHidden(true)
    }

    private func stub(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(OnboardingColors.illustrationStub).frame(width: width, height: 9)
    }

    /// The circle and the bar of the icon, as on the artboard.
    private nonisolated struct PithGlyph: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addEllipse(in: CGRect(x: rect.width * 0.25, y: rect.height * 0.25, width: rect.width * 0.5, height: rect.height * 0.5))
            path.addRoundedRect(
                in: CGRect(x: rect.width * 0.444, y: rect.height * 0.109, width: rect.width * 0.112, height: rect.height * 0.78),
                cornerSize: CGSize(width: 1, height: 1)
            )
            return path
        }
    }

    private nonisolated struct Arrow: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 10, y: 28))
            path.addLine(to: CGPoint(x: 10, y: 4))
            path.move(to: CGPoint(x: 4, y: 10))
            path.addLine(to: CGPoint(x: 10, y: 4))
            path.addLine(to: CGPoint(x: 16, y: 10))
            return path
        }
    }
}

// MARK: Parts

private struct OnboardingTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .bold))
            .tracking(-0.22)
            .lineSpacing(6)
            .foregroundStyle(OnboardingColors.title)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct OnboardingHeading: View {
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            OnboardingTitle(text: title)
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(OnboardingColors.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The dots of the steps on the left, the buttons on the right.
private struct OnboardingFooter<Buttons: View>: View {
    let step: Int
    @ViewBuilder let buttons: Buttons

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(1...2, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == step ? OnboardingColors.ink : OnboardingColors.dot)
                        .frame(width: index == step ? 14 : 5, height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step) of 2")
            Spacer()
            buttons
        }
    }
}

/// The two buttons of the onboarding: 32 high, 8 radius; the system's prominent one has other sizes.
private struct OnboardingButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        configuration.label
            .font(.system(size: 13, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(kind == .primary ? Color.white : OnboardingColors.title)
            .padding(.horizontal, kind == .primary ? 18 : 14)
            .frame(height: 32)
            .background(shape.fill(kind == .primary ? OnboardingColors.ink : OnboardingColors.secondaryButton))
            .overlay {
                if configuration.isPressed {
                    shape.fill(kind == .primary ? Color.black.opacity(0.08) : OnboardingColors.pressedSecondary)
                }
            }
            .overlay {
                if kind == .secondary, contrast == .increased { shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
            }
            .contentShape(shape)
    }
}

/// A small keycap for a key of the Hotkey in the text of step 2.
private struct SmallKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(nsColor: RecorderTheme.keycapText))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 24)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: RecorderTheme.keycapFill))
                    .shadow(color: .black.opacity(0.10), radius: 0, x: 0, y: 1)
            }
            .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color(nsColor: RecorderTheme.keycapBorder), lineWidth: 0.5) }
    }
}

/// Items in a centered row that wraps to the next line when the width runs out; `spacing` between items and lines.
private struct WrappingRow: Layout {
    var spacing: CGFloat

    private func lines(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var lines: [[(Int, CGSize)]] = [[]]
        var used: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            // An item wider than the row wraps inside itself.
            if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            let needed = (lines[lines.count - 1].isEmpty ? 0 : spacing) + size.width
            if used + needed > width, !lines[lines.count - 1].isEmpty {
                lines.append([])
                used = 0
            }
            used += (lines[lines.count - 1].isEmpty ? 0 : spacing) + size.width
            lines[lines.count - 1].append((index, size))
        }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let rows = lines(subviews, width: width)
        let height = rows.reduce(CGFloat(0)) { $0 + ($1.map(\.size.height).max() ?? 0) }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in lines(subviews, width: bounds.width) {
            let height = row.map(\.size.height).max() ?? 0
            let total = row.reduce(CGFloat(0)) { $0 + $1.size.width } + CGFloat(max(row.count - 1, 0)) * spacing
            var x = bounds.minX + (bounds.width - total) / 2
            for item in row {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (height - item.size.height) / 2), anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += height
        }
    }
}
