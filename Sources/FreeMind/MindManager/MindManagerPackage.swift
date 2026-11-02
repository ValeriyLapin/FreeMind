import Foundation

struct MindManagerPackage {
    enum Container {
        case zip(ZipArchive)
        case plainXML
    }

    static let documentEntry = "Document.xml"
    static let encryptedDocumentEntry = documentEntry + MindManagerCrypto.encryptedSuffix
    static let archiveScheme = "mmarch://"
    static let previewEntries = ["Preview.png", "PDFPreview.pdf"]

    let container: Container
    let documentXML: Data
    let isEncrypted: Bool
    let password: String?

    static func needsPassword(_ data: Data) -> Bool {
        guard let archive = try? ZipArchive(data: data) else { return false }
        return archive.entry(named: encryptedDocumentEntry) != nil && archive.entry(named: documentEntry) == nil
    }

    init(data: Data, password: String?) throws {
        if Self.looksLikeXML(data) {
            container = .plainXML
            documentXML = data
            isEncrypted = false
            self.password = nil
            return
        }
        let archive: ZipArchive
        do {
            archive = try ZipArchive(data: data)
        } catch {
            throw MindManagerError.notAMap
        }
        if let plain = try archive.contents(of: Self.documentEntry) {
            container = .zip(archive)
            documentXML = plain
            isEncrypted = false
            self.password = nil
        } else if let encrypted = try archive.contents(of: Self.encryptedDocumentEntry) {
            guard let password else { throw MindManagerError.passwordRequired }
            do {
                documentXML = try MindManagerCrypto.decrypt(encrypted, password: password)
            } catch MindManagerCrypto.CryptoError.wrongPassword {
                throw MindManagerError.wrongPassword
            }
            container = .zip(archive)
            isEncrypted = true
            self.password = password
        } else {
            throw MindManagerError.notAMap
        }
    }

    static func looksLikeXML(_ data: Data) -> Bool {
        let head = data.prefix(64)
        let trimmed = head.drop { $0 == 0xEF || $0 == 0xBB || $0 == 0xBF || $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
        return trimmed.first == UInt8(ascii: "<")
    }

    static func entryName(forURI uri: String) -> String? {
        guard uri.hasPrefix(archiveScheme) else { return nil }
        let path = String(uri.dropFirst(archiveScheme.count))
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return nil }
        return path
    }

    func resource(forURI uri: String) -> Data? {
        guard case .zip(let archive) = container, let name = Self.entryName(forURI: uri),
              let raw = try? archive.contents(of: name) else { return nil }
        if MindManagerCrypto.isEncrypted(raw) {
            guard let password else { return nil }
            return try? MindManagerCrypto.decrypt(raw, password: password)
        }
        return raw
    }

    func storedEntryName(forNewResource id: UUID) -> String {
        "bin/" + id.uuidString + ".bin" + (isEncrypted ? MindManagerCrypto.encryptedSuffix : "")
    }

    struct Changes {
        var documentXML: Data
        var addedResources: [String: Data] = [:]
        var removedEntries: Set<String> = []
        var floatingTopics: Set<UUID> = []
        var preview: Data?
    }

    func serialized(with changes: Changes) throws -> Data {
        guard case .zip(var archive) = container else { return changes.documentXML }
        for name in changes.removedEntries { archive.remove(name) }
        if isEncrypted {
            guard let password else { throw MindManagerError.passwordRequired }
            try archive.set(try MindManagerCrypto.encrypt(changes.documentXML, password: password),
                            for: Self.encryptedDocumentEntry)
            for (name, data) in changes.addedResources {
                try archive.set(try MindManagerCrypto.encrypt(data, password: password), for: name)
            }
            for name in Self.previewEntries { archive.remove(name) }
        } else {
            try archive.set(changes.documentXML, for: Self.documentEntry)
            for (name, data) in changes.addedResources {
                try archive.set(data, for: name)
            }
            archive.remove("PDFPreview.pdf")
            if let preview = changes.preview {
                try archive.set(preview, for: "Preview.png", compress: false)
            }
        }
        guard archive.totalSizeLimitOK else { throw MindManagerError.tooLarge }
        return archive.serialized()
    }
}

enum MindManagerError: LocalizedError {
    case notAMap, passwordRequired, wrongPassword, tooLarge, verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAMap: return L("This file does not look like a MindManager map.")
        case .passwordRequired: return L("This MindManager map is protected with a password.")
        case .wrongPassword: return L("The password is incorrect.")
        case .tooLarge: return L("The map is too large to be saved in the MindManager format.")
        case .verificationFailed: return L("The map could not be saved safely in the MindManager format.")
        }
    }

    var failureReason: String? {
        if case .verificationFailed(let detail) = self { return detail }
        return nil
    }

    var recoverySuggestion: String? {
        if case .verificationFailed = self {
            return L("The original file was left unchanged. Use File › Duplicate to keep a copy in the FreeMind format.")
        }
        return nil
    }
}
