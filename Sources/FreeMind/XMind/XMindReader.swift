import AppKit
import CryptoKit

enum XMindError: LocalizedError {
    case notAWorkbook
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAWorkbook: L("This file does not look like an XMind workbook.")
        case .verificationFailed(let detail): detail
        }
    }
}

struct XMindOrigin {
    var parent: UUID?
    var kind: String
}

struct XMindIndex {
    var topics: [UUID: [String: Any]] = [:]
    var origin: [UUID: XMindOrigin] = [:]
    var byXMindID: [String: UUID] = [:]
    var relationships: [UUID: [String: Any]] = [:]
    var otherRelationships: [[String: Any]] = []

    var kinds: [UUID: String] { origin.mapValues(\.kind) }
}

struct XMindReadResult {
    var map: MindMap
    var resources: [UUID: ResourceFile]
    var index: XMindIndex
}

enum XMindReader {
    static let contentEntry = "content.json"
    static let manifestEntry = "manifest.json"
    static let metadataEntry = "metadata.json"
    static let thumbnailEntry = "Thumbnails/thumbnail.png"
    static let childKinds = ["attached", "callout", "summary", "detached"]

    static func sheets(in archive: ZipArchive) throws -> [[String: Any]] {
        guard let data = try? archive.contents(of: contentEntry),
              let sheets = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              sheets.first?["rootTopic"] is [String: Any] else { throw XMindError.notAWorkbook }
        return sheets
    }

    static func preferredID(_ xmindID: String, kind: String) -> UUID {
        UUID(uuidString: xmindID) ?? derivedID("\(kind)|\(xmindID)")
    }

    static func derivedID(_ seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("freemind.xmind|" + seed).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    static func resourcePath(_ reference: String) -> String? {
        guard reference.hasPrefix("xap:") else { return nil }
        let path = String(reference.dropFirst(4))
        return path.removingPercentEncoding ?? path
    }

    static func resourceID(_ path: String, topic: UUID, role: String) -> UUID {
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return UUID(uuidString: stem) ?? derivedID("resource|\(role)|\(topic.uuidString)|\(path)")
    }

    static func normalizedNote(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func title(of dict: [String: Any]) -> String {
        if let title = dict["title"] as? String { return title }
        let pieces = (dict["attributedTitle"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
        return pieces.joined()
    }

    static func boundaryFlags(_ ranges: [String], attachedCount: Int) -> (master: Bool, children: Set<Int>) {
        var master = false
        var children = Set<Int>()
        for range in ranges {
            if range == "master" {
                master = true
                continue
            }
            let bounds = range.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
                .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard bounds.count == 2, attachedCount > 0 else { continue }
            let lower = max(0, min(bounds[0], bounds[1]))
            let upper = min(attachedCount - 1, max(bounds[0], bounds[1]))
            guard lower <= upper else { continue }
            children.formUnion(lower...upper)
        }
        return (master, children)
    }

    static func read(sheet: [String: Any], archive: ZipArchive) -> XMindReadResult {
        var index = XMindIndex()
        var resources: [UUID: ResourceFile] = [:]
        var used = Set<UUID>()
        var ordinal = 0

        func assign(_ xmindID: String?, kind: String) -> UUID {
            if let xmindID, !xmindID.isEmpty {
                let id = preferredID(xmindID, kind: kind)
                if used.insert(id).inserted { return id }
            }
            ordinal += 1
            var id = derivedID("\(kind)#\(ordinal)|\(xmindID ?? "")")
            while !used.insert(id).inserted { id = derivedID(id.uuidString) }
            return id
        }

        func file(_ path: String) -> Data? {
            (try? archive.contents(of: path)) ?? nil
        }

        func topic(_ dict: [String: Any], parent: UUID?, kind: String) -> Topic {
            let xmindID = dict["id"] as? String
            let id = assign(xmindID, kind: "topic")
            if let xmindID, index.byXMindID[xmindID] == nil { index.byXMindID[xmindID] = id }
            index.topics[id] = dict
            index.origin[id] = XMindOrigin(parent: parent, kind: kind)
            var t = Topic(id: id, title: title(of: dict))
            if let notes = dict["notes"] as? [String: Any], let plain = notes["plain"] as? [String: Any],
               let content = plain["content"] as? String {
                t.note = normalizedNote(content)
            }
            if let href = dict["href"] as? String {
                if let path = resourcePath(href) {
                    if let data = file(path) {
                        let rid = resourceID(path, topic: id, role: "href")
                        let name = (dict["title"] as? String).flatMap { $0.contains(".") ? $0 : nil }
                            ?? (path as NSString).lastPathComponent
                        resources[rid] = ResourceFile(name: name, data: data)
                        t.attachments = [Attachment(id: rid, name: AttachmentStore.sanitize(name), size: Int64(data.count))]
                    }
                } else if !href.hasPrefix("xmind:") {
                    t.link = href
                }
            }
            if let labels = dict["labels"] as? [String] { t.labels = labels }
            if let markers = dict["markers"] as? [[String: Any]] {
                t.markers = XMindImporter.convertMarkers(markers.compactMap { $0["markerId"] as? String })
            }
            if parent != nil, (dict["branch"] as? String) == "folded" { t.collapsed = true }
            if let image = dict["image"] as? [String: Any], let src = image["src"] as? String,
               let path = resourcePath(src), let data = file(path), let picture = NSImage(data: data) {
                let rid = resourceID(path, topic: id, role: "image")
                let name = (path as NSString).lastPathComponent
                resources[rid] = ResourceFile(name: name, data: data)
                var width = image["width"] as? Double, height = image["height"] as? Double
                if width == nil || height == nil {
                    let w = Double(picture.size.width), h = Double(picture.size.height)
                    let scale = min(1, 300 / max(w, h, 1))
                    width = (w * scale).rounded()
                    height = (h * scale).rounded()
                }
                t.image = TopicImage(id: rid, name: name, width: max(width ?? 1, 1), height: max(height ?? 1, 1))
            }
            if let children = dict["children"] as? [String: Any] {
                for childKind in childKinds where parent == nil || childKind != "detached" {
                    for child in (children[childKind] as? [[String: Any]]) ?? [] {
                        t.children.append(topic(child, parent: id, kind: childKind))
                    }
                }
            }
            let attachedCount = t.children.filter { index.origin[$0.id]?.kind == "attached" }.count
            let flags = boundaryFlags(((dict["boundaries"] as? [[String: Any]]) ?? []).compactMap { $0["range"] as? String },
                                      attachedCount: attachedCount)
            if flags.master { t.style.boundary = true }
            for i in flags.children { t.children[i].style.boundary = true }
            return t
        }

        let rootDict = sheet["rootTopic"] as? [String: Any] ?? [:]
        let root = topic(rootDict, parent: nil, kind: "root")
        var map = MindMap(root: root, structure: XMindImporter.structure(from: rootDict["structureClass"] as? String),
                          theme: Preferences.shared.defaultTheme)
        for rel in (sheet["relationships"] as? [[String: Any]]) ?? [] {
            let rid = assign(rel["id"] as? String, kind: "relationship")
            guard let a = (rel["end1Id"] as? String).flatMap({ index.byXMindID[$0] }),
                  let b = (rel["end2Id"] as? String).flatMap({ index.byXMindID[$0] }), a != b else {
                index.otherRelationships.append(rel)
                continue
            }
            index.relationships[rid] = rel
            map.relationships.append(Relationship(id: rid, from: a, to: b, title: (rel["title"] as? String) ?? ""))
        }
        return XMindReadResult(map: map, resources: resources, index: index)
    }
}
