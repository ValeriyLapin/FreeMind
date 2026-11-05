import AppKit

enum FormatLoss {
    static func features(of map: MindMap, type: String, baseline: MindMap?) -> [String] {
        let isXMind = type == DocumentTypes.xmind
        let reference = baseline ?? MindMap(root: Topic(title: ""), theme: Preferences.shared.defaultTheme)
        var base: [UUID: Topic] = [:]
        if baseline != nil { reference.root.forEach { base[$0.id] = $0 } }
        var styles = false, labels = false, markers = false, boundaries = false, attachments = false, positions = false
        map.root.forEach { t in
            let before = base[t.id]
            var style = t.style, oldStyle = before?.style ?? TopicStyle()
            style.boundary = nil
            oldStyle.boundary = nil
            if style != oldStyle { styles = true }
            if (t.style.boundary == true) != (before?.style.boundary == true) { boundaries = true }
            if t.labels != (before?.labels ?? []) { labels = true }
            if t.position != before?.position { positions = true }
            let unsupported = t.markers.filter { isXMind ? XMindMarkers.xmindID($0) == nil : !MindManagerMarkers.isPersistable($0) }
            if !unsupported.isEmpty { markers = true }
            if t.attachments.count > 1 || (!(t.link ?? "").isEmpty && !t.attachments.isEmpty) { attachments = true }
        }
        var lost: [String] = []
        if styles { lost.append(L("Topic styles")) }
        if markers { lost.append(L("Some markers")) }
        if !isXMind && labels { lost.append(L("Labels")) }
        if !isXMind && boundaries { lost.append(L("Boundaries")) }
        if isXMind && attachments { lost.append(L("More than one link or attachment on a topic")) }
        if positions { lost.append(L("Topic positions")) }
        if !isXMind && (map.structure != reference.structure || map.isBalanced != reference.isBalanced) { lost.append(L("Structure")) }
        if map.theme != reference.theme || map.spacing != reference.spacing || map.lineStyle != reference.lineStyle
            || map.topicMaxWidth != reference.topicMaxWidth {
            lost.append(L("Theme and layout"))
        }
        let oldRelationships = Dictionary(reference.relationships.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let plain = Relationship(from: UUID(), to: UUID())
        func look(_ r: Relationship) -> [String] {
            ["\(String(describing: r.control1))", "\(String(describing: r.control2))", "\(String(describing: r.labelPosition))",
             "\(String(describing: r.color))", "\(r.dashed)", "\(r.arrowStart)", "\(r.arrowEnd)"]
        }
        if map.relationships.contains(where: { look($0) != look(oldRelationships[$0.id] ?? plain) }) {
            lost.append(L("Relationship styles"))
        }
        if !isXMind && map.relationships.contains(where: { $0.title != (oldRelationships[$0.id]?.title ?? "") }) {
            lost.append(L("Relationship labels"))
        }
        return lost
    }
}

extension MindMapDocument {
    func offerNativeCopyIfNeeded(type: String) {
        let baseline = type == DocumentTypes.xmind ? xmind?.snapshot : mindManager?.snapshot
        let lost = FormatLoss.features(of: editor.map, type: type, baseline: baseline)
        guard !lost.isEmpty, let window = windowForSheet else { return }
        let format = type == DocumentTypes.xmind ? "XMind" : "MindManager"
        let alert = NSAlert()
        alert.messageText = LF("Some changes are not stored in the %@ format.", format)
        alert.informativeText = lost.map { "• " + $0 }.joined(separator: "\n") + "\n\n"
            + L("Save a copy in the FreeMind format to keep them.")
        alert.addButton(withTitle: L("Save FreeMind Copy…"))
        alert.addButton(withTitle: L("Not Now"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.saveNativeCopy(window: window)
        }
    }

    private func saveNativeCopy(window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [DocumentTypes.mapUTType]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            save(to: url, ofType: DocumentTypes.map, for: .saveToOperation) { error in
                if let error { self.presentError(error) }
            }
        }
    }
}
