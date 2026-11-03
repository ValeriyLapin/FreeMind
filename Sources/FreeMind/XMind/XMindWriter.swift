import Foundation

enum XMindMarkers {
    static func xmindID(_ marker: MarkerID) -> String? {
        let raw = marker.rawValue
        if raw.hasPrefix("priority-") || raw.hasPrefix("flag-") || raw.hasPrefix("star-") {
            return marker.group.map { MarkerCatalog.markers(in: $0).contains(marker) } == true ? raw : nil
        }
        let table: [String: String] = [
            "task-0": "task-start", "task-25": "task-quarter", "task-50": "task-half", "task-75": "task-3quar",
            "task-100": "task-done", "symbol-question": "symbol-question", "symbol-important": "symbol-exclam",
            "symbol-idea": "symbol-idea", "symbol-check": "symbol-right", "symbol-cross": "symbol-wrong",
            "symbol-heart": "c_symbol_heart", "symbol-like": "c_symbol_like", "symbol-dislike": "c_symbol_dislike",
            "symbol-pin": "symbol-pin", "symbol-time": "c_symbol_hourglass", "symbol-person": "people-green",
            "symbol-money": "c_symbol_money",
        ]
        return table[raw]
    }
}

enum XMindStructure {
    static func className(_ structure: MapStructure) -> String {
        switch structure {
        case .mindMap: "org.xmind.ui.map.unbalanced"
        case .logicRight: "org.xmind.ui.logic.right"
        case .logicLeft: "org.xmind.ui.logic.left"
        case .orgChart: "org.xmind.ui.org-chart.down"
        case .tree: "org.xmind.ui.tree.right"
        case .process: "org.xmind.ui.timeline.horizontal"
        }
    }
}

struct XMindProjection: Equatable {
    struct Node: Equatable {
        var id: UUID
        var title: String
        var collapsed: Bool
        var note: String
        var link: String
        var markers: [MarkerID]
        var labels: [String]
        var image: String?
        var attachments: [UUID]
        var boundary: Bool
        var children: [Node]
    }

    struct Link: Equatable {
        var id: UUID
        var from: UUID
        var to: UUID
        var title: String
    }

    var structure: MapStructure
    var root: Node
    var relationships: [Link]

    static func rank(_ kind: String?) -> Int {
        XMindReader.childKinds.firstIndex(of: kind ?? "attached") ?? 0
    }

    static func ordered(_ children: [Topic], kinds: [UUID: String]) -> [Topic] {
        children.enumerated().sorted { a, b in
            let ra = rank(kinds[a.element.id]), rb = rank(kinds[b.element.id])
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
    }

    static func attachmentIDs(_ t: Topic) -> [UUID] {
        guard (t.link ?? "").isEmpty, let first = t.attachments.first else { return [] }
        return [first.id]
    }

    init(_ map: MindMap, kinds: [UUID: String]) {
        func node(_ t: Topic, isRoot: Bool) -> Node {
            Node(id: t.id, title: t.title, collapsed: !isRoot && t.collapsed, note: XMindReader.normalizedNote(t.note),
                 link: t.link ?? "", markers: t.markers.filter { XMindMarkers.xmindID($0) != nil }.sorted(),
                 labels: t.labels,
                 image: t.image.map { "\($0.id.uuidString) \(String(format: "%.2f %.2f", $0.width, $0.height))" },
                 attachments: Self.attachmentIDs(t), boundary: t.style.boundary == true,
                 children: Self.ordered(t.children, kinds: kinds).map { node($0, isRoot: false) })
        }
        structure = map.structure
        root = node(map.root, isRoot: true)
        let ids = Set(map.root.flattenedIDs)
        relationships = map.relationships
            .filter { ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to }
            .map { Link(id: $0.id, from: $0.from, to: $0.to, title: $0.title) }
    }

    func firstDifference(from other: XMindProjection) -> String? {
        func compare(_ a: Node, _ b: Node) -> String? {
            let place = "topic \(a.id.uuidString)"
            if a.id != b.id { return "\(place): id \(b.id.uuidString)" }
            if a.title != b.title { return "\(place): title" }
            if a.collapsed != b.collapsed { return "\(place): collapsed" }
            if a.note != b.note { return "\(place): note" }
            if a.link != b.link { return "\(place): link" }
            if a.markers != b.markers { return "\(place): markers \(a.markers.map(\.rawValue)) vs \(b.markers.map(\.rawValue))" }
            if a.labels != b.labels { return "\(place): labels" }
            if a.image != b.image { return "\(place): image \(a.image ?? "-") vs \(b.image ?? "-")" }
            if a.attachments != b.attachments { return "\(place): attachments" }
            if a.boundary != b.boundary { return "\(place): boundary" }
            if a.children.map(\.id) != b.children.map(\.id) { return "\(place): children order or set" }
            for (x, y) in zip(a.children, b.children) {
                if let d = compare(x, y) { return d }
            }
            return nil
        }
        if structure != other.structure { return "structure" }
        if let d = compare(root, other.root) { return d }
        return relationships == other.relationships ? nil : "relationships \(relationships.count) vs \(other.relationships.count)"
    }
}

struct XMindPatch {
    var sheet: [String: Any]
    var files: [String: Data]
    var kinds: [UUID: String]
}

enum XMindWriter {
    static func newID() -> String { UUID().uuidString.lowercased() }

    static func patch(sheet original: [String: Any], index: XMindIndex, snapshot: MindMap, current: MindMap,
                      resources: (UUID) -> ResourceFile?) -> XMindPatch {
        var old: [UUID: Topic] = [:]
        snapshot.root.forEach { old[$0.id] = $0 }
        var written: [UUID: String] = [:]
        var files: [String: Data] = [:]
        var kinds: [UUID: String] = [:]

        func store(_ id: UUID, name: String) -> String? {
            guard let file = resources(id) else { return nil }
            let ext = (name as NSString).pathExtension.isEmpty ? (file.name as NSString).pathExtension : (name as NSString).pathExtension
            let path = "resources/\(id.uuidString.lowercased())" + (ext.isEmpty ? "" : ".\(ext.lowercased())")
            files[path] = file.data
            return path
        }

        func write(_ t: Topic, parent: UUID?, covered: Bool) -> [String: Any] {
            var dict = index.topics[t.id] ?? ["class": "topic"]
            let before = old[t.id]
            if (dict["id"] as? String).map({ XMindReader.preferredID($0, kind: "topic") }) != t.id {
                dict["id"] = t.id.uuidString.lowercased()
            }
            written[t.id] = dict["id"] as? String
            if before?.title != t.title {
                dict["title"] = t.title
                dict["attributedTitle"] = nil
                dict["titleUnedited"] = nil
            }
            if before?.note != t.note {
                let note = XMindReader.normalizedNote(t.note)
                if note.isEmpty {
                    dict["notes"] = nil
                } else {
                    let html = note.components(separatedBy: "\n")
                        .map { $0.isEmpty ? "<div><br></div>" : "<div>\(escapeHTML($0))</div>" }.joined()
                    dict["notes"] = ["plain": ["content": note], "realHTML": ["content": html]]
                }
            }
            if before?.link != t.link || before?.attachments.map(\.id) != t.attachments.map(\.id) {
                if let link = t.link, !link.isEmpty {
                    dict["href"] = link
                } else if let first = t.attachments.first {
                    if before?.attachments.first?.id != first.id || !(before?.link ?? "").isEmpty || dict["href"] == nil {
                        dict["href"] = store(first.id, name: first.name).map { "xap:" + $0 }
                    }
                } else {
                    dict["href"] = nil
                }
            }
            if before?.markers != t.markers {
                let kept = ((dict["markers"] as? [[String: Any]]) ?? []).filter {
                    XMindImporter.convertMarkers([($0["markerId"] as? String) ?? ""]).isEmpty
                }
                let all = kept + t.markers.compactMap(XMindMarkers.xmindID).map { ["markerId": $0] as [String: Any] }
                dict["markers"] = all.isEmpty ? nil : all
            }
            if before?.labels != t.labels { dict["labels"] = t.labels.isEmpty ? nil : t.labels }
            if parent != nil, (before?.collapsed ?? false) != t.collapsed { dict["branch"] = t.collapsed ? "folded" : nil }
            if before?.image != t.image {
                if let image = t.image {
                    var entry = (before?.image?.id == image.id ? dict["image"] as? [String: Any] : nil) ?? [:]
                    if entry["src"] == nil { entry["src"] = store(image.id, name: image.name).map { "xap:" + $0 } }
                    entry["width"] = image.width
                    entry["height"] = image.height
                    dict["image"] = entry
                } else {
                    dict["image"] = nil
                }
            }

            var childKinds: [UUID: String] = [:]
            for child in t.children {
                let origin = index.origin[child.id]
                childKinds[child.id] = origin?.parent == t.id && origin?.parent != nil ? origin!.kind : "attached"
            }
            var summaries = (dict["summaries"] as? [[String: Any]]) ?? []
            let attachedBefore = childKinds.values.filter { $0 == "attached" }.count
            var validSummaries = Set<UUID>()
            for entry in summaries {
                if attachedBefore > 0, let topicID = (entry["topicId"] as? String).flatMap({ index.byXMindID[$0] }),
                   childKinds[topicID] == "summary" {
                    validSummaries.insert(topicID)
                }
            }
            for (id, kind) in childKinds where kind == "summary" && !validSummaries.contains(id) { childKinds[id] = "attached" }
            kinds.merge(childKinds) { $1 }
            let ordered = XMindProjection.ordered(t.children, kinds: childKinds)
            let attached = ordered.filter { childKinds[$0.id] == "attached" }

            var boundaries = (dict["boundaries"] as? [[String: Any]]) ?? []
            let desired = Set(attached.indices.filter { attached[$0].style.boundary == true })
            if XMindReader.boundaryFlags(boundaries.compactMap { $0["range"] as? String }, attachedCount: attached.count).children != desired {
                var byRange: [String: [String: Any]] = [:]
                for b in boundaries { if let r = b["range"] as? String, byRange[r] == nil { byRange[r] = b } }
                boundaries = boundaries.filter { ($0["range"] as? String) == "master" } + desired.sorted().map { i in
                    let range = "(\(i),\(i))"
                    var b = byRange[range] ?? ["id": newID()]
                    b["range"] = range
                    return b
                }
            }
            let ownBoundary = t.style.boundary == true
            let hasMaster = boundaries.contains { ($0["range"] as? String) == "master" }
            if ownBoundary && !covered && !hasMaster { boundaries.append(["id": newID(), "range": "master"]) }
            if !ownBoundary && hasMaster { boundaries.removeAll { ($0["range"] as? String) == "master" } }
            dict["boundaries"] = boundaries.isEmpty ? nil : boundaries
            let finalCovered = XMindReader.boundaryFlags(boundaries.compactMap { $0["range"] as? String },
                                                         attachedCount: attached.count).children

            var groups: [String: [[String: Any]]] = [:]
            var attachedIndex = 0
            for child in ordered {
                let kind = childKinds[child.id] ?? "attached"
                let isCovered = kind == "attached" && finalCovered.contains(attachedIndex)
                if kind == "attached" { attachedIndex += 1 }
                groups[kind, default: []].append(write(child, parent: t.id, covered: isCovered))
            }
            var children = (dict["children"] as? [String: Any]) ?? [:]
            for kind in XMindReader.childKinds { children[kind] = groups[kind] }
            dict["children"] = children.isEmpty ? nil : children

            if !summaries.isEmpty {
                summaries = summaries.compactMap { entry in
                    guard let id = (entry["topicId"] as? String).flatMap({ index.byXMindID[$0] }),
                          validSummaries.contains(id), let target = written[id] else { return nil }
                    var entry = entry
                    entry["topicId"] = target
                    let bounds = ((entry["range"] as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "() "))
                        .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    let last = attached.count - 1
                    let lower = min(max(bounds.first ?? 0, 0), last), upper = min(max(bounds.last ?? last, lower), last)
                    entry["range"] = "(\(lower),\(upper))"
                    return entry
                }
                dict["summaries"] = summaries.isEmpty ? nil : summaries
            }
            return dict
        }

        var sheet = original
        var root = write(current.root, parent: nil, covered: false)
        if snapshot.structure != current.structure {
            let name = XMindStructure.className(current.structure)
            root["structureClass"] = name
            if var extensions = sheet["extensions"] as? [[String: Any]] {
                for i in extensions.indices where (extensions[i]["provider"] as? String) == "org.xmind.ui.skeleton.structure.style" {
                    var content = (extensions[i]["content"] as? [String: Any]) ?? [:]
                    content["centralTopic"] = name
                    extensions[i]["content"] = content
                }
                sheet["extensions"] = extensions
            }
        }
        sheet["rootTopic"] = root

        let oldRelationships = Dictionary(snapshot.relationships.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var relationships: [[String: Any]] = []
        for r in current.relationships where r.from != r.to {
            guard let end1 = written[r.from], let end2 = written[r.to] else { continue }
            var dict = index.relationships[r.id] ?? [:]
            if (dict["id"] as? String).map({ XMindReader.preferredID($0, kind: "relationship") }) != r.id {
                dict["id"] = r.id.uuidString.lowercased()
            }
            dict["end1Id"] = end1
            dict["end2Id"] = end2
            if oldRelationships[r.id]?.title != r.title { dict["title"] = r.title.isEmpty ? nil : r.title }
            relationships.append(dict)
        }
        relationships += index.otherRelationships
        sheet["relationships"] = relationships.isEmpty ? nil : relationships
        return XMindPatch(sheet: sheet, files: files, kinds: kinds)
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
