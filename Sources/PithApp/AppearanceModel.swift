import AppKit
import Observation

/// What the app's windows look like: the system's, or always light or dark.
nonisolated enum Appearance: String, CaseIterable, Sendable {
    case system, light, dark

    /// The value of `-PithAppearance light|dark`; anything else, including `system`, is no override.
    init?(argument: String?) {
        guard let argument, let value = Appearance(rawValue: argument), value != .system else { return nil }
        self = value
    }

    var title: String { rawValue.capitalized }
}

/// The Appearance choice, stored in `UserDefaults`; Settings and the launch use the same object.
@Observable
final class AppearanceModel {
    static let key = "Appearance"

    var appearance: Appearance {
        didSet {
            guard appearance != oldValue else { return }
            if !isTemporary { defaults.set(appearance.rawValue, forKey: Self.key) }
            apply(appearanceName)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// A value from the launch arguments replaces the stored one and is never saved.
    @ObservationIgnored private let isTemporary: Bool
    @ObservationIgnored private let apply: (NSAppearance.Name?) -> Void

    /// What `NSApp.appearance` gets; `nil` follows the system.
    var appearanceName: NSAppearance.Name? {
        switch appearance {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    /// `apply` is called with the name at start and after every change; the app sets `NSApp.appearance` with it.
    init(defaults: UserDefaults = .standard, initial: Appearance? = nil, apply: @escaping (NSAppearance.Name?) -> Void = { _ in }) {
        self.defaults = defaults
        self.apply = apply
        isTemporary = initial != nil
        appearance = initial ?? defaults.string(forKey: Self.key).flatMap(Appearance.init(rawValue:)) ?? .system
        apply(appearanceName)
    }

    /// Applies the appearance to the whole app.
    static func applyToApp(_ name: NSAppearance.Name?) {
        NSApp.appearance = name.flatMap(NSAppearance.init(named:))
    }
}
