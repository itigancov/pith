import PithNotes
import SwiftUI

/// Both tabs are as wide as the window and as high as their content.
enum SettingsLayout {
    static let width: CGFloat = 520
}

struct GeneralSettingsView: View {
    let context: SettingsContext
    @Bindable private var appearance: AppearanceModel
    private let trash: SettingsTrash

    init(context: SettingsContext) {
        self.context = context
        appearance = context.appearance
        trash = context.trash
    }

    var body: some View {
        Form {
            Section {
                ShortcutRow(store: context.shortcuts, action: .hotkey, title: "Open Pith")
                LabeledContent {
                    // Until the login item exists (13) the switch is off and cannot be turned on.
                    Toggle("Open at login", isOn: .constant(false))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(true)
                } label: {
                    RowLabel(title: "Open at login", caption: "Keeps the shortcut working after a restart")
                }
            }
            Section {
                LabeledContent {
                    Picker("Appearance", selection: $appearance.appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    RowLabel(title: "Appearance")
                }
                LabeledContent {
                    TextSizeCapsule(model: context.textSize)
                } label: {
                    RowLabel(title: "Text size", caption: "⌘+ and ⌘− in the panel change it too, ⌘0 resets")
                }
            }
            Section {
                LabeledContent {
                    Button("Empty Trash…") { context.emptyTrash() }
                        .disabled(!trash.canEmpty)
                } label: {
                    RowLabel(title: "Trash", caption: trash.label)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: SettingsLayout.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ShortcutsSettingsView: View {
    let context: SettingsContext
    @Bindable private var latestMeans: LatestMeansModel

    init(context: SettingsContext) {
        self.context = context
        latestMeans = context.latestMeans
    }

    var body: some View {
        VStack(spacing: 14) {
            Form {
                Section("Anywhere") {
                    ShortcutRow(store: context.shortcuts, action: .hotkey)
                }
                Section("In the panel") {
                    ShortcutRow(store: context.shortcuts, action: .newNote)
                    ShortcutRow(store: context.shortcuts, action: .goToLatest, caption: "From anywhere in the stack, back to where you left off")
                    LabeledContent {
                        Picker("Latest means", selection: $latestMeans.mode) {
                            Text("Newest note").tag(Latest.newest)
                            Text("Last edited note").tag(Latest.lastEdited)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    } label: {
                        Text("Latest means")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                    }
                    ShortcutRow(store: context.shortcuts, action: .searchNotes)
                    ShortcutRow(store: context.shortcuts, action: .previousNote)
                    ShortcutRow(store: context.shortcuts, action: .nextNote)
                    ShortcutRow(store: context.shortcuts, action: .moveToTrash)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Restore Defaults") { context.shortcuts.restoreDefaults() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: SettingsLayout.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}
