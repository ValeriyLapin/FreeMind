import XCTest
@testable import FreeMind

/// 关掉 Balance Map 后主分支停在自己的一侧。
final class BalanceMapTests: XCTestCase {
    private var doc: MindMapDocument!
    private var editor: MapEditor { doc.editor }

    override func setUp() {
        doc = MindMapDocument()
        doc.editor.load(MindMap.blank(title: "Root"))
        doc.undoManager?.groupsByEvent = false
    }

    private func step(_ body: () -> Void) {
        doc.undoManager?.beginUndoGrouping()
        body()
        doc.undoManager?.endUndoGrouping()
    }

    private var sides: [BranchSide] { editor.map.root.children.map { editor.layout.nodes[$0.id]!.side } }

    func testTurningBalanceOffKeepsTheLayout() {
        let before = sides
        XCTAssertEqual(before, [.right, .right, .left, .left])
        step { editor.setBalanced(false) }
        XCTAssertEqual(editor.map.rightCount, 2)
        XCTAssertEqual(sides, before)
        doc.undoManager?.undo()
        XCTAssertTrue(editor.map.isBalanced)
    }

    func testNewMainTopicsStayOnTheirSide() {
        step { editor.setBalanced(false) }
        editor.select(editor.map.root.children[1].id)
        step { editor.addSibling(edit: false) }
        XCTAssertEqual(editor.map.rightCount, 3)
        XCTAssertEqual(sides, [.right, .right, .right, .left, .left])

        editor.select(editor.map.root.children[3].id)
        step { editor.addSibling(before: true, edit: false) }
        XCTAssertEqual(editor.map.rightCount, 3)
        XCTAssertEqual(sides, [.right, .right, .right, .left, .left, .left])

        step { editor.addChild(to: editor.rootID, edit: false) }
        XCTAssertEqual(editor.map.rightCount, 3)

        editor.setSelection(editor.map.root.children.prefix(2).map(\.id))
        step { editor.deleteSelection() }
        XCTAssertEqual(editor.map.rightCount, 1)
        XCTAssertEqual(sides, [.right, .left, .left, .left, .left])
    }

    func testAllRightMapGrowsOnTheRight() {
        step { editor.setBalanced(false) }
        let ids = editor.map.root.children.map(\.id)
        step { editor.move(Array(ids[2...]), to: editor.rootID, at: 2, side: true) }
        XCTAssertEqual(editor.map.rightCount, 4)
        step { editor.addChild(to: editor.rootID, edit: false) }
        XCTAssertEqual(editor.map.rightCount, 5)
        XCTAssertEqual(Set(sides), [.right])
    }

    func testDraggingMovesBranchToTheOtherSide() {
        step { editor.setBalanced(false) }
        let ids = editor.map.root.children.map(\.id)
        step { editor.move([ids[0]], to: editor.rootID, at: 4, side: false) }
        XCTAssertEqual(editor.map.root.children.map(\.id), [ids[1], ids[2], ids[3], ids[0]])
        XCTAssertEqual(editor.map.rightCount, 1)
        XCTAssertEqual(sides, [.right, .left, .left, .left])

        step { editor.move([ids[2]], to: editor.rootID, at: 0, side: true) }
        XCTAssertEqual(editor.map.root.children.map(\.id), [ids[2], ids[1], ids[3], ids[0]])
        XCTAssertEqual(editor.map.rightCount, 2)
    }

    func testMovingPastTheBottomSwitchesSide() {
        step { editor.setBalanced(false) }
        let ids = editor.map.root.children.map(\.id)
        editor.select(ids[1])
        step { editor.moveSelection(up: false) }
        XCTAssertEqual(editor.map.root.children.map(\.id), ids)
        XCTAssertEqual(editor.map.rightCount, 1)
        XCTAssertEqual(editor.layout.nodes[ids[1]]?.side, .left)
        step { editor.moveSelection(up: false) }
        XCTAssertEqual(editor.map.rightCount, 2)
        XCTAssertEqual(editor.layout.nodes[ids[1]]?.side, .right)
    }

    func testDroppingInEmptySpaceMovesBranchToThatSide() throws {
        step { editor.setBalanced(false) }
        let canvas = MindMapCanvasView(editor: editor)
        let ids = editor.map.root.children.map(\.id)
        let root = try XCTUnwrap(editor.layout.nodes[editor.rootID]).frame
        let leftmost = editor.layout.nodes.values.map(\.frame.minX).min()!
        let far = CGPoint(x: leftmost - 200, y: root.minY - 400)
        let target = try XCTUnwrap(canvas.dropTarget(at: far, dragging: [ids[0]]))
        XCTAssertEqual(target.parentID, editor.rootID)
        XCTAssertEqual(target.side, false)
        step { editor.move([ids[0]], to: target.parentID, at: target.index, side: target.side) }
        XCTAssertEqual(editor.layout.nodes[ids[0]]?.side, .left)
        XCTAssertEqual(editor.map.rightCount, 1)

        let gap = try XCTUnwrap(editor.layout.nodes[ids[2]]).frame
        let between = CGPoint(x: gap.midX, y: gap.maxY + 20)
        let inGap = try XCTUnwrap(canvas.dropTarget(at: between, dragging: [ids[1]]))
        XCTAssertEqual(inGap.parentID, editor.rootID)
        XCTAssertEqual(inGap.side, false)
    }

    func testBalancedMapDropInEmptySpaceDoesNothing() {
        let canvas = MindMapCanvasView(editor: editor)
        let leftmost = editor.layout.nodes.values.map(\.frame.minX).min()!
        XCTAssertNil(canvas.dropTarget(at: CGPoint(x: leftmost - 400, y: 0), dragging: [editor.map.root.children[0].id]))
    }

    func testBalancedMapIgnoresSides() {
        let ids = editor.map.root.children.map(\.id)
        step { editor.move([ids[0]], to: editor.rootID, at: nil, side: false) }
        XCTAssertNil(editor.map.rightCount)
        XCTAssertEqual(sides, [.right, .right, .left, .left])
    }

    func testRightCountIsSavedOnlyWhenUnbalanced() throws {
        var map = MindMap.blank()
        let balanced = try JSONEncoder().encode(map)
        XCTAssertFalse(String(decoding: balanced, as: UTF8.self).contains("rightCount"))
        XCTAssertNil(try JSONDecoder().decode(MindMap.self, from: balanced).rightCount)
        map.rightCount = 1
        XCTAssertEqual(try JSONDecoder().decode(MindMap.self, from: JSONEncoder().encode(map)).rightCount, 1)
    }

    func testXMindRightNumberRoundTrips() throws {
        let session = try XMindSession(data: try XMindTests.makeWorkbook())
        var map = session.snapshot
        XCTAssertTrue(map.isBalanced)
        map.rightCount = 4
        let written = try session.serialized(current: map, resources: { session.resources[$0] }, preview: { nil })
        let root = try XCTUnwrap(XMindTests.content(written)["rootTopic"] as? [String: Any])
        XCTAssertEqual(root["structureClass"] as? String, "org.xmind.ui.map.unbalanced")
        let extensions = try XCTUnwrap(root["extensions"] as? [[String: Any]])
        XCTAssertEqual(extensions.compactMap { $0["provider"] as? String }, ["custom", "org.xmind.ui.map.unbalanced"])
        let reread = try XMindSession(data: written)
        XCTAssertEqual(reread.snapshot.rightCount, 4)

        var balanced = reread.snapshot
        balanced.rightCount = nil
        let rewritten = try reread.serialized(current: balanced, resources: { reread.resources[$0] }, preview: { nil })
        let root2 = try XCTUnwrap(XMindTests.content(rewritten)["rootTopic"] as? [String: Any])
        XCTAssertEqual(root2["structureClass"] as? String, "org.xmind.ui.map.clockwise")
        XCTAssertEqual((root2["extensions"] as? [[String: Any]])?.compactMap { $0["provider"] as? String }, ["custom"])
        XCTAssertTrue(try XMindSession(data: rewritten).snapshot.isBalanced)
    }

    func testUnbalancedXMindWithoutRightNumberSplitsInHalf() {
        let root: [String: Any] = ["structureClass": "org.xmind.ui.map.unbalanced",
                                   "children": ["attached": [[:], [:], [:]]]]
        XCTAssertEqual(XMindImporter.rightCount(from: root), 2)
        XCTAssertNil(XMindImporter.rightCount(from: ["structureClass": "org.xmind.ui.map.clockwise"]))
    }
}
