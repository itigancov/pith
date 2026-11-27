import AppKit
import Foundation
import SwiftUI
import Testing
@testable import PithApp
@testable import PithNotes

/// What an accessibility client sees and what VoiceOver is told: the pass of 17a, pinned so that no refactor drops it.
@MainActor
struct AccessibilityTests {
    // MARK: Announcements

    @Test func theToastAfterCommandDeleteIsAnnouncedAtHighPriority() throws {
        let world = try TrashWorld()
        try world.insert("one")
        try world.insert("two")
        world.launch()
        let heard = announcements { world.note.moveToTrash() }
        #expect(heard == [Announcer.Announcement(text: "Note moved to Trash", priority: .high)])
    }

    @Test func theSizePillAnnouncesTheNewSize() throws {
        let world = try TrashWorld()
        try world.insert("one")
        world.launch()
        let heard = announcements { world.note.showSizeHUD(size: 17) }
        #expect(heard == [Announcer.Announcement(text: "Text size 17 points", priority: .medium)])
    }

    @Test func pagingThroughTheStackAnnouncesThePlace() throws {
        let world = try TrashWorld()
        try world.insert("one")
        try world.insert("two")
        world.launch()
        #expect(announcements { world.note.previousNote() } == [Announcer.Announcement(text: "Note 1 of 2", priority: .high)])
        #expect(announcements { world.note.nextNote() } == [Announcer.Announcement(text: "Latest, note 2 of 2", priority: .high)])
    }

    @Test func searchAnnouncesTheCountAndTheEmptyResult() throws {
        let world = try SearchWorld()
        try world.insert("alpha one")
        try world.insert("alpha two")
        world.launch()
        let screen = try world.openSearch()
        #expect(announcements { screen.setQuery("alpha") } == [Announcer.Announcement(text: "2 notes", priority: .medium)])
        #expect(announcements { screen.setQuery("zzz") } == [Announcer.Announcement(text: "No notes match “zzz”", priority: .medium)])
    }

    @Test func theSelectionPillAnnouncesHowManyRowsAreSelected() throws {
        let world = try SearchWorld()
        for text in ["a", "b", "c", "d"] { try world.insert("note \(text)") }
        world.launch()
        let screen = try world.openSearch()
        let heard = announcements { screen.selectRows(from: 1, to: 3) }
        #expect(heard.contains(Announcer.Announcement(text: "3 selected", priority: .medium)))
    }

    // MARK: Names and roles

    @Test func theFooterIsOneStaticTextWithThePlaceOfTheNote() throws {
        let world = try TrashWorld()
        try world.insert("one")
        try world.insert("two")
        world.launch()
        let footer = world.note.footer
        #expect(footer.isAccessibilityElement())
        #expect(footer.accessibilityRole() == .staticText)
        #expect(footer.accessibilityLabel() == "Latest, note 2 of 2")
        world.note.previousNote()
        #expect(footer.accessibilityLabel() == "Note 1 of 2")
    }

    @Test func theEditorIsATextAreaNamedNote() throws {
        let world = try TrashWorld()
        try world.insert("one")
        world.launch()
        #expect(world.note.editor.accessibilityRole() == .textArea)
        #expect(world.note.editor.accessibilityLabel() == "Note")
    }

    @Test func aSearchRowIsOneCellWithTheTitleTheTimeAndTheStartOfTheNote() throws {
        let world = try SearchWorld()
        try world.insert("Alpha\nfirst words of the note")
        world.launch()
        let screen = try world.openSearch()
        world.layOut()
        let cell = try #require(screen.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SearchRowCell)
        let label = try #require(cell.accessibilityLabel())
        #expect(label == "Alpha, \(screen.display(at: 0).time), first words of the note")
        // The table makes the row and the cell; a row inside a cell says everything twice.
        #expect(cell.accessibilityRole() != .row)
    }

    @Test func aTrashRowIsOneCellWithTheTitleAndTheTime() throws {
        let world = try TrashWorld()
        let note = try world.insert("Gamma note")
        try world.trash(note)
        world.launch()
        let screen = try world.openTrash()
        screen.view.frame = NSRect(x: 0, y: 0, width: 540, height: 440)
        screen.view.layoutSubtreeIfNeeded()
        let cell = try #require(screen.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? TrashRowCell)
        #expect(cell.accessibilityLabel() == "Gamma note, \(screen.display(at: 0).time)")
        #expect(cell.accessibilityRole() != .row)
    }

    @Test func theButtonsOfTheTrashNameTheirAction() throws {
        let world = try TrashWorld()
        try world.trash(try world.insert("Gamma note"))
        world.launch()
        let screen = try world.openTrash()
        screen.view.frame = NSRect(x: 0, y: 0, width: 540, height: 440)
        screen.view.layoutSubtreeIfNeeded()
        let names = Set(buttonNames(in: screen.view))
        #expect(names.isSuperset(of: ["Back to notes", "Empty Trash"]))
    }

    private func buttonNames(in view: NSView) -> [String] {
        var names: [String] = []
        if view is NSButton, let label = view.accessibilityLabel() { names.append(label) }
        for sub in view.subviews { names += buttonNames(in: sub) }
        return names
    }

    @Test func theSettingsWindowIsNamedAfterTheTabItShows() throws {
        let defaults = UserDefaults(suiteName: "pith-tests-" + UUID().uuidString)!
        let shortcuts = ShortcutStore(defaults: defaults, menuKeys: { [] }, systemShortcuts: { [] }, layout: StubLayout(), registrar: FakeRegistrar())
        let store = try NoteStore.open(at: .memory).store
        let context = SettingsContext(
            shortcuts: shortcuts, textSize: TextSizeModel(defaults: defaults), appearance: AppearanceModel(defaults: defaults),
            latestMeans: LatestMeansModel(defaults: defaults), trash: SettingsTrash(store: { store }),
            loginItem: LoginItem(service: FakeLoginService(), location: .applications, defaults: defaults)
        )
        let controller = SettingsWindowController(context: context, defaults: defaults)
        let window = controller.makeWindow()
        let tabs = try #require(window.contentViewController as? NSTabViewController)
        #expect(window.title == "General")
        tabs.selectedTabViewItemIndex = 1
        #expect(window.title == "Shortcuts")
        tabs.selectedTabViewItemIndex = 0
        #expect(window.title == "General")
    }

    // MARK: Contrast (WCAG 2.1 AA, 1.4.3), from the tokens

    @Test func theWhiteLabelOnRestoreHasFourAndAHalfToOne() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let fill = resolved(TrashStyle.restoreFill, as: name)
            #expect(contrast(.white, fill) >= 4.5, "Restore, \(name.rawValue)")
        }
    }

    @Test func theRedOfARejectionReadsOnTheSettingsWindowInBothThemes() {
        // The grouped form is white in light; in dark it is about #2C2C2E, tested against the lighter #323232 as well.
        #expect(contrast(resolved(SettingsColors.errorInk, as: .aqua), NSColor.white) >= 4.5)
        #expect(contrast(resolved(SettingsColors.errorInk, as: .darkAqua), NSColor(white: 50 / 255, alpha: 1)) >= 4.5)
    }

    @Test func theRedOfTheTrashReadsOnThePanelInBothThemes() {
        #expect(contrast(resolved(TrashStyle.red, as: .aqua), NSColor.white) >= 4.5)
        #expect(contrast(resolved(TrashStyle.red, as: .darkAqua), NSColor(srgbRed: 0x26 / 255, green: 0x26 / 255, blue: 0x28 / 255, alpha: 1)) >= 4.5)
    }

    private func resolved(_ color: NSColor, as name: NSAppearance.Name) -> NSColor {
        var result = color
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB) ?? color
        }
        return result
    }

    private func luminance(_ color: NSColor) -> Double {
        func linear(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let c = color.usingColorSpace(.sRGB) ?? color
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
