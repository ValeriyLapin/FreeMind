import Foundation

final class XMindSession {
    let originalData: Data
    let archive: ZipArchive
    let sheets: [[String: Any]]
    let snapshot: MindMap
    let resources: [UUID: ResourceFile]
    let index: XMindIndex

    init(data: Data) throws {
        originalData = data
        guard let archive = try? ZipArchive(data: data) else { throw XMindError.notAWorkbook }
        self.archive = archive
        sheets = try XMindReader.sheets(in: archive)
        let result = XMindReader.read(sheet: sheets[0], archive: archive)
        snapshot = result.map
        resources = result.resources
        index = result.index
    }

    static func canEdit(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let archive = try? ZipArchive(data: data),
              let sheets = try? XMindReader.sheets(in: archive) else { return false }
        return sheets.count == 1
    }

    static func blank(rootID: UUID, sheetTitle: String) throws -> XMindSession {
        let sheet: [String: Any] = [
            "id": XMindWriter.newID(), "class": "sheet", "title": sheetTitle,
            "rootTopic": ["id": rootID.uuidString.lowercased(), "class": "topic", "title": "",
                          "structureClass": XMindStructure.className(.mindMap, balanced: true)] as [String: Any],
        ]
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let metadata: [String: Any] = ["dataStructureVersion": "3", "creator": ["name": "FreeMind", "version": version]]
        let manifest: [String: Any] = ["file-entries": [XMindReader.contentEntry: [String: Any](),
                                                        XMindReader.metadataEntry: [String: Any]()]]
        var archive = ZipArchive()
        try archive.set(json([sheet]), for: XMindReader.contentEntry, compress: false)
        try archive.set(json(metadata), for: XMindReader.metadataEntry, compress: false)
        try archive.set(json(manifest), for: XMindReader.manifestEntry, compress: false)
        return try XMindSession(data: archive.serialized())
    }

    static func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    func serialized(current: MindMap, resources: (UUID) -> ResourceFile?, preview: () -> Data?) throws -> Data {
        if XMindProjection(current, kinds: index.kinds) == XMindProjection(snapshot, kinds: index.kinds) { return originalData }
        let patch = XMindWriter.patch(sheet: sheets[0], index: index, snapshot: snapshot, current: current, resources: resources)
        var out = archive
        var newSheets = sheets
        newSheets[0] = patch.sheet
        try out.set(Self.json(newSheets), for: XMindReader.contentEntry, compress: false)
        for (path, data) in patch.files.sorted(by: { $0.key < $1.key }) where out.entry(named: path) == nil {
            try out.set(data, for: path, compress: false)
        }
        if let data = try? out.contents(of: XMindReader.manifestEntry),
           var manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            var entries = (manifest["file-entries"] as? [String: Any]) ?? [:]
            for path in patch.files.keys where entries[path] == nil { entries[path] = [String: Any]() }
            manifest["file-entries"] = entries
            try out.set(Self.json(manifest), for: XMindReader.manifestEntry, compress: false)
        }
        if let png = preview() { try out.set(png, for: XMindReader.thumbnailEntry, compress: false) }
        let data = out.serialized()
        try verify(data, expected: current, kinds: patch.kinds)
        return data
    }

    func verify(_ data: Data, expected: MindMap, kinds: [UUID: String]) throws {
        let reread: XMindSession
        do {
            reread = try XMindSession(data: data)
        } catch {
            throw XMindError.verificationFailed(L("The written file could not be read back."))
        }
        let written = XMindProjection(reread.snapshot, kinds: reread.index.kinds)
        let wanted = XMindProjection(expected, kinds: kinds)
        guard written == wanted else {
            let detail = wanted.firstDifference(from: written) ?? ""
            throw XMindError.verificationFailed(L("The written file does not match the map.") + " " + detail)
        }
    }
}
