import AppKit

final class MindManagerSession {
    let originalData: Data
    let package: MindManagerPackage
    let snapshot: MindMap
    let resources: [UUID: ResourceFile]

    var password: String? { package.password }
    var isEncrypted: Bool { package.isEncrypted }

    init(data: Data, password: String?) throws {
        originalData = data
        package = try MindManagerPackage(data: data, password: password)
        let result = try MindManagerReader.read(package)
        snapshot = result.map
        resources = result.resources
    }

    static func blank(rootID: UUID) throws -> MindManagerSession {
        let primitive = "http://schemas.mindjet.com/MindManager/Primitive/2003"
        let delta = "http://schemas.mindjet.com/MindManager/Delta/2003"
        let schemaLocation = [MindManagerXML.ap, MindManagerXML.cor, delta, primitive].map { "\($0) \($0)" }.joined(separator: " ")
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <ap:Map Dirty="\(MindManagerXML.dirty)" OId="\(MindManagerXML.oid(UUID()))" Gen="\(MindManagerXML.clean)" \
        xmlns:ap="\(MindManagerXML.ap)" xmlns:cor="\(MindManagerXML.cor)" xmlns:pri="\(primitive)" xmlns:xsi="\(MindManagerXML.xsi)" \
        xsi:schemaLocation="\(schemaLocation)">\
        <ap:OneTopic><ap:Topic OId="\(MindManagerXML.oid(rootID))"><ap:Text PlainText="" ReadOnly="false"><ap:Font/></ap:Text>\
        </ap:Topic></ap:OneTopic></ap:Map>
        """
        var archive = ZipArchive()
        try archive.set(Data(xml.utf8), for: MindManagerPackage.documentEntry)
        return try MindManagerSession(data: archive.serialized(), password: nil)
    }

    static func open(data: Data, fileName: String, knownPassword: String?) throws -> MindManagerSession {
        guard MindManagerPackage.needsPassword(data) else { return try MindManagerSession(data: data, password: nil) }
        var password = knownPassword
        var retry = false
        while true {
            if password == nil {
                password = MindManagerPasswordPrompt.ask(fileName: fileName, retry: retry)
                guard password != nil else { throw CocoaError(.userCancelled) }
            }
            do {
                return try MindManagerSession(data: data, password: password)
            } catch MindManagerError.wrongPassword {
                password = nil
                retry = true
            }
        }
    }

    func serialized(current: MindMap, resources: (UUID) -> ResourceFile?, preview: () -> Data?) throws -> Data {
        if MindManagerProjection(current) == MindManagerProjection(snapshot) { return originalData }
        var changes = try MindManagerWriter.patch(base: package.documentXML, snapshot: snapshot, current: current,
                                                  package: package, resources: resources)
        if !package.isEncrypted { changes.preview = preview() }
        let data = try package.serialized(with: changes)
        try verify(data, expected: current, floating: changes.floatingTopics)
        return data
    }

    func verify(_ data: Data, expected: MindMap, floating: Set<UUID>) throws {
        let reread: MindManagerReadResult
        do {
            reread = try MindManagerReader.read(try MindManagerPackage(data: data, password: package.password))
        } catch {
            throw MindManagerError.verificationFailed(L("The written file could not be read back."))
        }
        let written = MindManagerProjection(reread.map), wanted = MindManagerProjection(expected, floating: floating)
        guard written == wanted else {
            let detail = wanted.firstDifference(from: written) ?? ""
            throw MindManagerError.verificationFailed(L("The written file does not match the map.") + " " + detail)
        }
    }
}

enum MindManagerPasswordPrompt {
    static func ask(fileName: String, retry: Bool) -> String? {
        let work = { () -> String? in
            let alert = NSAlert()
            alert.messageText = LF("“%@” is protected with a password.", fileName)
            alert.informativeText = retry ? L("The password is incorrect. Try again.")
                : L("Enter the password to open this MindManager map.")
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            alert.accessoryView = field
            alert.addButton(withTitle: L("Open"))
            alert.addButton(withTitle: L("Cancel"))
            alert.window.initialFirstResponder = field
            return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
        }
        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }
}
