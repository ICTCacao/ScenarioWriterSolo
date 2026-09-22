import Foundation

/// 無圧縮（stored）ZIP の書き出し。docx 用途に十分な最小実装（CacaoTrans と同じもの）。
public struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var entries = 0

    public init() {}

    public mutating func add(path: String, data: Data) {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(data)
        let offset = UInt32(body.count)
        let (dosTime, dosDate) = ZipWriter.dosDateTime()

        var local = Data()
        local.append(le32(0x04034b50))
        local.append(le16(20))
        local.append(le16(0x0800))        // UTF-8 names
        local.append(le16(0))             // stored
        local.append(le16(dosTime))
        local.append(le16(dosDate))
        local.append(le32(crc))
        local.append(le32(UInt32(data.count)))
        local.append(le32(UInt32(data.count)))
        local.append(le16(UInt16(name.count)))
        local.append(le16(0))
        local.append(name)
        local.append(data)
        body.append(local)

        var c = Data()
        c.append(le32(0x02014b50))
        c.append(le16(20))
        c.append(le16(20))
        c.append(le16(0x0800))
        c.append(le16(0))
        c.append(le16(dosTime))
        c.append(le16(dosDate))
        c.append(le32(crc))
        c.append(le32(UInt32(data.count)))
        c.append(le32(UInt32(data.count)))
        c.append(le16(UInt16(name.count)))
        c.append(le16(0))
        c.append(le16(0))
        c.append(le16(0))
        c.append(le16(0))
        c.append(le32(0))
        c.append(le32(offset))
        c.append(name)
        central.append(c)
        entries += 1
    }

    public func finish() -> Data {
        var out = body
        out.append(central)
        out.append(le32(0x06054b50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries)))
        out.append(le16(UInt16(entries)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(UInt32(body.count)))
        out.append(le16(0))
        return out
    }

    private func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    static func dosDateTime(_ date: Date = Date()) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: date)
        let year = max(1980, c.year ?? 1980)
        let time = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        let day = UInt16(((year - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        return (time, day)
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}
