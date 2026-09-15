//
//  VorbisCommentCodec.swift
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

/// Encode/decode for the Vorbis comment format (the tagging scheme FLAC
/// uses, and Ogg Vorbis/Opus too — this logic is reusable there if that
/// format gets added later). Shared by FLACReader (decode only) and
/// FLACWriter (decode existing, modify, re-encode).
enum VorbisCommentCodec {
    static func decode(_ block: Data) -> [String: String] {
        var comments: [String: String] = [:]
        var i = block.startIndex

        func readUInt32LE() -> Int? {
            guard i + 4 <= block.endIndex else { return nil }
            let v = UInt32(block[i]) | UInt32(block[i + 1]) << 8
                  | UInt32(block[i + 2]) << 16 | UInt32(block[i + 3]) << 24
            i += 4
            return Int(v)
        }

        guard let vendorLength = readUInt32LE(), i + vendorLength <= block.endIndex else {
            return comments
        }
        i += vendorLength // vendor string itself isn't needed for our purposes

        guard let count = readUInt32LE() else { return comments }
        for _ in 0..<count {
            guard let len = readUInt32LE(), i + len <= block.endIndex else { break }
            let entry = String(decoding: block[i..<(i + len)], as: UTF8.self)
            i += len
            if let eq = entry.firstIndex(of: "=") {
                let key = String(entry[entry.startIndex..<eq]).uppercased()
                let value = String(entry[entry.index(after: eq)...])
                comments[key] = value
            }
        }
        return comments
    }

    static func encode(_ comments: [String: String], vendor: String = "audiotag4") -> Data {
        var out = Data()

        func appendUInt32LE(_ value: Int) {
            let v = UInt32(value)
            out.append(UInt8(v & 0xFF))
            out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF))
            out.append(UInt8((v >> 24) & 0xFF))
        }

        appendUInt32LE(vendor.utf8.count)
        out.append(contentsOf: vendor.utf8)

        appendUInt32LE(comments.count)
        for (key, value) in comments {
            let entry = "\(key)=\(value)"
            let bytes = Array(entry.utf8)
            appendUInt32LE(bytes.count)
            out.append(contentsOf: bytes)
        }

        return out
    }
}
