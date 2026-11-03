import AppKit
@testable import FreeMind
import XCTest

final class XMindTests: XCTestCase {
    static func makeWorkbook() throws -> Data {
        let png = MindManagerTests.tinyPNG
        let root: [String: Any] = [
            "id": "root-1", "class": "topic", "title": "Root", "structureClass": "org.xmind.ui.map.clockwise",
            "extensions": [["provider": "custom", "content": ["keep": true]]],
            "children": [
                "attached": [
                    ["id": "a", "title": "Alpha", "attributedTitle": [["text": "Alpha"]],
                     "markers": [["markerId": "priority-1"], ["markerId": "unknown-marker"]], "labels": ["L1"],
                     "notes": ["plain": ["content": "Note A"], "realHTML": ["content": "<div>Note A</div>"]],
                     "children": ["attached": [["id": "a1", "title": "A1"], ["id": "a2", "title": "A2"]],
                                  "callout": [["id": "ac", "title": "Callout"]]],
                     "boundaries": [["id": "bd", "range": "(0,1)", "title": "Box"]], "branch": "folded"],
                    ["id": "b", "title": "Beta", "href": "https://example.com",
                     "image": ["src": "xap:resources/pic.png", "width": 40, "height": 30, "align": "top"]],
                    ["id": "c", "title": "file.txt", "href": "xap:resources/file.txt"],
                ],
                "summary": [["id": "s", "title": "Summary"]],
                "detached": [["id": "d", "title": "Floating", "position": ["x": 10, "y": 20]]],
            ] as [String: Any],
            "summaries": [["id": "sum", "range": "(0,1)", "topicId": "s"]],
        ]
        let sheet: [String: Any] = [
            "id": "sheet-1", "class": "sheet", "title": "Sheet", "rootTopic": root, "theme": ["map": ["id": "t"]],
            "relationships": [["id": "r", "end1Id": "a1", "end2Id": "b", "title": "Rel",
                               "controlPoints": ["0": ["x": 1, "y": 2]]]],
        ]
        var archive = ZipArchive()
        try archive.set(XMindSession.json([sheet]), for: "content.json", compress: false)
        try archive.set(XMindSession.json(["creator": ["name": "Test"]]), for: "metadata.json", compress: false)
        try archive.set(XMindSession.json(["file-entries": ["content.json": [String: Any](), "resources/pic.png": [String: Any]()]]),
                        for: "manifest.json", compress: false)
        try archive.set(png, for: "resources/pic.png", compress: false)
        try archive.set(Data("hello".utf8), for: "resources/file.txt", compress: false)
        try archive.set(Data("legacy".utf8), for: "content.xml", compress: false)
        return archive.serialized()
    }

    static func content(_ data: Data) throws -> [String: Any] {
        let archive = try ZipArchive(data: data)
        let sheets = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(archive.contents(of: "content.json"))) as? [[String: Any]])
        return try XCTUnwrap(sheets.first)
    }

    static func topic(_ id: String, in sheet: [String: Any]) -> [String: Any]? {
        func find(_ t: [String: Any]) -> [String: Any]? {
            if t["id"] as? String == id { return t }
            for case let list as [[String: Any]] in ((t["children"] as? [String: Any]) ?? [:]).values {
                for child in list { if let found = find(child) { return found } }
            }
            return nil
        }
        return (sheet["rootTopic"] as? [String: Any]).flatMap(find)
    }

    func testWorkbookIsReadWithStableIDs() throws {
        let data = try Self.makeWorkbook()
        let session = try XMindSession(data: data)
        let map = session.snapshot
        XCTAssertEqual(map.root.title, "Root")
        XCTAssertEqual(map.structure, .mindMap)
        XCTAssertEqual(map.root.children.map(\.title), ["Alpha", "Beta", "file.txt", "Summary", "Floating"])
        let alpha = map.root.children[0]
        XCTAssertEqual(alpha.children.map(\.title), ["A1", "A2", "Callout"])
        XCTAssertEqual(alpha.children.map { $0.style.boundary == true }, [true, true, false])
        XCTAssertTrue(alpha.collapsed)
        XCTAssertEqual(alpha.markers, [MarkerID("priority-1")])
        XCTAssertEqual(alpha.note, "Note A")
        XCTAssertEqual(map.root.children[1].link, "https://example.com")
        XCTAssertEqual(map.root.children[1].image?.width, 40)
        XCTAssertEqual(map.root.children[2].attachments.count, 1)
        XCTAssertEqual(map.relationships.map(\.title), ["Rel"])
        XCTAssertEqual(try XMindSession(data: data).snapshot, map)
        XCTAssertEqual(try session.serialized(current: map, resources: { session.resources[$0] }, preview: { nil }), data)
    }

    func testEditsKeepUnknownContent() throws {
        let session = try XMindSession(data: try Self.makeWorkbook())
        var map = session.snapshot
        let alpha = map.root.children[0], beta = map.root.children[1]
        let fresh = Topic(title: "New", note: "Line 1\n\nLine <3>", markers: [MarkerID("task-50"), MarkerID("symbol-time")])
        _ = map.update(alpha.id) {
            $0.title = "Alpha edited"
            $0.markers = [MarkerID("priority-2"), MarkerID("star-blue")]
            $0.labels = []
            $0.collapsed = false
            $0.children.swapAt(0, 1)
            $0.children[0].style.boundary = false
            $0.children.insert(fresh, at: 1)
        }
        _ = map.update(beta.id) { $0.link = "https://example.org" }
        map.structure = .logicRight
        map.relationships.append(Relationship(from: fresh.id, to: beta.id, title: "New rel"))
        let written = try session.serialized(current: map, resources: { session.resources[$0] }, preview: { MindManagerTests.tinyPNG })

        let reread = try XMindSession(data: written)
        XCTAssertEqual(XMindProjection(reread.snapshot, kinds: reread.index.kinds).root.children.map(\.title),
                       ["Alpha edited", "Beta", "file.txt", "Summary", "Floating"])
        let sheet = try Self.content(written)
        XCTAssertNotNil(sheet["theme"])
        let root = try XCTUnwrap(sheet["rootTopic"] as? [String: Any])
        XCTAssertEqual(root["structureClass"] as? String, "org.xmind.ui.logic.right")
        XCTAssertNotNil(root["extensions"])
        XCTAssertEqual((root["summaries"] as? [[String: Any]])?.first?["topicId"] as? String, "s")
        let a = try XCTUnwrap(Self.topic("a", in: sheet))
        XCTAssertNil(a["attributedTitle"])
        XCTAssertNil(a["labels"])
        XCTAssertNil(a["branch"])
        XCTAssertEqual((a["markers"] as? [[String: Any]])?.compactMap { $0["markerId"] as? String },
                       ["unknown-marker", "priority-2", "star-blue"])
        XCTAssertEqual((a["boundaries"] as? [[String: Any]])?.compactMap { $0["range"] as? String }, ["(2,2)"])
        let fresh2 = try XCTUnwrap(Self.topic(fresh.id.uuidString.lowercased(), in: sheet))
        XCTAssertEqual(((fresh2["notes"] as? [String: Any])?["realHTML"] as? [String: Any])?["content"] as? String,
                       "<div>Line 1</div><div><br></div><div>Line &lt;3&gt;</div>")
        XCTAssertEqual((fresh2["markers"] as? [[String: Any]])?.compactMap { $0["markerId"] as? String }, ["task-half", "c_symbol_hourglass"])
        let rels = try XCTUnwrap(sheet["relationships"] as? [[String: Any]])
        XCTAssertNotNil(rels.first?["controlPoints"])
        XCTAssertEqual(rels.count, 2)
        XCTAssertEqual(((Self.topic("b", in: sheet)?["image"]) as? [String: Any])?["align"] as? String, "top")
        XCTAssertNotNil(try ZipArchive(data: written).entry(named: "Thumbnails/thumbnail.png"))
        XCTAssertEqual(try ZipArchive(data: written).contents(of: "content.xml"), Data("legacy".utf8))
    }

    func testMovedAndRemovedTopicsKeepWorkbookValid() throws {
        let session = try XMindSession(data: try Self.makeWorkbook())
        var map = session.snapshot
        let alpha = map.root.children[0]
        let callout = alpha.children[2], summary = map.root.children[3], floating = map.root.children[4]
        map.root.children.removeAll { $0.id == summary.id || $0.id == floating.id }
        _ = map.update(alpha.id) { $0.children.removeAll { $0.id == callout.id } }
        map.root.children.append(floating)
        _ = map.update(map.root.children[1].id) { $0.children = [callout] }
        let written = try session.serialized(current: map, resources: { session.resources[$0] }, preview: { nil })
        let root = try XCTUnwrap(try Self.content(written)["rootTopic"] as? [String: Any])
        XCTAssertNil(root["summaries"])
        let children = try XCTUnwrap(root["children"] as? [String: Any])
        XCTAssertNil(children["summary"])
        XCTAssertEqual((children["detached"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(((Self.topic("b", in: try Self.content(written))?["children"] as? [String: Any])?["attached"] as? [[String: Any]])?.count, 1)
    }

    func testNewMapIsSavedAsXMindWorkbook() throws {
        let doc = MindMapDocument()
        var map = doc.editor.map
        map.root.title = "Plan"
        var first = Topic(title: "First", note: "Note", markers: [MarkerID("priority-1"), MarkerID("flag-red")], labels: ["x"])
        let imageID = doc.attachments.add(data: MindManagerTests.tinyPNG, name: "pic.png")
        first.image = TopicImage(id: imageID, name: "pic.png", width: 40, height: 30)
        first.children = [Topic(title: "Child")]
        var second = Topic(title: "Second")
        let fileID = doc.attachments.add(data: Data("hello".utf8), name: "readme.txt")
        second.attachments = [Attachment(id: fileID, name: "readme.txt", size: 5)]
        second.style.boundary = true
        map.root.children = [first, second]
        map.structure = .orgChart
        map.relationships = [Relationship(from: first.children[0].id, to: second.id, title: "R")]
        doc.editor.load(map)

        let written = try XCTUnwrap(try doc.fileWrapper(ofType: DocumentTypes.xmind).regularFileContents)
        let reread = try XMindSession(data: written)
        XCTAssertEqual(XMindProjection(reread.snapshot, kinds: reread.index.kinds), XMindProjection(map, kinds: [:]))
        XCTAssertEqual(reread.resources[imageID]?.data, MindManagerTests.tinyPNG)
        XCTAssertEqual(reread.resources[fileID]?.data, Data("hello".utf8))
        let manifest = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(try ZipArchive(data: written).contents(of: "manifest.json"))) as? [String: Any])
        XCTAssertEqual((manifest["file-entries"] as? [String: Any])?.count, 4)

        doc.editor.setTitle(second.id, "Second edited")
        let again = try XCTUnwrap(try doc.fileWrapper(ofType: DocumentTypes.xmind).regularFileContents)
        XCTAssertEqual(try XMindSession(data: again).snapshot.topic(second.id)?.title, "Second edited")
        XCTAssertTrue(doc.writableTypes(for: .saveAsOperation).contains(DocumentTypes.xmind))
    }

    func testFormatLossListsOnlyChangesTheFormatDrops() throws {
        let session = try XMindSession(data: try Self.makeWorkbook())
        var map = session.snapshot
        XCTAssertEqual(FormatLoss.features(of: map, type: DocumentTypes.xmind, baseline: session.snapshot), [])
        _ = map.update(map.root.children[0].id) { $0.labels = ["new"]; $0.style.bold = true }
        XCTAssertEqual(FormatLoss.features(of: map, type: DocumentTypes.xmind, baseline: session.snapshot), [L("Topic styles")])
        XCTAssertEqual(FormatLoss.features(of: map, type: DocumentTypes.mindManager, baseline: session.snapshot),
                       [L("Topic styles"), L("Labels")])
        var fresh = MindMap(root: Topic(title: "Plan", children: [Topic(title: "A", markers: [MarkerID("star-red")])]),
                            theme: Preferences.shared.defaultTheme)
        XCTAssertEqual(FormatLoss.features(of: fresh, type: DocumentTypes.xmind, baseline: nil), [])
        fresh.structure = .orgChart
        XCTAssertEqual(FormatLoss.features(of: fresh, type: DocumentTypes.mindManager, baseline: nil), [L("Some markers"), L("Structure")])
    }

    func testRealXMindSamples() throws {
        let env = ProcessInfo.processInfo.environment
        guard let list = env["FREEMIND_XMIND_SAMPLES"], !list.isEmpty else { throw XCTSkip("FREEMIND_XMIND_SAMPLES not set") }
        let output = env["FREEMIND_XMIND_OUT"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let files = try String(contentsOfFile: list, encoding: .utf8).split(separator: "\n").map(String.init)
            .filter { $0.lowercased().hasSuffix(".xmind") && FileManager.default.fileExists(atPath: $0) }
        var report: [String] = []
        var failures = 0
        for (n, path) in files.enumerated() {
            let label = String(format: "%03d", n)
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                guard let session = try? XMindSession(data: data) else { report.append("\(label) SKIP not JSON"); continue }
                let lookup: (UUID) -> ResourceFile? = { session.resources[$0] }
                XCTAssertEqual(try session.serialized(current: session.snapshot, resources: lookup, preview: { nil }), data)
                var map = session.snapshot
                _ = MindManagerTests.applyRealEdits(&map)
                let written = try session.serialized(current: map, resources: lookup, preview: { nil })
                report.append("\(label) OK topics=\(map.root.subtreeCount) sheets=\(session.sheets.count) resources=\(session.resources.count) relationships=\(session.snapshot.relationships.count)")
                if let output { try written.write(to: output.appendingPathComponent("\(label).xmind")) }
            } catch {
                failures += 1
                report.append("\(label) ERROR \(error.localizedDescription)")
            }
        }
        let text = report.joined(separator: "\n") + "\nfiles=\(files.count) failures=\(failures)\n"
        try text.write(toFile: list + ".report.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(failures, 0, text)
    }
}
