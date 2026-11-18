import Foundation

/// Commands on tasks: `-`, `*` or `+` list items with a `[ ]`, `[x]` or `[X]` checkbox.
public enum TaskCommands {
    /// Complete Task (⌘K, a click on the checkbox): toggles the tasks whose lines the selection touches.
    /// If any of them is open, the open ones are checked and the done ones stay; otherwise all are opened.
    /// Rewrites only the character between the brackets, so the selection stays. `nil` when no task is touched.
    public static func toggle(text: String, selection: NSRange) -> TextEdit? {
        let note = ScannedNote(text)
        let tasks = note.blockIndices(touchedBy: selection).compactMap { index -> (mark: NSRange, checked: Bool)? in
            let block = note.blocks[index]
            guard case .task(_, let checked) = block.kind, let box = block.taskCheckbox else { return nil }
            // The character between the brackets.
            return (NSRange(location: box.location + 1, length: 1), checked)
        }
        guard !tasks.isEmpty else { return nil }
        let checks = tasks.contains { !$0.checked }
        let replacements = tasks
            .filter { $0.checked != checks }
            .map { TextEdit.Replacement(range: $0.mark, string: checks ? "x" : " ") }
        return TextEdit(replacements: replacements, selection: selection)
    }
}
