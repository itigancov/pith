import Testing
@testable import PithNotes

@Suite struct NoteRowContentTests {
    private func content(_ text: String, _ query: String = "") -> NoteRowContent {
        NoteRowContent(text: text, query: SearchQuery(query))
    }

    /// The substrings of `text` that `ranges` cover.
    private func slices(_ text: String, _ ranges: [Range<Int>]) -> [String] {
        let units = Array(text.utf16)
        return ranges.map { String(decoding: units[$0], as: UTF16.self) }
    }

    @Test func emptyQueryShowsTitleAndPreview() {
        let row = content("Groceries\nmilk\n\neggs")
        #expect(row.title == "Groceries")
        #expect(row.detail == "milk · eggs")
        #expect(row.titleHits.isEmpty && row.detailHits.isEmpty)
    }

    @Test func previewDropsBlockMarkersAndKeepsInlineOnes() {
        let row = content("# Plan\n- [ ] **call** Ann\n> quoted\n## Next")
        #expect(row.title == "Plan")
        #expect(row.detail == "**call** Ann · quoted · Next")
    }

    @Test func aSingleLineNoteHasNoDetail() {
        #expect(content("Only line").detail == "")
        #expect(content("").title == "")
    }

    @Test func snippetSurroundsTheFirstMatchOutsideTheTitle() {
        let row = content("Sales call notes\nshort intro\nthe EMEA region wants the export", "region")
        #expect(row.title == "Sales call notes")
        #expect(row.detail == "the EMEA region wants the export")
        #expect(slices(row.detail, row.detailHits) == ["region"])
    }

    @Test func aMatchInTheFirstTwentyCharactersKeepsTheLineStart() {
        let row = content("T\n12345678901234567890region tail", "region")
        #expect(row.detail.hasPrefix("1234567890"))
        #expect(!row.detail.hasPrefix("…"))
    }

    @Test func aLateMatchCutsTheStartAtAWordBoundary() {
        let line = "alpha beta gamma delta epsilon zeta eta theta region iota"
        let row = content("T\n" + line, "region")
        #expect(row.detail.hasPrefix("…"))
        // 20 characters before the match is inside "epsilon", so the snippet starts at the next whole word.
        #expect(row.detail == "…zeta eta theta region iota")
        #expect(slices(row.detail, row.detailHits) == ["region"])
    }

    @Test func aLateMatchWithNoWordBreakStartsAtTheMatch() {
        let row = content("T\n" + String(repeating: "x", count: 40) + "region", "region")
        #expect(row.detail == "…region")
    }

    @Test func everyWordOfTheQueryIsHighlightedInTheSnippet() {
        let row = content("T\nthe quick brown fox", "quick fox")
        #expect(slices(row.detail, row.detailHits) == ["quick", "fox"])
    }

    @Test func aMatchOnlyInTheTitleHighlightsTheTitleAndKeepsThePreview() {
        let row = content("Region report\nnothing here\nmore", "region")
        #expect(slices(row.title, row.titleHits) == ["Region"])
        #expect(row.detail == "nothing here · more")
        #expect(row.detailHits.isEmpty)
    }

    @Test func aMatchInTheTitleAndBelowHighlightsBoth() {
        let row = content("Region\nthe region again", "region")
        #expect(slices(row.title, row.titleHits) == ["Region"])
        #expect(slices(row.detail, row.detailHits) == ["region"])
    }

    @Test func theSnippetHasNoBlockMarker() {
        let row = content("T\n- [ ] ship the region report", "region")
        #expect(row.detail == "ship the region report")
        #expect(slices(row.detail, row.detailHits) == ["region"])
    }

    @Test func matchingIgnoresCaseAndAccents() {
        let row = content("T\nVisit Zürich soon", "zurich")
        #expect(slices(row.detail, row.detailHits) == ["Zürich"])
    }

    @Test func titleHitsAreOffsetsInTheTitleWithoutItsMarker() {
        let row = content("## Big region", "region")
        #expect(row.title == "Big region")
        #expect(slices(row.title, row.titleHits) == ["region"])
    }
}
