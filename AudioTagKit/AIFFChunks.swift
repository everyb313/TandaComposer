//
//  AIFFChunks.swift
//
//  Copyright © 2026 Hagen Eckert.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

struct AIFFChunk {
    let id: String
    var data: Data
}

enum AIFFParseError: Error, CustomStringConvertible {
    case notAIFF
    case truncated

    var description: String {
        switch self {
        case .notAIFF: return "Not a valid AIFF/AIFC file (missing 'FORM' marker)."
        case .truncated: return "AIFF chunk structure appears truncated or corrupt."
        }
    }
}

/// Parses and serializes AIFF's IFF chunk structure. Unlike FLAC (metadata
/// blocks, then raw audio frames appended separately), AIFF chunks
/// *everything* — including the sound data itself, in an "SSND" chunk —
/// so every chunk is treated as an opaque (id, data) pair; there's no
/// separate "where does audio start" concept to track.
enum AIFFChunks {
    static func parse(_ data: Data) throws -> (formType: String, chunks: [AIFFChunk]) {
        guard data.count >= 12, data.prefix(4).elementsEqual("FORM".utf8) else {
            throw AIFFParseError.notAIFF
        }

        let formType = String(
            decoding: data.subdata(in: (data.startIndex + 8)..<(data.startIndex + 12)),
            as: UTF8.self
        )
        guard formType == "AIFF" || formType == "AIFC" else {
            throw AIFFParseError.notAIFF
        }

        var offset = 12
        var chunks: [AIFFChunk] = []

        while offset + 8 <= data.count {
            let idStart = data.startIndex + offset
            let id = String(decoding: data.subdata(in: idStart..<(idStart + 4)), as: UTF8.self)
            let sizeBytes = data.subdata(in: (idStart + 4)..<(idStart + 8))
            let size = Int(sizeBytes[sizeBytes.startIndex]) << 24
                     | Int(sizeBytes[sizeBytes.startIndex + 1]) << 16
                     | Int(sizeBytes[sizeBytes.startIndex + 2]) << 8
                     | Int(sizeBytes[sizeBytes.startIndex + 3])

            let chunkDataStart = idStart + 8
            let chunkDataEnd = chunkDataStart + size
            guard size >= 0, chunkDataEnd <= data.endIndex else { throw AIFFParseError.truncated }

            chunks.append(AIFFChunk(id: id, data: data.subdata(in: chunkDataStart..<chunkDataEnd)))

            // IFF chunks pad odd-sized data to the next even byte boundary.
            offset += 8 + size + (size % 2)
        }

        return (formType, chunks)
    }

    static func serialize(formType: String, chunks: [AIFFChunk]) -> Data {
        var body = Data(formType.utf8)

        for chunk in chunks {
            body.append(contentsOf: chunk.id.utf8)
            let size = UInt32(chunk.data.count)
            body.append(contentsOf: [
                UInt8((size >> 24) & 0xFF), UInt8((size >> 16) & 0xFF),
                UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)
            ])
            body.append(chunk.data)
            if chunk.data.count % 2 != 0 {
                body.append(0x00) // pad byte so the next chunk lands on an even offset
            }
        }

        var out = Data("FORM".utf8)
        let formSize = UInt32(body.count)
        out.append(contentsOf: [
            UInt8((formSize >> 24) & 0xFF), UInt8((formSize >> 16) & 0xFF),
            UInt8((formSize >> 8) & 0xFF), UInt8(formSize & 0xFF)
        ])
        out.append(body)
        return out
    }
}
