import AppKit

enum MindManagerMarkers {
    static let iconPrefix = "urn:mindjet:"
    static let priorityPrefix = "urn:mindjet:Prio"

    static let iconToMarker: [String: String] = [
        "FlagRed": "flag-red", "FlagOrange": "flag-orange", "FlagYellow": "flag-yellow", "FlagGreen": "flag-green",
        "FlagBlue": "flag-blue", "FlagPurple": "flag-purple", "FlagBlack": "flag-gray",
        "QuestionMark": "symbol-question", "ExclamationMark": "symbol-important", "Emergency": "symbol-important",
        "Lightbulb": "symbol-idea", "Check": "symbol-check", "Cross": "symbol-cross", "NoEntry": "symbol-cross",
        "ThumbsUp": "symbol-like", "ThumbsDown": "symbol-dislike", "Dollar": "symbol-money",
        "Clock": "symbol-time", "Time": "symbol-time",
    ]

    static let markerToIcon: [String: String] = [
        "flag-red": "FlagRed", "flag-orange": "FlagOrange", "flag-yellow": "FlagYellow", "flag-green": "FlagGreen",
        "flag-blue": "FlagBlue", "flag-purple": "FlagPurple", "flag-gray": "FlagBlack",
        "symbol-question": "QuestionMark", "symbol-important": "ExclamationMark", "symbol-idea": "Lightbulb",
        "symbol-check": "Check", "symbol-cross": "Cross", "symbol-like": "ThumbsUp", "symbol-dislike": "ThumbsDown",
        "symbol-money": "Dollar", "symbol-time": "Clock",
    ]

    static let progressValues = [0, 25, 50, 75, 100]

    static func marker(forIconType type: String?) -> MarkerID? {
        guard let type, type.hasPrefix(iconPrefix) else { return nil }
        return iconToMarker[String(type.dropFirst(iconPrefix.count))].map { MarkerID($0) }
    }

    static func priority(from value: String?) -> MarkerID? {
        guard let value, value.hasPrefix(priorityPrefix), let n = Int(value.dropFirst(priorityPrefix.count)), n >= 1 else {
            return nil
        }
        return MarkerID("priority-\(min(n, 6))")
    }

    static func progress(from value: String?) -> MarkerID? {
        guard let value, let n = Double(value) else { return nil }
        let rounded = Int(n.rounded())
        return progressValues.contains(rounded) ? MarkerID("task-\(rounded)") : nil
    }

    static func icons(of topic: XMLElement) -> [XMLElement] {
        topic.ap("IconsGroup")?.ap("Icons")?.aps("Icon") ?? []
    }

    static func markers(of topic: XMLElement) -> [MarkerID] {
        var result: [MarkerID] = []
        if let task = topic.ap("Task") {
            if let p = priority(from: task.attr("TaskPriority")) { result.append(p) }
            if let p = progress(from: task.attr("TaskPercentage")) { result.append(p) }
        }
        for icon in icons(of: topic) {
            if let m = marker(forIconType: icon.attr("IconType")), !result.contains(m) { result.append(m) }
        }
        return result.sorted()
    }

    static func isPersistable(_ marker: MarkerID) -> Bool {
        switch marker.group {
        case .priority, .task: return true
        default: return markerToIcon[marker.rawValue] != nil
        }
    }
}

struct MindManagerReadResult {
    var map: MindMap
    var resources: [UUID: ResourceFile]
}

enum MindManagerReader {
    static let maxImageSide = 300.0

    static func read(_ package: MindManagerPackage) throws -> MindManagerReadResult {
        let doc = try MindManagerXML.parse(package.documentXML)
        let index = try MindManagerXML.buildIndex(doc)
        var resources: [UUID: ResourceFile] = [:]

        func build(_ id: UUID) -> Topic {
            let element = index.topics[id]!
            var topic = Topic(id: id, title: title(of: element))
            topic.collapsed = collapsed(element)
            topic.note = note(of: element)
            topic.link = link(of: element)
            topic.markers = MindManagerMarkers.markers(of: element)
            if let (image, file) = image(of: element, topicID: id, package: package), resources[image.id] == nil {
                topic.image = image
                resources[image.id] = file
            }
            for (attachment, file) in attachments(of: element, topicID: id, package: package) where resources[attachment.id] == nil {
                topic.attachments.append(attachment)
                resources[attachment.id] = file
            }
            topic.children = MindManagerXML.topicContainers.flatMap { name in
                (element.ap(name)?.aps("Topic") ?? []).compactMap(index.id(of:))
            }.map(build)
            return topic
        }

        var map = MindMap(root: build(index.rootID), structure: .mindMap, theme: Preferences.shared.defaultTheme)
        map.root.collapsed = false
        let known = Set(map.root.flattenedIDs)
        for (id, element) in index.relationships {
            guard let (from, to) = ends(of: element, index: index), from != to, known.contains(from), known.contains(to) else {
                continue
            }
            map.relationships.append(Relationship(id: id, from: from, to: to, title: relationshipTitle(element)))
        }
        return MindManagerReadResult(map: map, resources: resources)
    }

    static func title(of topic: XMLElement) -> String {
        normalizedNewlines(topic.ap("Text")?.attr("PlainText") ?? "")
    }

    static func collapsed(_ topic: XMLElement) -> Bool {
        topic.aps("TopicViewGroup").first?.ap("Collapsed")?.attr("Collapsed") == "true"
    }

    static func link(of topic: XMLElement) -> String? {
        guard let url = topic.ap("Hyperlink")?.attr("Url"), !url.isEmpty, !url.hasPrefix("#") else { return nil }
        return url
    }

    static func note(of topic: XMLElement) -> String {
        guard let data = topic.ap("NotesGroup")?.ap("NotesXhtmlData") else { return "" }
        let html = (data.children ?? []).compactMap { $0 as? XMLElement }
        let text = html.isEmpty ? (data.attr("PreviewPlainText") ?? "") : html.map(xhtmlText).joined(separator: "\n")
        return normalizedNote(text)
    }

    static func normalizedNote(_ text: String) -> String {
        normalizedNewlines(text).split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingTrailingWhitespace() }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let blockElements: Set<String> = ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "pre", "blockquote"]

    static func xhtmlText(_ node: XMLNode) -> String {
        guard let element = node as? XMLElement else { return node.stringValue ?? "" }
        let name = (element.localName ?? "").lowercased()
        if name == "br" { return "\n" }
        let inner = (element.children ?? []).map(xhtmlText).joined()
        if blockElements.contains(name) || name == "ol" || name == "ul" || name == "table" || name == "body" || name == "html" {
            let trimmed = inner.hasSuffix("\n") ? String(inner.dropLast()) : inner
            return trimmed + "\n"
        }
        return inner
    }

    static func normalizedNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func resourceID(_ oid: String?, topicID: UUID, kind: String, ordinal: Int) -> UUID {
        MindManagerXML.uuid(fromOId: oid) ?? MindManagerXML.derivedID("\(kind)|\(topicID.uuidString)|\(ordinal)")
    }

    static func image(of topic: XMLElement, topicID: UUID, package: MindManagerPackage) -> (TopicImage, ResourceFile)? {
        guard let image = topic.ap("OneImage")?.ap("Image"),
              let uri = image.ap("ImageData")?.corChild("Uri")?.stringValue,
              let data = package.resource(forURI: uri), let picture = NSImage(data: data) else { return nil }
        let size = image.ap("ImageSize")
        var w = size?.attr("Width").flatMap(Double.init) ?? Double(picture.size.width)
        var h = size?.attr("Height").flatMap(Double.init) ?? Double(picture.size.height)
        let longest = max(w, h, 1)
        if longest > maxImageSide { w = w * maxImageSide / longest; h = h * maxImageSide / longest }
        let id = resourceID(image.attr("OId"), topicID: topicID, kind: "image", ordinal: 0)
        let name = "image." + imageExtension(data)
        return (TopicImage(id: id, name: name, width: max(w, 1), height: max(h, 1)), ResourceFile(name: name, data: data))
    }

    static func imageExtension(_ data: Data) -> String {
        let head = [UInt8](data.prefix(4))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if head.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "bin"
    }

    static func attachmentID(_ item: XMLElement, topicID: UUID, ordinal: Int) -> UUID {
        resourceID(item.attr("AttachmentId"), topicID: topicID, kind: "attachment", ordinal: ordinal)
    }

    static func attachments(of topic: XMLElement, topicID: UUID, package: MindManagerPackage) -> [(Attachment, ResourceFile)] {
        var result: [(Attachment, ResourceFile)] = []
        for (n, item) in (topic.ap("AttachmentGroup")?.aps("AttachmentData") ?? []).enumerated() {
            guard let uri = item.corChild("Uri")?.stringValue, let data = package.resource(forURI: uri) else { continue }
            let name = AttachmentStore.sanitize(item.attr("FileName") ?? "attachment")
            let attachment = Attachment(id: attachmentID(item, topicID: topicID, ordinal: n), name: name, size: Int64(data.count))
            result.append((attachment, ResourceFile(name: name, data: data)))
        }
        return result
    }

    static func ends(of relationship: XMLElement, index: MindManagerXML.Index) -> (UUID, UUID)? {
        let groups = relationship.aps("ConnectionGroup")
        func end(_ i: Int) -> UUID? {
            let group = groups.first { $0.attr("Index") == "\(i)" } ?? (groups.count > i ? groups[i] : nil)
            let ref = group?.ap("Connection")?.corChild("ObjectReference")?.attr("OIdRef")
            return ref.flatMap { index.topicIDsByOId[$0] }
        }
        guard let a = end(0), let b = end(1) else { return nil }
        return (a, b)
    }

    static func relationshipTitle(_ relationship: XMLElement) -> String {
        relationship.ap("FloatingTopics")?.ap("Topic").map(title) ?? ""
    }
}

extension Topic {
    var flattenedIDs: [UUID] {
        var ids: [UUID] = []
        forEach { ids.append($0.id) }
        return ids
    }
}

extension StringProtocol {
    func trimmingTrailingWhitespace() -> String {
        var s = String(self)
        while let last = s.unicodeScalars.last, CharacterSet.whitespaces.contains(last) { s.unicodeScalars.removeLast() }
        return s
    }
}
