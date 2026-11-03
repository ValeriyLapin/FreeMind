import AppKit
import XCTest
@testable import FreeMind

final class MindManagerTests: XCTestCase {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
    static func oid(_ n: Int) -> String { MindManagerXML.oid(id(n)) }

    static let root = 1, alpha = 2, a1 = 3, a2 = 4, beta = 5, b1 = 6, gamma = 7, floating = 8, relation = 9, image = 10

    static var tinyPNG: Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    static func topic(_ n: Int, _ title: String, extra: String = "", children: String = "", floating: String = "",
                      collapsed: Bool = false) -> String {
        let sub = children.isEmpty ? "" : "<ap:SubTopics>\(children)</ap:SubTopics>"
        let float = floating.isEmpty ? "" : "<ap:FloatingTopics>\(floating)</ap:FloatingTopics>"
        return """
        <ap:Topic Dirty="0000000000000001" OId="\(oid(n))" Gen="0000000000000000">\(sub)\(float)\
        <ap:TopicViewGroup ViewIndex="0"><ap:Collapsed Dirty="0000000000000001" Collapsed="\(collapsed)"/></ap:TopicViewGroup>\
        <ap:Text Dirty="0000000000000001" PlainText="\(title)" ReadOnly="false"><ap:Font/>\
        <ap:FontRange From="0" To="\(title.utf16.count - 1)" Bold="true" Name="Helvetica" Size="14.000000"/></ap:Text>\(extra)</ap:Topic>
        """
    }

    static var documentXML: Data {
        let imageEntry = "bin/\(id(image).uuidString).bin"
        let a1Topic = topic(a1, "Alpha one")
        let a2Topic = topic(a2, "Alpha two", extra: """
        <ap:Offset Dirty="0000000000000001" CX="5.000000" CY="6.000000"/><ap:IconsGroup><ap:Icons Dirty="0000000000000001">\
        <ap:Icon xsi:type="ap:StockIcon" IconType="urn:mindjet:FlagRed"/><ap:Icon xsi:type="ap:StockIcon" IconType="urn:mindjet:ArrowUp"/>\
        </ap:Icons></ap:IconsGroup>
        """)
        let alphaTopic = topic(alpha, "Alpha", extra: """
        <ap:Color Dirty="0000000000000001" FillColor="ffff0000"/><ap:Offset Dirty="0000000000000001" CX="10.000000" CY="20.000000"/>\
        <ap:Hyperlink Dirty="0000000000000001" Url="https://alpha.example" Absolute="false" Title="Alpha site"/>\
        <ap:Task Dirty="0000000000000001" TaskPriority="urn:mindjet:Prio1" TaskPercentage="50"/>
        """, children: a1Topic + a2Topic)
        let betaTopic = topic(beta, "Beta", extra: """
        <ap:NotesGroup><ap:NotesXhtmlData Dirty="0000000000000001" PreviewPlainText="Line one"><html xmlns="http://www.w3.org/1999/xhtml">\
        <p>Line one</p><p>Line two</p></html></ap:NotesXhtmlData></ap:NotesGroup>
        """, children: topic(b1, "Beta one", extra: """
        <ap:NotesGroup><ap:NotesXhtmlData Dirty="0000000000000001" PreviewPlainText="a b"><html xmlns="http://www.w3.org/1999/xhtml">\
        <p>a<span> </span>b<br></br>c<br/></p></html></ap:NotesXhtmlData></ap:NotesGroup>
        """), collapsed: true)
        let gammaTopic = """
        <ap:Topic Dirty="0000000000000001" OId="\(oid(gamma))" Gen="0000000000000000"><ap:OneImage><ap:Image Dirty="0000000000000000" OId="\(oid(image))" Gen="0000000000000000">\
        <ap:ImageData Dirty="0000000000000000" ImageType="urn:mindjet:PngImage"><cor:Uri xsi:nil="false">mmarch://\(imageEntry)</cor:Uri></ap:ImageData>\
        <ap:ImageSize Dirty="0000000000000001" Width="40.000000" Height="30.000000"/></ap:Image></ap:OneImage>\
        <ap:TopicViewGroup ViewIndex="0"/><ap:Text Dirty="0000000000000001" PlainText="Gamma" ReadOnly="false"><ap:Font/></ap:Text></ap:Topic>
        """
        let rootTopic = topic(root, "Root", children: alphaTopic + betaTopic + gammaTopic, floating: topic(floating, "Floating"))
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <ap:Map Dirty="0000000000000001" OId="\(oid(99))" Gen="0000000000000000" xmlns:ap="http://schemas.mindjet.com/MindManager/Application/2003" \
        xmlns:cor="http://schemas.mindjet.com/MindManager/Core/2003" xmlns:pri="http://schemas.mindjet.com/MindManager/Primitive/2003" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><cor:Custom Index="0" Uri="http://example.com/addin" Dirty="0000000000000000"/>\
        <ap:OneTopic>\(rootTopic)</ap:OneTopic><ap:Relationships><ap:Relationship Dirty="0000000000000001" OId="\(oid(relation))" Gen="0000000000000000">\
        <ap:ConnectionGroup Index="0"><ap:Connection Dirty="0000000000000001" CX="1.0" CY="2.0"><ap:ObjectReference OIdRef="\(oid(a1))"/></ap:Connection></ap:ConnectionGroup>\
        <ap:ConnectionGroup Index="1"><ap:Connection Dirty="0000000000000001" CX="3.0" CY="4.0"><ap:ObjectReference OIdRef="\(oid(b1))"/></ap:Connection></ap:ConnectionGroup>\
        <ap:RelationshipViewGroup ViewIndex="0"/><ap:AutoRoute Dirty="0000000000000001" AutoRouting="true"/></ap:Relationship></ap:Relationships>\
        <ap:StyleGroup/><ap:MapViewGroup ViewIndex="0" RowIndex="0" ColumnIndex="0"><ap:Selection Dirty="0000000000000001">\
        <ap:ObjectReference OIdRef="\(oid(a1))"/><ap:ObjectReference OIdRef="\(oid(a2))"/></ap:Selection>\
        <ap:VisibleRoot><ap:ObjectReference OIdRef="\(oid(a1))"/></ap:VisibleRoot></ap:MapViewGroup></ap:Map>
        """
        return Data(xml.utf8)
    }

    static func makeMap(password: String? = nil) throws -> Data {
        var archive = ZipArchive()
        let imageEntry = "bin/\(id(image).uuidString).bin"
        if let password {
            try archive.set(try MindManagerCrypto.encrypt(documentXML.replacingImageEntry(encrypted: true), password: password),
                            for: MindManagerPackage.encryptedDocumentEntry)
            try archive.set(try MindManagerCrypto.encrypt(tinyPNG, password: password), for: imageEntry + MindManagerCrypto.encryptedSuffix)
        } else {
            try archive.set(documentXML, for: MindManagerPackage.documentEntry)
            try archive.set(tinyPNG, for: imageEntry, compress: false)
            try archive.set(Data("preview".utf8), for: "Preview.png", compress: false)
            try archive.set(Data("%PDF-old".utf8), for: "PDFPreview.pdf")
        }
        try archive.set(Data("<schema/>".utf8), for: "xsd/MindManagerApplication.xsd")
        return archive.serialized()
    }

    static func resources(of session: MindManagerSession) -> (UUID) -> ResourceFile? {
        { session.resources[$0] }
    }

    // MARK: Crypto and container

    func testCryptoRoundTripAcrossPasswordLengths() throws {
        let payload = Data(String(repeating: "Карта mind map 🗺️ ", count: 500).utf8)
        for password in ["a", "test", "password9", "пароль", String(repeating: "x", count: 56)] {
            let sealed = try MindManagerCrypto.encrypt(payload, password: password)
            XCTAssertTrue(MindManagerCrypto.isEncrypted(sealed))
            XCTAssertEqual(sealed.count % 8, 0)
            XCTAssertEqual(try MindManagerCrypto.decrypt(sealed, password: password), payload, password)
            XCTAssertThrowsError(try MindManagerCrypto.decrypt(sealed, password: password + "!")) { error in
                guard case MindManagerCrypto.CryptoError.wrongPassword = error else { return XCTFail("\(error)") }
            }
        }
        XCTAssertThrowsError(try MindManagerCrypto.encrypt(payload, password: String(repeating: "x", count: 57)))
    }

    func testShortPasswordKeyMatchesRepeatedKey() throws {
        let payload = Data("same key schedule".utf8)
        let sealed = try MindManagerCrypto.encrypt(payload, password: "abc")
        XCTAssertEqual(try MindManagerCrypto.decrypt(sealed, password: "abcabcabc"), payload)
    }

    func testZipKeepsUntouchedEntriesByteForByte() throws {
        var archive = ZipArchive()
        try archive.set(Data(String(repeating: "keep me ", count: 200).utf8), for: "bin/keep.bin")
        try archive.set(Data("old".utf8), for: "Document.xml")
        let first = try ZipArchive(data: archive.serialized())
        var edited = first
        try edited.set(Data("new".utf8), for: "Document.xml")
        let second = try ZipArchive(data: edited.serialized())
        XCTAssertEqual(second.entry(named: "bin/keep.bin")?.payload, first.entry(named: "bin/keep.bin")?.payload)
        XCTAssertEqual(second.entry(named: "bin/keep.bin")?.crc32, first.entry(named: "bin/keep.bin")?.crc32)
        XCTAssertEqual(try second.contents(of: "Document.xml"), Data("new".utf8))
        XCTAssertEqual(second.entries.map(\.name), ["bin/keep.bin", "Document.xml"])
    }

    // MARK: Reading

    func testReadsTopicsMarkersNotesImagesAndRelationships() throws {
        let session = try MindManagerSession(data: try Self.makeMap(), password: nil)
        let map = session.snapshot
        XCTAssertEqual(map.root.id, Self.id(Self.root))
        XCTAssertEqual(map.root.children.map(\.title), ["Alpha", "Beta", "Gamma", "Floating"])
        let alpha = try XCTUnwrap(map.topic(Self.id(Self.alpha)))
        XCTAssertEqual(alpha.markers, [MarkerID("priority-1"), MarkerID("task-50")])
        XCTAssertEqual(alpha.link, "https://alpha.example")
        XCTAssertEqual(map.topic(Self.id(Self.a2))?.markers, [MarkerID("flag-red")])
        let beta = try XCTUnwrap(map.topic(Self.id(Self.beta)))
        XCTAssertEqual(beta.note, "Line one\nLine two")
        XCTAssertTrue(beta.collapsed)
        let gamma = try XCTUnwrap(map.topic(Self.id(Self.gamma)))
        XCTAssertEqual(gamma.image?.id, Self.id(Self.image))
        XCTAssertEqual(gamma.image?.width, 40)
        XCTAssertEqual(session.resources[Self.id(Self.image)]?.data, Self.tinyPNG)
        XCTAssertEqual(map.relationships.map(\.id), [Self.id(Self.relation)])
        XCTAssertEqual(map.relationships.first?.from, Self.id(Self.a1))
    }

    func testUnchangedMapIsWrittenBackByteForByte() throws {
        let data = try Self.makeMap()
        let session = try MindManagerSession(data: data, password: nil)
        var map = session.snapshot
        map.structure = .orgChart
        map.root.children[0].style.bold = true
        let written = try session.serialized(current: map, resources: Self.resources(of: session), preview: { nil })
        XCTAssertEqual(written, data)
    }

    // MARK: Writing

    @discardableResult
    static func applyEdits(_ map: inout MindMap) -> Topic {
        _ = map.update(id(alpha)) { $0.title = "Alpha renamed"; $0.markers = [MarkerID("priority-3"), MarkerID("task-50")] }
        var moved: Topic?
        map.root.mutateAll { t in
            if let i = t.children.firstIndex(where: { $0.id == id(a2) }) { moved = t.children.remove(at: i) }
        }
        map.root.mutateAll { t in t.children.removeAll { $0.id == id(a1) } }
        moved!.markers = [MarkerID("flag-green"), MarkerID("flag-red")]
        _ = map.update(id(beta)) { $0.children.append(moved!); $0.collapsed = false }
        _ = map.update(id(gamma)) { $0.image = nil }
        _ = map.update(id(floating)) { $0.title = "Floating\nsecond line" }
        let fresh = Topic(title: "New <topic> & \"quotes\"", note: "First\nSecond", link: "https://new.example",
                          markers: [MarkerID("priority-2"), MarkerID("symbol-question")])
        map.root.children.insert(fresh, at: 1)
        map.relationships.append(Relationship(from: fresh.id, to: id(b1)))
        return fresh
    }

    func testEditsArePatchedIntoTheOriginalXML() throws {
        let session = try MindManagerSession(data: try Self.makeMap(), password: nil)
        var map = session.snapshot
        let fresh = Self.applyEdits(&map)
        let written = try session.serialized(current: map, resources: Self.resources(of: session), preview: { Data("new-preview".utf8) })

        let reread = try MindManagerSession(data: written, password: nil)
        XCTAssertEqual(MindManagerProjection(reread.snapshot), MindManagerProjection(map))
        XCTAssertEqual(reread.snapshot.root.children.map(\.title), ["Alpha renamed", fresh.title, "Beta", "Gamma", "Floating\nsecond line"])

        let archive = try ZipArchive(data: written)
        XCTAssertNil(archive.entry(named: "bin/\(Self.id(Self.image).uuidString).bin"))
        XCTAssertNil(archive.entry(named: "PDFPreview.pdf"))
        XCTAssertEqual(try archive.contents(of: "Preview.png"), Data("new-preview".utf8))
        XCTAssertNotNil(archive.entry(named: "xsd/MindManagerApplication.xsd"))

        let doc = try MindManagerXML.parse(try XCTUnwrap(archive.contents(of: MindManagerPackage.documentEntry)))
        let index = try MindManagerXML.buildIndex(doc)
        let alpha = try XCTUnwrap(index.topics[Self.id(Self.alpha)])
        XCTAssertNotNil(alpha.ap("Color"))
        XCTAssertNotNil(alpha.ap("Offset"))
        XCTAssertEqual(alpha.ap("Text")?.ap("FontRange")?.attr("To"), "12")
        XCTAssertEqual(alpha.ap("Text")?.ap("FontRange")?.attr("Bold"), "true")
        XCTAssertEqual(alpha.ap("Task")?.attr("TaskPriority"), "urn:mindjet:Prio3")
        XCTAssertEqual(alpha.ap("Hyperlink")?.attr("Title"), "Alpha site")

        let a2 = try XCTUnwrap(index.topics[Self.id(Self.a2)])
        XCTAssertNil(a2.ap("Offset"))
        XCTAssertEqual(index.origin[Self.id(Self.a2)]?.parent, Self.id(Self.beta))
        let icons = MindManagerMarkers.icons(of: a2).compactMap { $0.attr("IconType") }
        XCTAssertEqual(Set(icons), ["urn:mindjet:FlagRed", "urn:mindjet:ArrowUp", "urn:mindjet:FlagGreen"])

        XCTAssertNil(index.topics[Self.id(Self.a1)])
        XCTAssertEqual(index.origin[Self.id(Self.floating)]?.container, "FloatingTopics")
        XCTAssertNil(index.topics[Self.id(Self.gamma)]?.ap("OneImage"))
        XCTAssertEqual(index.relationships.count, 1)
        XCTAssertEqual(index.relationships.first?.id, map.relationships.last?.id)
        XCTAssertNotNil(index.root.corChild("Custom"))
        let view = try XCTUnwrap(index.root.ap("MapViewGroup"))
        XCTAssertEqual(view.ap("Selection")?.aps("ObjectReference").compactMap { $0.attr("OIdRef") }, [Self.oid(Self.a2)])
        XCTAssertNil(view.ap("VisibleRoot"))

        let created = try XCTUnwrap(index.topics[fresh.id])
        XCTAssertEqual(index.origin[fresh.id]?.container, "SubTopics")
        let order = (created.children ?? []).compactMap { ($0 as? XMLElement)?.localName }
        XCTAssertEqual(order, ["TopicViewGroup", "Text", "NotesGroup", "IconsGroup", "Hyperlink", "Task"])
        XCTAssertEqual(MindManagerReader.title(of: created), fresh.title)

        let original = try MindManagerXML.buildIndex(try MindManagerXML.parse(Self.documentXML))
        XCTAssertEqual(index.topics[Self.id(Self.b1)]?.xmlString, original.topics[Self.id(Self.b1)]?.xmlString)
    }

    func testTopicAddedAfterFloatingTopicIsSavedBeforeIt() throws {
        let session = try MindManagerSession(data: try Self.makeMap(), password: nil)
        var map = session.snapshot
        let fresh = Topic(title: "Last")
        map.root.children.append(fresh)
        let written = try session.serialized(current: map, resources: Self.resources(of: session), preview: { nil })
        let reread = try MindManagerSession(data: written, password: nil)
        XCTAssertEqual(reread.snapshot.root.children.map(\.title), ["Alpha", "Beta", "Gamma", "Last", "Floating"])
    }

    func testDocumentOpensAndSavesMindManagerMap() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mmap")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Self.makeMap()
        try data.write(to: url)

        let doc = MindMapDocument()
        try doc.read(from: url, ofType: DocumentTypes.mindManager)
        XCTAssertEqual(doc.editor.map.root.children.map(\.title), ["Alpha", "Beta", "Gamma", "Floating"])
        XCTAssertEqual(doc.attachments.data(for: Self.id(Self.image)), Self.tinyPNG)
        XCTAssertTrue(doc.writableTypes(for: .saveOperation).contains(DocumentTypes.mindManager))
        XCTAssertEqual(try doc.fileWrapper(ofType: DocumentTypes.mindManager).regularFileContents, data)

        doc.editor.setTitle(Self.id(Self.beta), "Beta edited")
        let written = try XCTUnwrap(try doc.fileWrapper(ofType: DocumentTypes.mindManager).regularFileContents)
        let reread = try MindManagerSession(data: written, password: nil)
        XCTAssertEqual(reread.snapshot.topic(Self.id(Self.beta))?.title, "Beta edited")
        XCTAssertEqual(reread.snapshot.topic(Self.id(Self.gamma))?.image?.id, Self.id(Self.image))
        XCTAssertNotNil(try ZipArchive(data: written).entry(named: "Preview.png"))
    }

    func testNewMapIsSavedAsMindManagerMap() throws {
        let doc = MindMapDocument()
        var map = doc.editor.map
        map.root.title = "Plan\u{0}"
        var first = Topic(title: "First\nline two", note: "Note", link: "https://example.com",
                          markers: [MarkerID("priority-1"), MarkerID("flag-red")])
        let imageID = doc.attachments.add(data: Self.tinyPNG, name: "pic.png")
        first.image = TopicImage(id: imageID, name: "pic.png", width: 40, height: 30)
        let fileID = doc.attachments.add(data: Data("hello".utf8), name: "readme.txt")
        first.attachments = [Attachment(id: fileID, name: "readme.txt", size: 5)]
        first.children = [Topic(title: "Child")]
        let second = Topic(title: "Second")
        map.root.children = [first, second]
        map.relationships = [Relationship(from: first.children[0].id, to: second.id)]
        doc.editor.load(map)

        let written = try XCTUnwrap(try doc.fileWrapper(ofType: DocumentTypes.mindManager).regularFileContents)
        let reread = try MindManagerSession(data: written, password: nil)
        XCTAssertEqual(MindManagerProjection(reread.snapshot), MindManagerProjection(map))
        XCTAssertEqual(reread.snapshot.root.id, map.root.id)
        XCTAssertEqual(reread.snapshot.root.title, "Plan")
        XCTAssertEqual(reread.resources[imageID]?.data, Self.tinyPNG)
        XCTAssertEqual(reread.resources[fileID]?.data, Data("hello".utf8))
        XCTAssertNotNil(try ZipArchive(data: written).entry(named: "Preview.png"))
        let document = try MindManagerXML.parse(try XCTUnwrap(try ZipArchive(data: written).contents(of: MindManagerPackage.documentEntry)))
        XCTAssertNotNil(document.rootElement()?.attribute(forLocalName: "schemaLocation", uri: MindManagerXML.xsi))

        doc.editor.setTitle(second.id, "Second edited")
        let again = try XCTUnwrap(try doc.fileWrapper(ofType: DocumentTypes.mindManager).regularFileContents)
        XCTAssertEqual(try MindManagerSession(data: again, password: nil).snapshot.topic(second.id)?.title, "Second edited")
        XCTAssertEqual(doc.writableTypes(for: .saveAsOperation), [DocumentTypes.map, DocumentTypes.mindManager])
    }

    func testNewImageAndAttachmentAreStoredInBin() throws {
        let session = try MindManagerSession(data: try Self.makeMap(), password: nil)
        var map = session.snapshot
        let imageID = UUID(), fileID = UUID()
        let extra: [UUID: ResourceFile] = [imageID: ResourceFile(name: "pic.png", data: Self.tinyPNG),
                                           fileID: ResourceFile(name: "doc.txt", data: Data("hello".utf8))]
        _ = map.update(Self.id(Self.b1)) {
            $0.image = TopicImage(id: imageID, name: "pic.png", width: 20, height: 20)
            $0.attachments = [Attachment(id: fileID, name: "doc.txt", size: 5)]
        }
        let lookup: (UUID) -> ResourceFile? = { extra[$0] ?? session.resources[$0] }
        let written = try session.serialized(current: map, resources: lookup, preview: { nil })
        let reread = try MindManagerSession(data: written, password: nil)
        let b1 = try XCTUnwrap(reread.snapshot.topic(Self.id(Self.b1)))
        XCTAssertEqual(b1.image?.id, imageID)
        XCTAssertEqual(b1.attachments.map(\.name), ["doc.txt"])
        XCTAssertEqual(reread.resources[fileID]?.data, Data("hello".utf8))
        XCTAssertNotNil(try ZipArchive(data: written).entry(named: "bin/\(fileID.uuidString).bin"))
    }

    func testEncryptedMapRoundTrip() throws {
        let data = try Self.makeMap(password: "test-password")
        XCTAssertTrue(MindManagerPackage.needsPassword(data))
        XCTAssertThrowsError(try MindManagerSession(data: data, password: nil))
        XCTAssertThrowsError(try MindManagerSession(data: data, password: "wrong")) { error in
            guard case MindManagerError.wrongPassword = error else { return XCTFail("\(error)") }
        }
        let session = try MindManagerSession(data: data, password: "test-password")
        XCTAssertTrue(session.isEncrypted)
        XCTAssertEqual(session.resources[Self.id(Self.image)]?.data, Self.tinyPNG)
        var map = session.snapshot
        Self.applyEdits(&map)
        let written = try session.serialized(current: map, resources: Self.resources(of: session), preview: { Data("leak".utf8) })
        let archive = try ZipArchive(data: written)
        XCTAssertNil(archive.entry(named: MindManagerPackage.documentEntry))
        XCTAssertNil(archive.entry(named: "Preview.png"))
        XCTAssertTrue(MindManagerCrypto.isEncrypted(try XCTUnwrap(archive.contents(of: MindManagerPackage.encryptedDocumentEntry))))
        let reread = try MindManagerSession(data: written, password: "test-password")
        XCTAssertEqual(MindManagerProjection(reread.snapshot), MindManagerProjection(map))
    }

    func testPlainXMLMapIsReadAndWritten() throws {
        let session = try MindManagerSession(data: Self.documentXML, password: nil)
        var map = session.snapshot
        _ = map.update(Self.id(Self.alpha)) { $0.title = "Plain" }
        let written = try session.serialized(current: map, resources: Self.resources(of: session), preview: { nil })
        XCTAssertTrue(MindManagerPackage.looksLikeXML(written))
        XCTAssertEqual(try MindManagerSession(data: written, password: nil).snapshot.topic(Self.id(Self.alpha))?.title, "Plain")
    }

    func testMissingNamespaceDeclarationsAreAdded() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?><ap:Map OId="\(Self.oid(99))" xmlns:ap="\(MindManagerXML.ap)"><ap:OneTopic>\
        <ap:Topic OId="\(Self.oid(Self.root))"><ap:Text PlainText="Root" ReadOnly="false"><ap:Font/></ap:Text></ap:Topic></ap:OneTopic></ap:Map>
        """
        var archive = ZipArchive()
        try archive.set(Data(xml.utf8), for: MindManagerPackage.documentEntry)
        let session = try MindManagerSession(data: archive.serialized(), password: nil)
        var map = session.snapshot
        map.root.children = [Topic(title: "Flagged", markers: [MarkerID("flag-red")])]
        let written = try session.serialized(current: map, resources: Self.resources(of: session), preview: { nil })
        XCTAssertEqual(try MindManagerSession(data: written, password: nil).snapshot.root.children.first?.markers, [MarkerID("flag-red")])
    }

    func testBrokenCharactersAreTolerated() throws {
        var xml = Self.documentXML
        let marker = Data("PlainText=\"Gamma\"".utf8)
        let range = try XCTUnwrap(xml.range(of: marker))
        xml.replaceSubrange(range, with: Data("PlainText=\"Gam\u{10}ma \u{FF}".utf8) + Data([0xC3]) + Data("\"".utf8))
        let session = try MindManagerSession(data: xml, password: nil)
        XCTAssertTrue(session.snapshot.topic(Self.id(Self.gamma))?.title.hasPrefix("Gamma") ?? false)
    }

    // MARK: Real files

    func testRealMindManagerSamples() throws {
        let env = ProcessInfo.processInfo.environment
        guard let list = env["FREEMIND_MMAP_SAMPLES"], !list.isEmpty else { throw XCTSkip("FREEMIND_MMAP_SAMPLES not set") }
        let password = env["FREEMIND_MMAP_PASSWORD"]
        let output = env["FREEMIND_MMAP_OUT"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let files = try String(contentsOfFile: list, encoding: .utf8).split(separator: "\n").map(String.init)
            .filter { $0.lowercased().hasSuffix(".mmap") && FileManager.default.fileExists(atPath: $0) }
        var report: [String] = []
        var failures = 0
        for (n, path) in files.enumerated() {
            let label = String(format: "%03d", n)
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let encrypted = MindManagerPackage.needsPassword(data)
                if encrypted && password == nil { report.append("\(label) SKIP encrypted"); continue }
                let session = try MindManagerSession(data: data, password: encrypted ? password : nil)
                let topics = session.snapshot.root.subtreeCount
                XCTAssertEqual(try session.serialized(current: session.snapshot, resources: Self.resources(of: session), preview: { nil }), data)

                var map = session.snapshot
                let edits = Self.applyRealEdits(&map)
                let written = try session.serialized(current: map, resources: Self.resources(of: session), preview: { nil })
                let untouchedChanged = try Self.changedUntouchedTopics(base: session, written: written, map: map, edits: edits)
                if !untouchedChanged.isEmpty { failures += 1 }
                report.append("\(label) OK topics=\(topics) encrypted=\(encrypted) resources=\(session.resources.count) relationships=\(session.snapshot.relationships.count) untouchedChanged=\(untouchedChanged.count)")
                if let output {
                    let name = "\(label)-\(encrypted ? "enc" : "plain").mmap"
                    try written.write(to: output.appendingPathComponent(name))
                    try Self.outline(map.root).write(to: output.appendingPathComponent(name + ".expected"), atomically: true, encoding: .utf8)
                }
            } catch {
                failures += 1
                report.append("\(label) ERROR \(error) \((error as? LocalizedError)?.failureReason ?? "")")
            }
        }
        let text = report.joined(separator: "\n") + "\nfiles=\(files.count) failures=\(failures)\n"
        try text.write(toFile: list + ".report.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(failures, 0, text)
    }

    static func applyRealEdits(_ map: inout MindMap) -> Set<UUID> {
        var touched: Set<UUID> = [map.root.id]
        if let first = map.root.children.first {
            touched.insert(first.id)
            _ = map.update(first.id) { $0.title += " ✎"; $0.markers = MarkerCatalog.toggle(MarkerID("flag-green"), in: $0.markers) }
        }
        var leaf: (parent: UUID, child: UUID)?
        map.root.forEach { t in
            if leaf == nil, t.id != map.root.id, let c = t.children.last, c.children.isEmpty { leaf = (t.id, c.id) }
        }
        if let leaf {
            touched.insert(leaf.parent)
            map.root.mutateAll { t in if t.id == leaf.parent { t.children.removeAll { $0.id == leaf.child } } }
            map.relationships.removeAll { $0.from == leaf.child || $0.to == leaf.child }
        }
        let fresh = Topic(title: "FreeMind check", note: "Written by FreeMind\nsecond line", link: "https://example.com",
                          markers: [MarkerID("priority-2"), MarkerID("symbol-question")])
        touched.insert(fresh.id)
        map.root.children.append(fresh)
        if let target = map.root.children.dropLast().last(where: { !$0.children.isEmpty }) {
            touched.insert(target.id)
            _ = map.update(target.id) { $0.collapsed.toggle() }
        }
        return touched
    }

    static func ownXML(_ e: XMLElement) -> String {
        let copy = e.copy() as! XMLElement
        for name in MindManagerXML.topicContainers { copy.ap(name)?.detach() }
        return copy.xmlString
    }

    static func changedUntouchedTopics(base: MindManagerSession, written: Data, map: MindMap, edits: Set<UUID>) throws -> [UUID] {
        let before = try MindManagerXML.buildIndex(try MindManagerXML.parse(base.package.documentXML))
        let after = try MindManagerXML.buildIndex(try MindManagerXML.parse(MindManagerPackage(data: written, password: base.password).documentXML))
        let changedOIds = Set(before.topics.compactMap { id, e in MindManagerXML.uuid(fromOId: e.attr("OId")) == id ? nil : id })
        return map.root.flattenedIDs.filter { id in
            guard !edits.contains(id), !changedOIds.contains(id), let a = before.topics[id], let b = after.topics[id] else { return false }
            return ownXML(a) != ownXML(b)
        }
    }

    static func outline(_ root: Topic) -> String {
        var lines: [String] = []
        func walk(_ t: Topic, _ depth: Int) {
            lines.append(String(repeating: "\t", count: depth) + t.title.replacingOccurrences(of: "\n", with: " "))
            t.children.forEach { walk($0, depth + 1) }
        }
        walk(root, 0)
        return lines.joined(separator: "\n") + "\n"
    }
}

private extension Data {
    func replacingImageEntry(encrypted: Bool) -> Data {
        guard encrypted else { return self }
        let text = String(decoding: self, as: UTF8.self)
        return Data(text.replacingOccurrences(of: ".bin</cor:Uri>", with: ".bin.zencr</cor:Uri>").utf8)
    }
}
