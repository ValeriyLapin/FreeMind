import CryptoKit
import Foundation

enum MindManagerXML {
    static let ap = "http://schemas.mindjet.com/MindManager/Application/2003"
    static let cor = "http://schemas.mindjet.com/MindManager/Core/2003"
    static let xsi = "http://www.w3.org/2001/XMLSchema-instance"
    static let xhtml = "http://www.w3.org/1999/xhtml"
    static let clean = "0000000000000000"
    static let dirty = "0000000000000001"

    static let topicChildOrder = [
        "SubTopics", "FloatingTopics", "OneBoundary", "OneImage", "TopicViewGroup", "Text", "Color", "NotesGroup",
        "Offset", "IconsGroup", "SubTopicShape", "LabelFloatingTopicShape", "CalloutFloatingTopicShape", "TopicLayout",
        "SubTopicsShape", "SubTopicsVisibility", "Hyperlink", "Task", "Bookmark", "Comments", "SpellingOptions",
        "InkGroup", "OneInkSketch", "AttachmentGroup", "TextLabels", "BusinessDataGroup", "CustomControlStripData",
        "TopicReview", "TopicBookmark", "ModificationStamp", "CreationInfo", "LoadingState", "NamedDefaultsId",
        "HyperlinkGroup", "Formulas", "TopicFormulas", "ConditionalRules", "FilterSettings",
        "ConditionalFormattingSettingsGroup", "ImageThumbnailSize",
    ]
    static let mapChildOrder = ["OneTopic", "Relationships", "StyleGroup", "MapViewGroup", "DocumentGroup"]
    static let topicContainers = ["SubTopics", "FloatingTopics"]

    struct Origin: Equatable {
        var parent: UUID?
        var container: String
    }

    struct Index {
        var root: XMLElement
        var rootTopic: XMLElement
        var rootID: UUID
        var topics: [UUID: XMLElement] = [:]
        var origin: [UUID: Origin] = [:]
        var topicIDsByOId: [String: UUID] = [:]
        var topicIDsByElement: [ObjectIdentifier: UUID] = [:]
        var relationships: [(id: UUID, element: XMLElement)] = []

        func id(of element: XMLElement) -> UUID? {
            topicIDsByElement[ObjectIdentifier(element)]
        }
    }

    static func parse(_ data: Data) throws -> XMLDocument {
        let options: XMLNode.Options = [.nodeLoadExternalEntitiesNever, .nodePreserveWhitespace, .nodePreserveCDATA,
                                        .nodePreserveAttributeOrder, .nodePreserveNamespaceOrder, .nodePreserveEmptyElements]
        if let doc = try? XMLDocument(data: data, options: options) { return doc }
        return try XMLDocument(data: sanitized(data), options: options)
    }

    static func sanitized(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v == 0x09 || v == 0x0A || v == 0x0D || (v >= 0x20 && v != 0xFFFE && v != 0xFFFF) {
                scalars.append(scalar)
            }
        }
        return Data(String(scalars).utf8)
    }

    private static let attributeEscapes: [(Character, Character, String)] = [
        ("\n", "\u{E00A}", "&#xA;"), ("\r", "\u{E00D}", "&#xD;"), ("\t", "\u{E009}", "&#x9;"),
    ]

    static func serialize(_ doc: XMLDocument) throws -> Data {
        doc.characterEncoding = "UTF-8"
        let sentinels = Set(attributeEscapes.map(\.1))
        var escaped = false
        func walk(_ node: XMLNode) throws {
            guard let element = node as? XMLElement else { return }
            for attribute in element.attributes ?? [] {
                guard let value = attribute.stringValue else { continue }
                if value.contains(where: sentinels.contains) {
                    throw MindManagerError.verificationFailed(L("The map contains characters that cannot be saved safely."))
                }
                guard value.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == "\r\n" }) else { continue }
                var replaced = ""
                for ch in value {
                    if ch == "\r\n" {
                        replaced.append("\u{E00D}")
                        replaced.append("\u{E00A}")
                    } else if let escape = attributeEscapes.first(where: { $0.0 == ch }) {
                        replaced.append(escape.1)
                    } else {
                        replaced.append(ch)
                    }
                }
                attribute.stringValue = replaced
                escaped = true
            }
            for child in element.children ?? [] { try walk(child) }
        }
        if let root = doc.rootElement() { try walk(root) }
        var data = doc.xmlData(options: [.nodePreserveWhitespace, .nodePreserveCDATA])
        guard escaped else { return data }
        for (_, sentinel, entity) in attributeEscapes {
            data = data.replacingAll(Data(String(sentinel).utf8), with: Data(entity.utf8))
        }
        return data
    }

    static func uuid(fromOId oid: String?) -> UUID? {
        guard let oid, let data = Data(base64Encoded: oid), data.count == 16 else { return nil }
        return data.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    static func oid(_ id: UUID) -> String {
        withUnsafeBytes(of: id.uuid) { Data($0).base64EncodedString() }
    }

    static func derivedID(_ seed: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(("freemind.mmap|" + seed).utf8)))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    static func buildIndex(_ doc: XMLDocument) throws -> Index {
        guard let root = doc.rootElement(), root.localName == "Map",
              let one = root.ap("OneTopic"), let rootTopic = one.ap("Topic") else {
            throw MindManagerError.notAMap
        }
        var used = Set<UUID>()
        var ordinal = 0
        func assign(_ oid: String?, kind: String) -> UUID {
            ordinal += 1
            if let id = uuid(fromOId: oid), used.insert(id).inserted { return id }
            var id = derivedID("\(kind)|\(oid ?? "")|\(ordinal)")
            while !used.insert(id).inserted { id = derivedID(id.uuidString) }
            return id
        }
        let rootID = assign(rootTopic.attr("OId"), kind: "topic")
        var index = Index(root: root, rootTopic: rootTopic, rootID: rootID)
        func visit(_ element: XMLElement, id: UUID, parent: UUID?, container: String) {
            index.topics[id] = element
            index.topicIDsByElement[ObjectIdentifier(element)] = id
            index.origin[id] = Origin(parent: parent, container: container)
            if let oid = element.attr("OId"), index.topicIDsByOId[oid] == nil { index.topicIDsByOId[oid] = id }
            for name in topicContainers {
                for child in element.ap(name)?.aps("Topic") ?? [] {
                    visit(child, id: assign(child.attr("OId"), kind: "topic"), parent: id, container: name)
                }
            }
        }
        visit(rootTopic, id: rootID, parent: nil, container: "OneTopic")
        for rel in root.ap("Relationships")?.aps("Relationship") ?? [] {
            index.relationships.append((assign(rel.attr("OId"), kind: "relationship"), rel))
        }
        return index
    }

    static func element(_ name: String, _ attributes: [(String, String)] = []) -> XMLElement {
        let e = XMLElement(name: "ap:" + name, uri: ap)
        for (key, value) in attributes { e.setAttr(key, value) }
        return e
    }

    static func uriElement(_ uri: String) -> XMLElement {
        let e = XMLElement(name: "cor:Uri", uri: cor)
        e.addAttribute(XMLNode.attribute(withName: "xsi:nil", uri: xsi, stringValue: "false") as! XMLNode)
        e.stringValue = uri
        return e
    }

    static func number(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}

extension Data {
    func replacingAll(_ target: Data, with replacement: Data) -> Data {
        guard !target.isEmpty else { return self }
        var result = Data()
        result.reserveCapacity(count)
        var cursor = startIndex
        while let found = self[cursor...].range(of: target) {
            result.append(self[cursor..<found.lowerBound])
            result.append(replacement)
            cursor = found.upperBound
        }
        result.append(self[cursor...])
        return result
    }
}

extension XMLElement {
    func aps(_ name: String) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == name && $0.uri == MindManagerXML.ap }
    }

    func ap(_ name: String) -> XMLElement? {
        (children ?? []).lazy.compactMap { $0 as? XMLElement }.first { $0.localName == name && $0.uri == MindManagerXML.ap }
    }

    func corChild(_ name: String) -> XMLElement? {
        (children ?? []).lazy.compactMap { $0 as? XMLElement }.first { $0.localName == name && $0.uri == MindManagerXML.cor }
    }

    func attr(_ name: String) -> String? {
        attribute(forName: name)?.stringValue
    }

    func setAttr(_ name: String, _ value: String) {
        if let existing = attribute(forName: name) {
            existing.stringValue = value
        } else {
            addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
        }
    }

    func removeAttr(_ name: String) {
        removeAttribute(forName: name)
    }

    func markDirty() {
        if attribute(forName: "Dirty") != nil { setAttr("Dirty", MindManagerXML.dirty) }
    }

    func insertOrdered(_ child: XMLElement, order: [String]) {
        let rank = order.firstIndex(of: child.localName ?? "") ?? order.count
        let siblings = children ?? []
        for (i, node) in siblings.enumerated() {
            guard let e = node as? XMLElement, e.uri == MindManagerXML.ap,
                  let r = order.firstIndex(of: e.localName ?? "") else { continue }
            if r > rank {
                insertChild(child, at: i)
                return
            }
        }
        addChild(child)
    }

    func ensureAP(_ name: String, order: [String]) -> XMLElement {
        if let existing = ap(name) { return existing }
        let created = MindManagerXML.element(name)
        insertOrdered(created, order: order)
        return created
    }
}
