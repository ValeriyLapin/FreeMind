import AppKit
@testable import FreeMind
import XCTest

final class ToolbarMenuTests: XCTestCase {
    func testToolbarMenusKeepTheirFirstItemVisible() throws {
        let controller = MapWindowController()
        let toolbar = NSToolbar(identifier: "test")
        let expected = ["theme": Theme.builtins[0].displayName, "structure": MapStructure.allCases[0].title,
                        "marker": MarkerGroup.allCases[0].title, "export": L("Markdown…")]
        for (id, title) in expected {
            let item = try XCTUnwrap(controller.toolbar(toolbar, itemForItemIdentifier: NSToolbarItem.Identifier(id),
                                                        willBeInsertedIntoToolbar: true) as? NSMenuToolbarItem)
            XCTAssertEqual(item.menu.items.first?.title, "", id)
            XCTAssertEqual(item.menu.items.dropFirst().first?.title, title, id)
        }
        let themes = try XCTUnwrap(controller.toolbar(toolbar, itemForItemIdentifier: NSToolbarItem.Identifier("theme"),
                                                      willBeInsertedIntoToolbar: true) as? NSMenuToolbarItem)
        (themes.menu as? ThemeMenu)?.menuNeedsUpdate(themes.menu)
        XCTAssertEqual(themes.menu.items.map(\.title), [""] + Theme.builtins.map(\.displayName)
                       + (ThemeLibrary.shared.customThemes.isEmpty ? [] : [""] + ThemeLibrary.shared.customThemes.map(\.displayName)))
    }
}
