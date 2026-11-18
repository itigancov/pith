import Foundation
import Testing
@testable import PithEditor

struct NoteGeneratorTests {
    @Test func theSameSeedGivesTheSameNote() {
        #expect(NoteGenerator.note(lines: 300, seed: 7) == NoteGenerator.note(lines: 300, seed: 7))
        #expect(NoteGenerator.note(lines: 300, seed: 7) != NoteGenerator.note(lines: 300, seed: 8))
    }

    @Test(arguments: [1, 2, 11, 300, 5000])
    func theNoteHasTheRequestedLineCount(_ lines: Int) {
        let note = NoteGenerator.note(lines: lines, seed: 1)
        #expect(note.split(separator: "\n", omittingEmptySubsequences: false).count == lines)
    }

    @Test func theNoteHasEveryBlockKind() {
        let blocks = BlockScanner.scan(NoteGenerator.note(lines: 300, seed: 1))
        var kinds: Set<String> = []
        for block in blocks {
            switch block.kind {
            case .paragraph: kinds.insert("paragraph")
            case .blank: kinds.insert("blank")
            case .heading(let level): kinds.insert("heading \(level)")
            case .bullet(let level): kinds.insert(level == 0 ? "bullet" : "nested bullet")
            case .ordered(let level, _): kinds.insert(level == 0 ? "ordered" : "nested ordered")
            case .task(_, let checked): kinds.insert(checked ? "done task" : "open task")
            case .quote: kinds.insert("quote")
            case .codeBlock: kinds.insert("code block")
            }
        }
        #expect(kinds == [
            "paragraph", "blank", "heading 1", "heading 2", "heading 3", "bullet", "nested bullet",
            "ordered", "nested ordered", "done task", "open task", "quote", "code block",
        ])
    }

    @Test func theNoteHasEveryInlineKind() {
        let text = NoteGenerator.note(lines: 300, seed: 1)
        let kinds = Set(BlockScanner.scan(text).filter { !$0.isCodeBlock }.flatMap { InlineParser.parse(text, in: $0.content) }.map(\.kind))
        #expect(kinds.isSuperset(of: [.strong, .emphasis, .strikethrough, .highlight, .code, .link, .linkText, .url]))
    }

    @Test(arguments: [1, 2, 3, 4, 5] as [UInt64])
    func everyCodeBlockIsClosed(_ seed: UInt64) {
        let codeBlocks = BlockScanner.scan(NoteGenerator.note(lines: 5000, seed: seed)).filter(\.isCodeBlock)
        #expect(!codeBlocks.isEmpty)
        #expect(codeBlocks.allSatisfy { $0.markers.filter { $0.kind == .fence }.count == 2 })
    }
}
