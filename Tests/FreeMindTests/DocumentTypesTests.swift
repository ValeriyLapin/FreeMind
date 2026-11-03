import UniformTypeIdentifiers
import XCTest
@testable import FreeMind

final class DocumentTypesTests: XCTestCase {
    func testForeignMapFilesResolveToReadableTypes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (ext, expected) in [("xmind", [DocumentTypes.xmind]), ("mmap", DocumentTypes.mindManagerTypes),
                                ("opml", [DocumentTypes.opml]), ("md", [DocumentTypes.markdown])] {
            let url = folder.appendingPathComponent("map.\(ext)")
            try Data("x".utf8).write(to: url)
            let type = try NSDocumentController.shared.typeForContents(of: url)
            XCTAssertTrue(expected.contains(type), "\(ext) resolved to \(type)")
            XCTAssertTrue(MindMapDocument.readableTypes.contains(type), ext)
        }
    }

    func testSaveAsOffersEveryEditableFormat() throws {
        let file = try XCTUnwrap(MainMenuBuilder.build().items.compactMap(\.submenu).first { $0.title == L("File") })
        let item = try XCTUnwrap(file.items.first { $0.action == #selector(NSDocument.saveAs(_:)) })
        XCTAssertEqual(item.keyEquivalent, "s")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option, .shift])
        let doc = MindMapDocument()
        XCTAssertTrue(doc.validateUserInterfaceItem(item))
        XCTAssertEqual(Set(doc.writableTypes(for: .saveAsOperation)),
                       [DocumentTypes.map, DocumentTypes.mindManager, DocumentTypes.xmind])
    }
}
