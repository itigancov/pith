import AppKit
import PithEditor
import PithNotes

// Restyle timings of `Styler` over a plain `NSTextStorage` on the generated 5k-line Note (spec 09),
// and the storage timings of `NoteStore` on the same Note in a database file (spec 03).
// Run in release: `make bench`. Exits with 1 when a budget is missed.
// Budgets are checked on wall time; CPU time of the thread is printed beside it, since it barely moves
// when other processes load the machine.
// `PithBench profile typing|unclosed` repeats one case until killed, for a sampling profiler.

let lines = 5000
let seed: UInt64 = 1
let note = NoteGenerator.note(lines: lines, seed: seed)

let storage = NSTextStorage()
let styler = Styler()

struct Sample {
    var wall: Double
    var cpu: Double
}

/// The time of `work`, in milliseconds.
@MainActor func timed(_ work: () -> Void) -> Sample {
    func cpuNow() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return Double(time.tv_sec) * 1000 + Double(time.tv_nsec) / 1e6
    }
    let cpu = cpuNow()
    let wall = ContinuousClock().measure(work)
    return Sample(
        wall: Double(wall.components.seconds) * 1000 + Double(wall.components.attoseconds) / 1e15,
        cpu: cpuNow() - cpu
    )
}

/// An edit of the storage, which the Styler restyles within it.
@MainActor func replace(_ range: NSRange, with string: String) {
    storage.replaceCharacters(in: range, with: string)
}

/// Puts the storage back to `text` by replacing only the part that differs.
@MainActor func restore(_ text: String) {
    let old = storage.string as NSString
    let new = text as NSString
    var prefix = 0
    while prefix < old.length, prefix < new.length, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
    var suffix = 0
    while suffix < old.length - prefix, suffix < new.length - prefix,
          old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
    replace(
        NSRange(location: prefix, length: old.length - prefix - suffix),
        with: new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
    )
}

var missed = false

@MainActor func report(_ name: String, _ samples: [Sample], median budget: Double? = nil, max maxBudget: Double? = nil) {
    func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    let wall = samples.map(\.wall)
    let cpu = samples.map(\.cpu)
    let wallMedian = median(wall)
    let wallMax = wall.max() ?? 0
    var verdict = ""
    if let budget { verdict = wallMedian <= budget ? "  ok, median ≤ \(budget)" : "  MISSED median ≤ \(budget)" }
    if let maxBudget { verdict = wallMax <= maxBudget ? "  ok, max ≤ \(maxBudget)" : "  MISSED max ≤ \(maxBudget)" }
    if verdict.contains("MISSED") { missed = true }
    func ms(_ value: Double) -> String { String(format: "%7.2f", value) }
    let columns = "wall median \(ms(wallMedian)) max \(ms(wallMax)) · cpu median \(ms(median(cpu))) max \(ms(cpu.max() ?? 0)) · n=\(samples.count)"
    print(name.padding(toLength: 34, withPad: " ", startingAt: 0) + columns + verdict)
}

/// The middle of the text of the first paragraph past the middle of the Note.
@MainActor func middleOfAParagraph(_ text: String) -> Int {
    let blocks = BlockScanner.scan(text)
    let middle = (text as NSString).length / 2
    let paragraph = blocks.first { $0.kind == .paragraph && $0.content.location >= middle } ?? blocks[blocks.count / 2]
    return paragraph.content.location + paragraph.content.length / 2
}

/// The end of the first bullet item past the middle of the Note.
@MainActor func endOfAListItem(_ text: String) -> Int {
    let middle = (text as NSString).length / 2
    let item = BlockScanner.scan(text).first {
        guard $0.range.location >= middle, case .bullet = $0.kind else { return false }
        return true
    }
    return item?.range.upperBound ?? middle
}

/// Applies a Command's replacements to the storage from the last, as `EditorTextView` does.
@MainActor func apply(_ command: (String, NSRange) -> TextEdit?, selection: NSRange) {
    guard let edit = command(storage.string, selection) else { fatalError("the Command declined") }
    for replacement in edit.replacements.reversed() {
        replace(replacement.range, with: replacement.string)
    }
}

print("Generated Note: \(lines) lines, seed \(seed), \((note as NSString).length) UTF-16 units, \(BlockScanner.scan(note).count) Blocks")
print("All times in ms.\n")

// As the demo does: an empty editor, then the whole Note at once.
styler.attach(to: storage)
report("set the whole Note", [timed { replace(NSRange(location: 0, length: 0), with: note) }])

let paragraphMiddle = middleOfAParagraph(note)

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "profile" {
    let unclosed = CommandLine.arguments[2] == "unclosed"
    print("Profiling, pid \(ProcessInfo.processInfo.processIdentifier)")
    while true {
        if unclosed {
            replace(NSRange(location: 0, length: 0), with: "````\n")
            replace(NSRange(location: 0, length: 5), with: "")
        } else {
            replace(NSRange(location: paragraphMiddle, length: 0), with: "a")
            replace(NSRange(location: paragraphMiddle, length: 1), with: "")
        }
    }
}

let warmup = 5

var inserts: [Sample] = []
var deletes: [Sample] = []
for round in 0..<(warmup + 101) {
    let insert = timed { replace(NSRange(location: paragraphMiddle, length: 0), with: "a") }
    let delete = timed { replace(NSRange(location: paragraphMiddle, length: 1), with: "") }
    if round >= warmup {
        inserts.append(insert)
        deletes.append(delete)
    }
}
report("insert a character mid-Note", inserts, median: 4)
report("delete a character mid-Note", deletes, median: 4)

/// Opens a fence on a new first line, then deletes it: each restyles every Block up to where the fence closes.
@MainActor func measureFence(_ fence: String, _ name: String) {
    var opens: [Sample] = []
    var closes: [Sample] = []
    let line = fence + "\n"
    for round in 0..<(1 + 9) {
        let open = timed { replace(NSRange(location: 0, length: 0), with: line) }
        let close = timed { replace(NSRange(location: 0, length: (line as NSString).length), with: "") }
        if round >= 1 {
            opens.append(open)
            closes.append(close)
        }
    }
    report("insert \(name)", opens, max: 100)
    report("delete \(name)", closes, max: 100)
}
// Closes at the first bare closing fence of the Note.
measureFence("```", "``` at the start")
// The Note has no closing fence of four backticks: the code block runs to its end and every Block changes.
measureFence("````", "unclosed ```` at the start")
print()

// Commands: the pure function and the restyle of its result. No budget of their own; they should stay near typing.
let listItemEnd = endOfAListItem(note)
let commands: [(String, (String, NSRange) -> TextEdit?, NSRange)] = [
    ("Enter continues a list item", BlockCommands.newline, NSRange(location: listItemEnd, length: 0)),
    ("Tab nests a list item", BlockCommands.indent, NSRange(location: listItemEnd, length: 0)),
    ("⌘B wraps a word", InlineCommands.toggle(.strong), NSRange(location: paragraphMiddle, length: 0)),
    ("⌃⌘1 makes a heading", BlockCommands.toggle(.heading(level: 1)), NSRange(location: paragraphMiddle, length: 0)),
]
for (name, command, selection) in commands {
    var samples: [Sample] = []
    for round in 0..<(warmup + 31) {
        let time = timed { apply(command, selection: selection) }
        restore(note)
        if round >= warmup { samples.append(time) }
    }
    report(name, samples)
}

report("BlockScanner.scan of the Note", (0..<31).map { _ in timed { _ = BlockScanner.scan(storage.string) } })

// Storage: a database file in a temporary directory (WAL), the same Note.
do {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pith-bench-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (store, _) = try NoteStore.open(at: .file(directory.appendingPathComponent("notes.sqlite")))
    let stored = try store.insert(text: note, selection: NoteSelection(location: 0, length: 0), scrollOffset: 0)

    var saves: [Sample] = []
    var opens: [Sample] = []
    for round in 0..<(warmup + 31) {
        // A different text each time, as typing makes it.
        let edited = note + String(repeating: "a", count: round % 7)
        var failure: Error?
        let save = timed { do { try store.updateText(id: stored.id, text: edited) } catch { failure = error } }
        var read: Note?
        let open = timed { do { read = try store.note(id: stored.id) } catch { failure = error } }
        if let failure { fatalError("storage failed: \(failure)") }
        precondition(read?.text == edited)
        if round >= warmup {
            saves.append(save)
            opens.append(open)
        }
    }
    report("autosave of the Note (updateText)", saves, median: 5)
    report("open the Note (note(id:))", opens, median: 16)
}
print()

if missed {
    print("\nA budget is missed.")
    exit(1)
}
