import Foundation
import Observation
import PithEditor

/// The text size, one for all Notes: 10–48 pt, stored in `UserDefaults`. Settings uses the same object.
@Observable
final class TextSizeModel {
    static let key = "TextSize"
    static let defaultSize = Int(Theme.defaultTextSize)
    static let range = Int(Theme.sizeRange.lowerBound)...Int(Theme.sizeRange.upperBound)

    private(set) var size: Int

    @ObservationIgnored private let defaults: UserDefaults
    /// A size from the launch arguments replaces the stored one and is never saved.
    @ObservationIgnored private let isTemporary: Bool

    init(defaults: UserDefaults = .standard, initial: Int? = nil) {
        self.defaults = defaults
        isTemporary = initial != nil
        let stored = defaults.object(forKey: Self.key) as? Int
        size = Self.clamped(initial ?? stored ?? Self.defaultSize)
    }

    func bigger() { set(size + 1) }
    func smaller() { set(size - 1) }
    func reset() { set(Self.defaultSize) }

    private func set(_ value: Int) {
        size = Self.clamped(value)
        if !isTemporary { defaults.set(size, forKey: Self.key) }
    }

    private static func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Calls `change` with the value `read` returns after every change of what it reads.
/// The call comes on the next turn of the main actor, once the new value is in place.
func observeChanges<Value>(_ read: @escaping @MainActor () -> Value, _ change: @escaping @MainActor (Value) -> Void) {
    withObservationTracking {
        _ = read()
    } onChange: {
        Task { @MainActor in
            change(read())
            observeChanges(read, change)
        }
    }
}
