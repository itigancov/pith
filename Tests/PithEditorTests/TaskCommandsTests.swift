import Foundation
import Testing
@testable import PithEditor

private func toggle(_ before: String) -> Marked? { run(TaskCommands.toggle, before) }

struct TaskCommandsTests {
    @Test func toggleChecksAnOpenTask() {
        #expect(toggle("- [ ] a|") == Marked("- [x] a|"))
    }

    @Test func toggleOpensADoneTask() {
        #expect(toggle("- [x] a|") == Marked("- [ ] a|"))
        #expect(toggle("- [X] a|") == Marked("- [ ] a|"))
    }

    @Test func toggleWorksWithTheCaretAnywhereOnTheLine() {
        #expect(toggle("|- [ ] a") == Marked("|- [x] a"))
        #expect(toggle("- [ ] a|b") == Marked("- [x] a|b"))
        #expect(toggle("- [|x] a") == Marked("- [| ] a"))
        #expect(toggle("- [ ]| a") == Marked("- [x]| a"))
        #expect(toggle("- [ ]|") == Marked("- [x]|"))
    }

    @Test func toggleWorksWithEveryBulletAndAnyIndent() {
        #expect(toggle("* [ ] a|") == Marked("* [x] a|"))
        #expect(toggle("+ [x] a|") == Marked("+ [ ] a|"))
        #expect(toggle("- a\n  - [ ] b|") == Marked("- a\n  - [x] b|"))
        #expect(toggle("\t- [x] b|") == Marked("\t- [ ] b|"))
    }

    @Test func toggleTouchesOnlyTheCaretsLine() {
        #expect(toggle("- [ ] a\n- [ ] b|\n- [ ] c") == Marked("- [ ] a\n- [x] b|\n- [ ] c"))
    }

    @Test func toggleDeclinesOutsideTasks() {
        #expect(toggle("text|") == nil)
        #expect(toggle("- item|") == nil)
        #expect(toggle("# [ ] heading|") == nil)
        #expect(toggle("|") == nil)
        #expect(toggle("- [ ] a\n|") == nil)
        #expect(toggle("```\n- [ ] code|\n```") == nil)
        #expect(toggle("> - [ ] quoted|") == nil)
        #expect(toggle("1. [ ] numbered|") == nil)
        #expect(toggle("- [y] a|") == nil)
    }

    @Test func toggleChecksEveryOpenTaskInTheSelection() {
        #expect(toggle("- [ ] «a\n- [ ] b»") == Marked("- [x] «a\n- [x] b»"))
    }

    @Test func toggleOpensEveryTaskWhenAllAreDone() {
        #expect(toggle("- [x] «a\n- [X] b»") == Marked("- [ ] «a\n- [ ] b»"))
    }

    @Test func toggleChecksAMixedSelectionAndLeavesDoneTasksAsTyped() {
        #expect(toggle("«- [x] a\n- [ ] b\n- [X] c»") == Marked("«- [x] a\n- [x] b\n- [X] c»"))
        #expect(toggle("«- [x] a\n- [x] b\n- [X] c»") == Marked("«- [ ] a\n- [ ] b\n- [ ] c»"))
    }

    @Test func toggleLeavesOtherBlocksInTheSelection() {
        #expect(
            toggle("«- [ ] a\ntext\n- item\n# h\n\n1. [ ] n\n- [ ] b»")
                == Marked("«- [x] a\ntext\n- item\n# h\n\n1. [ ] n\n- [x] b»")
        )
    }

    @Test func toggleTakesLinesThePartialSelectionTouches() {
        #expect(toggle("- [ ] a«b\n- [ ] c»d\n- [ ] e") == Marked("- [x] a«b\n- [x] c»d\n- [ ] e"))
        #expect(toggle("- [ ] «a\n»- [ ] b") == Marked("- [x] «a\n»- [ ] b"))
    }

    @Test func toggleDeclinesASelectionWithoutTasks() {
        #expect(toggle("«text\n- item»\n- [ ] a") == nil)
    }

    @Test func toggleHandlesCRLF() {
        #expect(toggle("- [ ] a\r\n- [x] «b\r\n- [ ] c»") == Marked("- [ ] a\r\n- [x] «b\r\n- [x] c»"))
    }

    @Test func toggleCountsUTF16WithCyrillicAndEmoji() {
        #expect(toggle("- [ ] задача 🎉\n- [ ] ещё 🚀|") == Marked("- [ ] задача 🎉\n- [x] ещё 🚀|"))
        #expect(toggle("«- [x] 🎉🎉\n- [x] б»") == Marked("«- [ ] 🎉🎉\n- [ ] б»"))
    }
}
