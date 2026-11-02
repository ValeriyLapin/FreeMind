import Foundation
import zlib

struct ZipArchive {
    struct Entry {
        var name: String
        var nameBytes: [UInt8]
        var flags: UInt16
        var method: UInt16
        var modTime: UInt16
        var modDate: UInt16
        var crc32: UInt32
        var compressedSize: Int
        var uncompressedSize: Int
        var externalAttributes: UInt32
        var versionMadeBy: UInt16
        var payload: Data

        var isDirectory: Bool { name.hasSuffix("/") }

        func contents() throws -> Data {
            switch method {
            case 0:
                return payload
            case 8:
                let inflated = try ZipArchive.inflateRaw(payload, expectedSize: uncompressedSize)
                guard ZipArchive.crc32(inflated) == crc32 else { throw ZipError.corrupt }
                return inflated
            default:
                throw ZipError.unsupportedMethod
            }
        }
    }

    enum ZipError: Error {
        case notAZip, corrupt, unsupportedMethod, zip64Unsupported, compressionFailed
    }

    private(set) var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    func contents(of name: String) throws -> Data? {
        try entry(named: name)?.contents()
    }

    mutating func set(_ data: Data, for name: String, compress: Bool = true) throws {
        let entry = try Self.makeEntry(name: name, data: data, compress: compress)
        if let index = entries.firstIndex(where: { $0.name == name }) {
            var replaced = entry
            replaced.externalAttributes = entries[index].externalAttributes
            replaced.versionMadeBy = entries[index].versionMadeBy
            entries[index] = replaced
        } else {
            entries.append(entry)
        }
    }

    mutating func remove(_ name: String) {
        entries.removeAll { $0.name == name }
    }

    mutating func rename(_ oldName: String, to newName: String) {
        guard let index = entries.firstIndex(where: { $0.name == oldName }) else { return }
        entries[index].name = newName
        entries[index].nameBytes = Array(newName.utf8)
        entries[index].flags |= 0x0800
    }

    // MARK: Reading

    init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 22, bytes.starts(with: [0x50, 0x4B]) else { throw ZipError.notAZip }
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        while i >= lowest {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(Self.u16(bytes, eocd + 10))
        let directorySize = Int(Self.u32(bytes, eocd + 12))
        let directoryOffset = Int(Self.u32(bytes, eocd + 16))
        guard count != 0xFFFF, directoryOffset != 0xFFFF_FFFF else { throw ZipError.zip64Unsupported }
        guard directoryOffset + directorySize <= bytes.count else { throw ZipError.corrupt }

        var result: [Entry] = []
        var p = directoryOffset
        for _ in 0..<count {
            guard p + 46 <= bytes.count, Self.u32(bytes, p) == 0x0201_4B50 else { throw ZipError.corrupt }
            let versionMadeBy = Self.u16(bytes, p + 4)
            let flags = Self.u16(bytes, p + 8)
            let method = Self.u16(bytes, p + 10)
            let modTime = Self.u16(bytes, p + 12)
            let modDate = Self.u16(bytes, p + 14)
            let crc = Self.u32(bytes, p + 16)
            let compressed = Int(Self.u32(bytes, p + 20))
            let uncompressed = Int(Self.u32(bytes, p + 24))
            let nameLength = Int(Self.u16(bytes, p + 28))
            let extraLength = Int(Self.u16(bytes, p + 30))
            let commentLength = Int(Self.u16(bytes, p + 32))
            let external = Self.u32(bytes, p + 38)
            let localOffset = Int(Self.u32(bytes, p + 42))
            guard compressed != 0xFFFF_FFFF, uncompressed != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF else {
                throw ZipError.zip64Unsupported
            }
            guard flags & 0x0001 == 0 else { throw ZipError.unsupportedMethod }
            let nameBytes = Array(bytes[(p + 46)..<(p + 46 + nameLength)])
            guard localOffset + 30 <= bytes.count, Self.u32(bytes, localOffset) == 0x0403_4B50 else { throw ZipError.corrupt }
            let localName = Int(Self.u16(bytes, localOffset + 26))
            let localExtra = Int(Self.u16(bytes, localOffset + 28))
            let start = localOffset + 30 + localName + localExtra
            guard start + compressed <= bytes.count else { throw ZipError.corrupt }
            let name = String(decoding: nameBytes, as: UTF8.self)
            result.append(Entry(name: name, nameBytes: nameBytes, flags: flags & ~0x0008, method: method,
                                modTime: modTime, modDate: modDate, crc32: crc, compressedSize: compressed,
                                uncompressedSize: uncompressed, externalAttributes: external,
                                versionMadeBy: versionMadeBy, payload: Data(bytes[start..<(start + compressed)])))
            p += 46 + nameLength + extraLength + commentLength
        }
        entries = result
    }

    // MARK: Writing

    func serialized() -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let offset = out.count
            out.append(le32: 0x0403_4B50)
            out.append(le16: 20)
            out.append(le16: entry.flags)
            out.append(le16: entry.method)
            out.append(le16: entry.modTime)
            out.append(le16: entry.modDate)
            out.append(le32: entry.crc32)
            out.append(le32: UInt32(entry.compressedSize))
            out.append(le32: UInt32(entry.uncompressedSize))
            out.append(le16: UInt16(entry.nameBytes.count))
            out.append(le16: 0)
            out.append(contentsOf: entry.nameBytes)
            out.append(entry.payload)

            central.append(le32: 0x0201_4B50)
            central.append(le16: entry.versionMadeBy)
            central.append(le16: 20)
            central.append(le16: entry.flags)
            central.append(le16: entry.method)
            central.append(le16: entry.modTime)
            central.append(le16: entry.modDate)
            central.append(le32: entry.crc32)
            central.append(le32: UInt32(entry.compressedSize))
            central.append(le32: UInt32(entry.uncompressedSize))
            central.append(le16: UInt16(entry.nameBytes.count))
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le32: entry.externalAttributes)
            central.append(le32: UInt32(offset))
            central.append(contentsOf: entry.nameBytes)
        }
        let directoryOffset = out.count
        out.append(central)
        out.append(le32: 0x0605_4B50)
        out.append(le16: 0)
        out.append(le16: 0)
        out.append(le16: UInt16(entries.count))
        out.append(le16: UInt16(entries.count))
        out.append(le32: UInt32(central.count))
        out.append(le32: UInt32(directoryOffset))
        out.append(le16: 0)
        return out
    }

    static func makeEntry(name: String, data: Data, compress: Bool) throws -> Entry {
        let (time, date) = dosTimestamp(Date())
        var method: UInt16 = 0
        var payload = data
        if compress, !data.isEmpty {
            let deflated = try deflateRaw(data)
            if deflated.count < data.count {
                method = 8
                payload = deflated
            }
        }
        let nameBytes = Array(name.utf8)
        return Entry(name: name, nameBytes: nameBytes, flags: nameBytes.allSatisfy { $0 < 0x80 } ? 0 : 0x0800,
                     method: method, modTime: time, modDate: date, crc32: crc32(data),
                     compressedSize: payload.count, uncompressedSize: data.count, externalAttributes: 0,
                     versionMadeBy: 20, payload: payload)
    }

    var totalSizeLimitOK: Bool {
        entries.reduce(0) { $0 + $1.payload.count + $1.nameBytes.count + 76 } < Int(UInt32.max) && entries.count < 0xFFFF
    }

    // MARK: Helpers

    static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw -> UInt32 in
            guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            var crc: uLong = zlib.crc32(0, nil, 0)
            var offset = 0
            while offset < raw.count {
                let chunk = min(raw.count - offset, Int(UInt32.max))
                crc = zlib.crc32(crc, base + offset, uInt(chunk))
                offset += chunk
            }
            return UInt32(truncatingIfNeeded: crc)
        }
    }

    static func deflateRaw(_ data: Data) throws -> Data {
        try runDeflate(data, windowBits: -MAX_WBITS)
    }

    static func inflateRaw(_ data: Data, expectedSize: Int) throws -> Data {
        try runInflate(data, windowBits: -MAX_WBITS, expectedSize: expectedSize)
    }

    static func zlibCompress(_ data: Data) throws -> Data {
        try runDeflate(data, windowBits: MAX_WBITS)
    }

    static func zlibDecompress(_ data: Data, expectedSize: Int) throws -> Data {
        try runInflate(data, windowBits: MAX_WBITS, expectedSize: expectedSize)
    }

    private static func runDeflate(_ data: Data, windowBits: Int32) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY,
                            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ZipError.compressionFailed
        }
        defer { deflateEnd(&stream) }
        var input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(input.count))) + 64)
        let status: Int32 = input.withUnsafeMutableBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                stream.next_in = inBuf.baseAddress
                stream.avail_in = uInt(inBuf.count)
                stream.next_out = outBuf.baseAddress
                stream.avail_out = uInt(outBuf.count)
                return deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw ZipError.compressionFailed }
        return Data(output.prefix(Int(stream.total_out)))
    }

    private static func runInflate(_ data: Data, windowBits: Int32, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ZipError.corrupt
        }
        defer { inflateEnd(&stream) }
        var input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: max(expectedSize, 1))
        let status: Int32 = input.withUnsafeMutableBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                stream.next_in = inBuf.baseAddress
                stream.avail_in = uInt(inBuf.count)
                stream.next_out = outBuf.baseAddress
                stream.avail_out = uInt(outBuf.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, Int(stream.total_out) == expectedSize else { throw ZipError.corrupt }
        return Data(output.prefix(expectedSize))
    }

    private static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let date = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, date)
    }

    static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}

extension Data {
    mutating func append(le16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func append(le32 value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }
}
