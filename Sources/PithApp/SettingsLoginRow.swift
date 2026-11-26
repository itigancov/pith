import SwiftUI

/// The Open at login row: a switch that shows the system's real status, its caption, and in the state that needs it a button
/// to System Settings.
struct OpenAtLoginRow: View {
    let item: LoginItem

    var body: some View {
        let row = item.row
        LabeledContent {
            Toggle("Open at login", isOn: Binding(get: { row.isOn }, set: { item.setEnabled($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!row.isEnabled)
                .accessibilityLabel("Open at login")
                .accessibilityHint(row.caption())
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                RowLabel(title: "Open at login", caption: row.caption())
                if row.showsApprovalButton {
                    Button("Open Login Items…") { item.openSystemSettings() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .padding(.top, 2)
                }
            }
        }
    }
}
