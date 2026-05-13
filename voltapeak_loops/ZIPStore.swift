//
//  ZIPStore.swift
//  voltapeak_loops
//
//  Mini-ZIP store-only (compression method = 0) suffisant pour OOXML.
//  Excel, Numbers, Google Sheets et LibreOffice acceptent ce format.
//  Repris de scadinot/voltapeakApp puis extrait pour être partagé entre
//  les deux écrivains XLSX (per-file et agrégé).
//

import Foundation

enum ZIPStore {

    static func archive(_ files: [(name: String, data: Data)]) -> Data {
        var output = Data()
        var central = Data()

        for file in files {
            let nameBytes = Array(file.name.utf8)
            let crc = crc32(file.data)
            let size = UInt32(file.data.count)
            let localOffset = UInt32(output.count)

            var lfh = Data()
            lfh.appendUInt32LE(0x04034b50)
            lfh.appendUInt16LE(20)
            lfh.appendUInt16LE(0)
            lfh.appendUInt16LE(0)
            lfh.appendUInt16LE(0)
            lfh.appendUInt16LE(0)
            lfh.appendUInt32LE(crc)
            lfh.appendUInt32LE(size)
            lfh.appendUInt32LE(size)
            lfh.appendUInt16LE(UInt16(nameBytes.count))
            lfh.appendUInt16LE(0)
            lfh.append(contentsOf: nameBytes)
            output.append(lfh)
            output.append(file.data)

            var cde = Data()
            cde.appendUInt32LE(0x02014b50)
            cde.appendUInt16LE(20)
            cde.appendUInt16LE(20)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt32LE(crc)
            cde.appendUInt32LE(size)
            cde.appendUInt32LE(size)
            cde.appendUInt16LE(UInt16(nameBytes.count))
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt32LE(0)
            cde.appendUInt32LE(localOffset)
            cde.append(contentsOf: nameBytes)
            central.append(cde)
        }

        let centralStart = UInt32(output.count)
        let centralSize = UInt32(central.count)
        output.append(central)

        var eocd = Data()
        eocd.appendUInt32LE(0x06054b50)
        eocd.appendUInt16LE(0)
        eocd.appendUInt16LE(0)
        eocd.appendUInt16LE(UInt16(files.count))
        eocd.appendUInt16LE(UInt16(files.count))
        eocd.appendUInt32LE(centralSize)
        eocd.appendUInt32LE(centralStart)
        eocd.appendUInt16LE(0)
        output.append(eocd)

        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask: UInt32 = (crc & 1) != 0 ? 0xEDB88320 : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

extension Data {
    mutating func appendUInt16LE(_ v: UInt16) {
        append(UInt8(v & 0xff))
        append(UInt8((v >> 8) & 0xff))
    }
    mutating func appendUInt32LE(_ v: UInt32) {
        append(UInt8(v & 0xff))
        append(UInt8((v >> 8) & 0xff))
        append(UInt8((v >> 16) & 0xff))
        append(UInt8((v >> 24) & 0xff))
    }
}
