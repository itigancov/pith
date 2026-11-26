import Foundation
import Observation
import PithNotes

/// What "Go to latest note" means, the newest Note or the last edited one: stored in `UserDefaults`, read by the Note screen
/// at every jump, set in Settings.
@Observable
final class LatestMeansModel {
    var mode: Latest {
        didSet {
            if !isTemporary, mode != oldValue { defaults.set(mode.rawValue, forKey: NoteScreen.latestMeansKey) }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// A value from the launch arguments (`-PithLatest`) replaces the stored one and is never saved.
    @ObservationIgnored private let isTemporary: Bool

    init(defaults: UserDefaults = .standard, initial: Latest? = nil) {
        self.defaults = defaults
        isTemporary = initial != nil
        mode = initial ?? defaults.string(forKey: NoteScreen.latestMeansKey).flatMap(Latest.init(rawValue:)) ?? .newest
    }
}
