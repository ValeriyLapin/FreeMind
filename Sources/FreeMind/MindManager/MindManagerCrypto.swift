import CommonCrypto
import Foundation
import Security

enum MindManagerCrypto {
    enum CryptoError: Error {
        case notEncrypted, wrongPassword, corrupt, unsupportedPassword, failed
    }

    static let encryptedMagic = Array("MJETENCR".utf8)
    static let rawMagic = Array("MJETRAWD".utf8)
    static let compressedMagic: [UInt8] = [0x4D, 0x4A, 0x5A, 0x00]
    static let encryptedSuffix = ".zencr"

    private static let headerSize = 40
    private static let ivOffset = 32
    private static let blockSize = 8

    static func isEncrypted(_ data: Data) -> Bool {
        data.count >= headerSize && Array(data.prefix(8)) == encryptedMagic
    }

    static func isPasswordSupported(_ password: String) -> Bool {
        let length = password.utf8.count
        return length > 0 && length <= kCCKeySizeMaxBlowfish
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        let bytes = [UInt8](data)
        guard isEncrypted(data) else { throw CryptoError.notEncrypted }
        let iv = Int(ZipArchive.u32(bytes, 8))
        let start = Int(ZipArchive.u32(bytes, 12))
        let cipherLength = Int(ZipArchive.u32(bytes, 20))
        let plainLength = Int(ZipArchive.u32(bytes, 24))
        let payloadOffset = Int(ZipArchive.u32(bytes, 28))
        guard iv + blockSize <= bytes.count, start + cipherLength <= bytes.count, cipherLength % blockSize == 0,
              cipherLength >= blockSize, payloadOffset + plainLength <= cipherLength else { throw CryptoError.corrupt }
        guard isPasswordSupported(password) else { throw CryptoError.wrongPassword }
        let key = blowfishKey(password)
        let ivBytes = Array(bytes[iv..<(iv + blockSize)])
        let firstBlock = try blowfish(CCOperation(kCCDecrypt), Array(bytes[start..<(start + blockSize)]), key: key, iv: ivBytes)
        guard firstBlock == rawMagic else { throw CryptoError.wrongPassword }
        let plain = try blowfish(CCOperation(kCCDecrypt), Array(bytes[start..<(start + cipherLength)]), key: key, iv: ivBytes)
        return try decompress(Data(plain[payloadOffset..<(payloadOffset + plainLength)]))
    }

    static func encrypt(_ data: Data, password: String) throws -> Data {
        guard isPasswordSupported(password) else { throw CryptoError.unsupportedPassword }
        let packed = try compress(data)
        var plain = rawMagic + [UInt8](packed)
        let padding = blockSize - plain.count % blockSize
        plain += [UInt8](repeating: UInt8(padding), count: padding)
        var iv = [UInt8](repeating: 0, count: blockSize)
        guard SecRandomCopyBytes(kSecRandomDefault, blockSize, &iv) == errSecSuccess else { throw CryptoError.failed }
        let cipher = try blowfish(CCOperation(kCCEncrypt), plain, key: blowfishKey(password), iv: iv)
        var out = Data(encryptedMagic)
        for value in [UInt32(ivOffset), UInt32(headerSize), UInt32(blockSize), UInt32(cipher.count),
                      UInt32(packed.count), UInt32(rawMagic.count)] {
            out.append(le32: value)
        }
        out.append(contentsOf: iv)
        out.append(contentsOf: cipher)
        return out
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 16, Array(bytes.prefix(4)) == compressedMagic else { throw CryptoError.corrupt }
        let header = Int(ZipArchive.u32(bytes, 4))
        let compressed = Int(ZipArchive.u32(bytes, 8))
        let original = Int(ZipArchive.u32(bytes, 12))
        guard header >= 16, header + compressed <= bytes.count else { throw CryptoError.corrupt }
        return try ZipArchive.zlibDecompress(Data(bytes[header..<(header + compressed)]), expectedSize: original)
    }

    static func compress(_ data: Data) throws -> Data {
        let packed = try ZipArchive.zlibCompress(data)
        var out = Data(compressedMagic)
        out.append(le32: 16)
        out.append(le32: UInt32(packed.count))
        out.append(le32: UInt32(data.count))
        out.append(packed)
        return out
    }

    private static func blowfishKey(_ password: String) -> [UInt8] {
        let base = Array(password.utf8)
        var key = base
        while key.count < kCCKeySizeMinBlowfish { key += base }
        return key
    }

    private static func blowfish(_ operation: CCOperation, _ input: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        var swappedInput = input
        var swappedIV = iv
        swapWords(&swappedInput)
        swapWords(&swappedIV)
        var output = [UInt8](repeating: 0, count: input.count)
        var moved = 0
        let status = CCCrypt(operation, CCAlgorithm(kCCAlgorithmBlowfish), 0, key, key.count, swappedIV,
                             swappedInput, swappedInput.count, &output, output.count, &moved)
        guard status == kCCSuccess, moved == input.count else { throw CryptoError.failed }
        swapWords(&output)
        return output
    }

    private static func swapWords(_ bytes: inout [UInt8]) {
        var i = 0
        while i + 4 <= bytes.count {
            bytes.swapAt(i, i + 3)
            bytes.swapAt(i + 1, i + 2)
            i += 4
        }
    }
}
