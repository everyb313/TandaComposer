//
//  FLACBlocks.swift
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

struct FLACBlock {
    let type: UInt8
    var data: Data
}

enum FLACParseError: Error, CustomStringConvertible {
    case notFLAC
    case truncated

    var description: String {
        switch self {
        case .notFLAC: return "Not a valid FLAC file (missing 'fLaC' marker)."
        case .truncated: return "FLAC metadata appears truncated or corrupt."
        }
    }
}

/// Parses and serializes FLAC's metadata block structure.
/// Spec reference: https://xiph.org/flac/format.html
/// Shared by FLACReader (read-only interpretation) and FLACWriter
/// (modify blocks, re-serialize) so the low-level framing logic exists
/// exactly once.
enum FLACBlocks {
    static let streamInfo: UInt8 = 0
    static let vorbisComment: UInt8 = 4
    static let picture: UInt8 = 6

    /// Parses all metadata blocks, returning them in file order plus the
    /// byte offset where actual audio frame data begins (right after the
    /// last metadata block).
    static func parse(_ data: Data) throws -> (blocks: [FLACBlock], audioOffset: Int) {
        guard data.count > 4, data.prefix(4).elementsEqual("fLaC".utf8) else {
            throw FLACParseError.notFLAC
        }

        var offset = 4
        var blocks: [FLACBlock] = []
        var isLast = false

        while !isLast {
            guard offset + 4 <= data.count else { throw FLACParseError.truncated }
            let header = data[data.startIndex + offset]
            isLast = (header & 0x80) != 0
            let blockType = header & 0x7F
            let length = Int(data[data.startIndex + offset + 1]) << 16
                       | Int(data[data.startIndex + offset + 2]) << 8
                       | Int(data[data.startIndex + offset + 3])

            let blockStart = offset + 4
            let blockEnd = blockStart + length
            guard blockEnd <= data.count else { throw FLACParseError.truncated }
            blocks.append(FLACBlock(
                type: blockType,
                data: data.subdata(in: (data.startIndex + blockStart)..<(data.startIndex + blockEnd))
            ))
            offset = blockEnd
        }

        return (blocks, offset)
    }

    /// Serializes a complete FLAC file: header + all metadata blocks + audio
    /// data. Recomputes the "is-last-block" flag from the block's position
    /// in the array, so callers can freely reorder/replace/insert blocks
    /// without manually tracking which one is last.
    static func serialize(blocks: [FLACBlock], audioData: Data) -> Data {
        var out = Data("fLaC".utf8)
        for (index, block) in blocks.enumerated() {
            let isLast = index == blocks.count - 1
            var header = block.type & 0x7F
            if isLast { header |= 0x80 }
            out.append(header)

            let length = block.data.count
            out.append(UInt8((length >> 16) & 0xFF))
            out.append(UInt8((length >> 8) & 0xFF))
            out.append(UInt8(length & 0xFF))
            out.append(block.data)
        }
        out.append(audioData)
        return out
    }
}
