import Foundation

/// The tabs of Settings.
enum SettingsTab: String, CaseIterable {
    case general, shortcuts

    static let defaultsKey = "SettingsTab"

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        }
    }

    /// The tab stored by the last session; a missing or broken value is General.
    static func stored(in defaults: UserDefaults) -> SettingsTab {
        defaults.string(forKey: defaultsKey).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }
}

/// What the controls of Settings work on: the same objects as the Panel, the menus and the Hotkey use.
final class SettingsContext {
    let shortcuts: ShortcutStore
    let textSize: TextSizeModel
    let appearance: AppearanceModel
    let latestMeans: LatestMeansModel
    let trash: SettingsTrash
    /// Empty Trash… was pressed: asks and empties.
    var emptyTrash: () -> Void = {}

    init(shortcuts: ShortcutStore, textSize: TextSizeModel, appearance: AppearanceModel, latestMeans: LatestMeansModel, trash: SettingsTrash) {
        self.shortcuts = shortcuts
        self.textSize = textSize
        self.appearance = appearance
        self.latestMeans = latestMeans
        self.trash = trash
    }
}
