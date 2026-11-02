import AppKit

struct MindManagerProjection: Equatable {
    struct Node: Equatable {
        var id: UUID
        var title: String
        var collapsed: Bool
        var note: String
        var link: String
        var markers: [MarkerID]
        var image: String?
        var attachments: [String]
        var children: [Node]
    }

    struct Link: Equatable {
        var id: UUID
        var from: UUID
        var to: UUID
    }

    var root: Node
    var relationships: [Link]

    func firstDifference(from other: MindManagerProjection) -> String? {
        func compare(_ a: Node, _ b: Node) -> String? {
            let where_ = "topic \(a.id.uuidString)"
            if a.id != b.id { return "\(where_): id \(b.id.uuidString)" }
            if a.title != b.title { return "\(where_): title" }
            if a.collapsed != b.collapsed { return "\(where_): collapsed \(a.collapsed) vs \(b.collapsed)" }
            if a.note != b.note { return "\(where_): note" }
            if a.link != b.link { return "\(where_): link" }
            if a.markers != b.markers { return "\(where_): markers \(a.markers.map(\.rawValue)) vs \(b.markers.map(\.rawValue))" }
            if a.image != b.image { return "\(where_): image \(a.image ?? "-") vs \(b.image ?? "-")" }
            if a.attachments != b.attachments { return "\(where_): attachments" }
            if a.children.map(\.id) != b.children.map(\.id) { return "\(where_): children order or set" }
            for (x, y) in zip(a.children, b.children) {
                if let d = compare(x, y) { return d }
            }
            return nil
        }
        if let d = compare(root, other.root) { return d }
        return relationships == other.relationships ? nil : "relationships \(relationships.count) vs \(other.relationships.count)"
    }

    init(_ map: MindMap, floating: Set<UUID> = []) {
        func node(_ t: Topic) -> Node {
            Node(id: t.id, title: MindManagerReader.normalizedNewlines(t.title), collapsed: t.collapsed && !t.children.isEmpty,
                 note: MindManagerReader.normalizedNote(t.note), link: t.link ?? "",
                 markers: t.markers.filter(MindManagerMarkers.isPersistable).sorted(),
                 image: t.image.map { "\($0.id.uuidString) \(MindManagerXML.number($0.width)) \(MindManagerXML.number($0.height))" },
                 attachments: t.attachments.map { "\($0.id.uuidString) \($0.name)" },
                 children: (t.children.filter { !floating.contains($0.id) } + t.children.filter { floating.contains($0.id) })
                    .map(node))
        }
        root = node(map.root)
        root.collapsed = false
        let ids = Set(map.root.flattenedIDs)
        relationships = map.relationships
            .filter { ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to }
            .map { Link(id: $0.id, from: $0.from, to: $0.to) }
    }
}

enum MindManagerWriter {
    static func patch(base: Data, snapshot: MindMap, current: MindMap, package: MindManagerPackage,
                      resources: (UUID) -> ResourceFile?) throws -> MindManagerPackage.Changes {
        let doc = try MindManagerXML.parse(base)
        let index = try MindManagerXML.buildIndex(doc)
        guard index.rootID == current.root.id else {
            throw MindManagerError.verificationFailed(L("The central topic does not match the original map."))
        }
        let oldTopics = topicsByID(snapshot.root)
        let referencedBefore = archiveURIs(in: index.root)
        var added: [String: Data] = [:]
        var floating = Set<UUID>()

        func process(_ topic: Topic, _ element: XMLElement) throws {
            if MindManagerXML.uuid(fromOId: element.attr("OId")) != topic.id {
                element.setAttr("OId", MindManagerXML.oid(topic.id))
            }
            try patchFields(element, current: topic, old: oldTopics[topic.id], package: package, resources: resources, added: &added)
            for name in MindManagerXML.topicContainers {
                guard let container = element.ap(name) else { continue }
                for child in container.aps("Topic") { child.detach() }
            }
            for child in topic.children {
                let childElement: XMLElement
                if let existing = index.topics[child.id] {
                    existing.detach()
                    childElement = existing
                } else {
                    childElement = newTopicElement(child)
                }
                let origin = index.origin[child.id]
                if origin != nil, origin?.parent != topic.id {
                    childElement.ap("Offset")?.detach()
                }
                let containerName = origin?.parent == topic.id ? (origin?.container ?? "SubTopics") : "SubTopics"
                if containerName == "FloatingTopics" { floating.insert(child.id) }
                element.ensureAP(containerName, order: MindManagerXML.topicChildOrder).addChild(childElement)
                try process(child, childElement)
            }
            for name in MindManagerXML.topicContainers {
                if let container = element.ap(name), container.aps("Topic").isEmpty { container.detach() }
            }
        }
        try process(current.root, index.rootTopic)
        patchRelationships(index: index, snapshot: snapshot, current: current)
        dropViewReferences(to: Set(index.topics.keys).subtracting(current.root.flattenedIDs), index: index)

        let referencedAfter = archiveURIs(in: index.root)
        let removed = referencedBefore.subtracting(referencedAfter)
            .compactMap(MindManagerPackage.entryName(forURI:))
            .filter { $0.hasPrefix("bin/") }
        return MindManagerPackage.Changes(documentXML: try MindManagerXML.serialize(doc), addedResources: added,
                                          removedEntries: Set(removed), floatingTopics: floating)
    }

    static func dropViewReferences(to removed: Set<UUID>, index: MindManagerXML.Index) {
        guard !removed.isEmpty else { return }
        func isRemoved(_ reference: XMLElement?) -> Bool {
            guard let ref = reference?.attr("OIdRef"), let id = index.topicIDsByOId[ref] else { return false }
            return removed.contains(id)
        }
        for group in index.root.aps("MapViewGroup") {
            for reference in group.ap("Selection")?.children?.compactMap({ $0 as? XMLElement }) ?? []
            where reference.localName == "ObjectReference" && isRemoved(reference) {
                reference.detach()
            }
            if let visibleRoot = group.ap("VisibleRoot"),
               isRemoved(visibleRoot.children?.compactMap({ $0 as? XMLElement }).first { $0.localName == "ObjectReference" }) {
                visibleRoot.detach()
            }
        }
    }

    static func topicsByID(_ root: Topic) -> [UUID: Topic] {
        var result: [UUID: Topic] = [:]
        root.forEach { result[$0.id] = $0 }
        return result
    }

    static func archiveURIs(in root: XMLElement) -> Set<String> {
        var result = Set<String>()
        func walk(_ node: XMLNode) {
            if let e = node as? XMLElement, e.localName == "Uri", e.uri == MindManagerXML.cor, let value = e.stringValue {
                result.insert(value)
            }
            for child in node.children ?? [] { walk(child) }
        }
        walk(root)
        return result
    }

    static func newTopicElement(_ topic: Topic) -> XMLElement {
        let e = MindManagerXML.element("Topic", [("Dirty", MindManagerXML.dirty), ("OId", MindManagerXML.oid(topic.id)),
                                                  ("Gen", MindManagerXML.clean)])
        let view = MindManagerXML.element("TopicViewGroup", [("ViewIndex", "0")])
        view.addChild(MindManagerXML.element("Collapsed", [("Dirty", MindManagerXML.dirty), ("Collapsed", "false")]))
        e.addChild(view)
        let text = MindManagerXML.element("Text", [("Dirty", MindManagerXML.dirty), ("PlainText", ""), ("ReadOnly", "false")])
        text.addChild(MindManagerXML.element("Font"))
        e.addChild(text)
        return e
    }

    // MARK: Fields

    static func patchFields(_ e: XMLElement, current t: Topic, old: Topic?, package: MindManagerPackage,
                            resources: (UUID) -> ResourceFile?, added: inout [String: Data]) throws {
        if old == nil || MindManagerReader.normalizedNewlines(old!.title) != MindManagerReader.normalizedNewlines(t.title) {
            setTitle(e, t.title)
        }
        let wantCollapsed = t.collapsed && !t.children.isEmpty
        let hadCollapsed = old.map { $0.collapsed && !$0.children.isEmpty } ?? false
        if hadCollapsed != wantCollapsed {
            setCollapsed(e, wantCollapsed)
        }
        if MindManagerReader.normalizedNote(old?.note ?? "") != MindManagerReader.normalizedNote(t.note) {
            setNote(e, t.note)
        }
        if (old?.link ?? "") != (t.link ?? "") {
            setLink(e, t.link ?? "")
        }
        let oldMarkers = (old?.markers ?? []).filter(MindManagerMarkers.isPersistable)
        let newMarkers = t.markers.filter(MindManagerMarkers.isPersistable)
        if Set(oldMarkers) != Set(newMarkers) {
            setMarkers(e, old: Set(oldMarkers), new: Set(newMarkers))
        }
        if old?.image != t.image {
            try setImage(e, old: old?.image, new: t.image, package: package, resources: resources, added: &added)
        }
        if (old?.attachments ?? []).map(\.id) != t.attachments.map(\.id) || (old?.attachments ?? []).map(\.name) != t.attachments.map(\.name) {
            setAttachments(e, topicID: t.id, t.attachments, package: package, resources: resources, added: &added)
        }
    }

    static func setTitle(_ e: XMLElement, _ title: String) {
        let text = MindManagerReader.normalizedNewlines(title)
        let node = e.ensureAP("Text", order: MindManagerXML.topicChildOrder)
        if node.attr("ReadOnly") == nil { node.setAttr("ReadOnly", "false") }
        node.setAttr("PlainText", text)
        node.markDirty()
        if node.ap("Font") == nil { node.insertChild(MindManagerXML.element("Font"), at: 0) }
        let ranges = node.aps("FontRange")
        let length = text.utf16.count
        if length == 0 {
            ranges.forEach { $0.detach() }
        } else if let first = ranges.first {
            first.setAttr("From", "0")
            first.setAttr("To", "\(length - 1)")
            ranges.dropFirst().forEach { $0.detach() }
        }
    }

    static func setCollapsed(_ e: XMLElement, _ collapsed: Bool) {
        let view = e.aps("TopicViewGroup").first ?? {
            let created = MindManagerXML.element("TopicViewGroup", [("ViewIndex", "0")])
            e.insertOrdered(created, order: MindManagerXML.topicChildOrder)
            return created
        }()
        let flag = view.ap("Collapsed") ?? {
            let created = MindManagerXML.element("Collapsed", [("Dirty", MindManagerXML.dirty)])
            view.insertChild(created, at: 0)
            return created
        }()
        flag.setAttr("Collapsed", collapsed ? "true" : "false")
        flag.markDirty()
    }

    static func setNote(_ e: XMLElement, _ note: String) {
        e.ap("NotesGroup")?.detach()
        let text = MindManagerReader.normalizedNote(note)
        guard !text.isEmpty else { return }
        let group = MindManagerXML.element("NotesGroup")
        let data = MindManagerXML.element("NotesXhtmlData", [("Dirty", MindManagerXML.dirty), ("PreviewPlainText", text)])
        let html = XMLElement(name: "html", uri: MindManagerXML.xhtml)
        html.addNamespace(XMLNode.namespace(withName: "", stringValue: MindManagerXML.xhtml) as! XMLNode)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let p = XMLElement(name: "p", uri: MindManagerXML.xhtml)
            p.stringValue = String(line)
            html.addChild(p)
        }
        data.addChild(html)
        group.addChild(data)
        e.insertOrdered(group, order: MindManagerXML.topicChildOrder)
    }

    static func setLink(_ e: XMLElement, _ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            e.ap("Hyperlink")?.detach()
            return
        }
        if let link = e.ap("Hyperlink") {
            for name in ["Name", "CachedName", "Title", "TitleAutoCreated", "CachedDocumentExtension"] { link.removeAttr(name) }
            link.setAttr("Url", trimmed)
            link.markDirty()
        } else {
            let link = MindManagerXML.element("Hyperlink", [("Dirty", MindManagerXML.dirty), ("Url", trimmed),
                                                            ("Absolute", "false")])
            e.insertOrdered(link, order: MindManagerXML.topicChildOrder)
        }
    }

    static func setMarkers(_ e: XMLElement, old: Set<MarkerID>, new: Set<MarkerID>) {
        let oldPriority = old.first { $0.group == .priority }, newPriority = new.first { $0.group == .priority }
        let oldProgress = old.first { $0.group == .task }, newProgress = new.first { $0.group == .task }
        if oldPriority != newPriority || oldProgress != newProgress {
            let task = e.ap("Task")
            if oldPriority != newPriority {
                if let p = newPriority {
                    let t = task ?? e.ensureAP("Task", order: MindManagerXML.topicChildOrder)
                    t.setAttr("TaskPriority", MindManagerMarkers.priorityPrefix + p.suffix)
                    t.markDirty()
                } else {
                    task?.removeAttr("TaskPriority")
                }
            }
            if oldProgress != newProgress {
                if let p = newProgress {
                    let t = e.ap("Task") ?? e.ensureAP("Task", order: MindManagerXML.topicChildOrder)
                    t.setAttr("TaskPercentage", p.suffix)
                    t.markDirty()
                } else {
                    task?.removeAttr("TaskPercentage")
                }
            }
            if let t = e.ap("Task"), t.attributes?.allSatisfy({ $0.name == "Dirty" }) ?? true, (t.children ?? []).isEmpty {
                t.detach()
            }
        }

        let oldIcons = old.filter { $0.group != .priority && $0.group != .task }
        let newIcons = new.filter { $0.group != .priority && $0.group != .task }
        guard oldIcons != newIcons else { return }
        let group = e.ap("IconsGroup") ?? {
            let created = MindManagerXML.element("IconsGroup")
            e.insertOrdered(created, order: MindManagerXML.topicChildOrder)
            return created
        }()
        let icons = group.ap("Icons") ?? {
            let created = MindManagerXML.element("Icons", [("Dirty", MindManagerXML.dirty)])
            group.insertChild(created, at: 0)
            return created
        }()
        var present = Set<MarkerID>()
        for icon in icons.aps("Icon") {
            guard let marker = MindManagerMarkers.marker(forIconType: icon.attr("IconType")) else { continue }
            if newIcons.contains(marker), !present.contains(marker) {
                present.insert(marker)
            } else {
                icon.detach()
            }
        }
        for marker in newIcons.sorted() where !present.contains(marker) {
            guard let type = MindManagerMarkers.markerToIcon[marker.rawValue] else { continue }
            let icon = MindManagerXML.element("Icon", [("IconType", MindManagerMarkers.iconPrefix + type)])
            icon.addAttribute(XMLNode.attribute(withName: "xsi:type", uri: MindManagerXML.xsi, stringValue: "ap:StockIcon") as! XMLNode)
            icons.addChild(icon)
        }
        icons.markDirty()
        if icons.aps("Icon").isEmpty, icons.attributes?.allSatisfy({ $0.name == "Dirty" }) ?? true {
            icons.detach()
            if (group.children ?? []).compactMap({ $0 as? XMLElement }).isEmpty { group.detach() }
        }
    }

    static func setImage(_ e: XMLElement, old: TopicImage?, new: TopicImage?, package: MindManagerPackage,
                         resources: (UUID) -> ResourceFile?, added: inout [String: Data]) throws {
        if let old, let new, old.id == new.id, let image = e.ap("OneImage")?.ap("Image") {
            let size = image.ap("ImageSize") ?? {
                let created = MindManagerXML.element("ImageSize", [("Dirty", MindManagerXML.dirty)])
                image.insertOrdered(created, order: ["ImageViewGroup", "ImageData", "ImageSize", "AlternateImageData", "Thumbnail"])
                return created
            }()
            size.setAttr("Width", MindManagerXML.number(new.width))
            size.setAttr("Height", MindManagerXML.number(new.height))
            size.markDirty()
            return
        }
        e.ap("OneImage")?.detach()
        guard let new else { return }
        guard let file = resources(new.id), let png = pngData(file.data) else {
            throw MindManagerError.verificationFailed(L("A topic image could not be stored in the MindManager format."))
        }
        let entry = package.storedEntryName(forNewResource: new.id)
        added[entry] = png
        let one = MindManagerXML.element("OneImage")
        let image = MindManagerXML.element("Image", [("Dirty", MindManagerXML.dirty), ("OId", MindManagerXML.oid(new.id)),
                                                     ("Gen", MindManagerXML.clean)])
        let data = MindManagerXML.element("ImageData", [("Dirty", MindManagerXML.dirty), ("ImageType", "urn:mindjet:PngImage")])
        data.addChild(MindManagerXML.uriElement(MindManagerPackage.archiveScheme + entry))
        image.addChild(data)
        image.addChild(MindManagerXML.element("ImageSize", [("Dirty", MindManagerXML.dirty),
                                                            ("Width", MindManagerXML.number(new.width)),
                                                            ("Height", MindManagerXML.number(new.height))]))
        one.addChild(image)
        e.insertOrdered(one, order: MindManagerXML.topicChildOrder)
    }

    static func pngData(_ data: Data) -> Data? {
        if MindManagerReader.imageExtension(data) == "png" { return data }
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func setAttachments(_ e: XMLElement, topicID: UUID, _ attachments: [Attachment], package: MindManagerPackage,
                               resources: (UUID) -> ResourceFile?, added: inout [String: Data]) {
        let group = e.ap("AttachmentGroup")
        var existing: [UUID: XMLElement] = [:]
        for (n, item) in (group?.aps("AttachmentData") ?? []).enumerated() {
            existing[MindManagerReader.attachmentID(item, topicID: topicID, ordinal: n)] = item
            item.detach()
        }
        guard !attachments.isEmpty else {
            group?.detach()
            return
        }
        let target = group ?? {
            let created = MindManagerXML.element("AttachmentGroup")
            e.insertOrdered(created, order: MindManagerXML.topicChildOrder)
            return created
        }()
        let stamp = ISO8601DateFormatter.mindManager.string(from: Date())
        var index = 0
        for attachment in attachments {
            let item: XMLElement
            if let kept = existing[attachment.id] {
                item = kept
                if item.attr("FileName") != attachment.name {
                    item.setAttr("FileName", attachment.name)
                    item.markDirty()
                }
            } else {
                guard let file = resources(attachment.id) else { continue }
                let entry = package.storedEntryName(forNewResource: attachment.id)
                added[entry] = file.data
                item = MindManagerXML.element("AttachmentData", [
                    ("Index", "0"), ("AttachmentId", MindManagerXML.oid(attachment.id)), ("Dirty", MindManagerXML.dirty),
                    ("Type", "urn:mindjet:File"), ("FileName", attachment.name),
                    ("FileSize", MindManagerXML.number(Double(file.data.count))),
                    ("FileCreated", stamp), ("FileModified", stamp),
                ])
                item.addChild(MindManagerXML.uriElement(MindManagerPackage.archiveScheme + entry))
            }
            item.setAttr("Index", "\(index)")
            index += 1
            target.insertOrdered(item, order: ["AttachmentData", "AttachmentsPermissions"])
        }
        if target.aps("AttachmentData").isEmpty { target.detach() }
    }

    // MARK: Relationships

    static func patchRelationships(index: MindManagerXML.Index, snapshot: MindMap, current: MindMap) {
        let ids = Set(current.root.flattenedIDs)
        let wanted = current.relationships.filter { ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to }
        let wantedByID = Dictionary(wanted.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oldByID = Dictionary(snapshot.relationships.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var kept = Set<UUID>()
        for (id, element) in index.relationships {
            guard let rel = wantedByID[id] else {
                let wasImported = oldByID[id] != nil
                let ends = MindManagerReader.ends(of: element, index: index)
                let endsGone = ends.map { !ids.contains($0.0) || !ids.contains($0.1) } ?? false
                if wasImported || endsGone { element.detach() }
                continue
            }
            kept.insert(id)
            if let old = oldByID[id], old.from == rel.from, old.to == rel.to { continue }
            setEnds(element, from: rel.from, to: rel.to, index: index)
        }
        let fresh = wanted.filter { !kept.contains($0.id) }
        guard !fresh.isEmpty else {
            if let container = index.root.ap("Relationships"), container.aps("Relationship").isEmpty { container.detach() }
            return
        }
        let container = index.root.ensureAP("Relationships", order: MindManagerXML.mapChildOrder)
        for rel in fresh {
            let element = MindManagerXML.element("Relationship", [("Dirty", MindManagerXML.dirty),
                                                                  ("OId", MindManagerXML.oid(rel.id)), ("Gen", MindManagerXML.clean)])
            for n in 0..<2 {
                let group = MindManagerXML.element("ConnectionGroup", [("Index", "\(n)")])
                let connection = MindManagerXML.element("Connection", [("Dirty", MindManagerXML.dirty)])
                let ref = XMLElement(name: "cor:ObjectReference", uri: MindManagerXML.cor)
                connection.addChild(ref)
                group.addChild(connection)
                element.addChild(group)
            }
            element.addChild(MindManagerXML.element("RelationshipViewGroup", [("ViewIndex", "0")]))
            element.addChild(MindManagerXML.element("AutoRoute", [("Dirty", MindManagerXML.dirty), ("AutoRouting", "true")]))
            setEnds(element, from: rel.from, to: rel.to, index: index)
            container.addChild(element)
        }
        if container.aps("Relationship").isEmpty { container.detach() }
    }

    static func setEnds(_ element: XMLElement, from: UUID, to: UUID, index: MindManagerXML.Index) {
        let groups = element.aps("ConnectionGroup")
        for (n, id) in [from, to].enumerated() where n < groups.count {
            let group = groups.first { $0.attr("Index") == "\(n)" } ?? groups[n]
            guard let ref = group.ap("Connection")?.corChild("ObjectReference") else { continue }
            let oid = index.topics[id]?.attr("OId") ?? MindManagerXML.oid(id)
            ref.removeAttr("OIdRef")
            ref.setAttr("OIdRef", oid)
        }
    }
}

extension ISO8601DateFormatter {
    static let mindManager: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        f.timeZone = .current
        return f
    }()
}
