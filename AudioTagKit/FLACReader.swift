//
//  FLACReader.swift
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

/// Read-only interpretation of FLAC metadata blocks. Framing/parsing itself
/// lives in FLACBlocks.swift (shared with FLACWriter) — this just decides
/// what each block type means.
struct FLACReader: MetadataReader {

    static func canHandle(url: URL) -> Bool {
        if url.pathExtension.lowercased() == "flac" { return true }
        return FormatSniffer.detect(url: url) == .flac
    }

    static func read(url: URL) async throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let (blocks, _) = try FLACBlocks.parse(data)

        var result: [String: Any] = [:]

        for block in blocks {
            switch block.type {
            case FLACBlocks.streamInfo:
                let info = parseStreamInfo(block.data)
                result["streamInfo"] = info
                // Surfaced at the top level too (not just nested in
                // streamInfo) to match AVFoundationReader's convention —
                // callers that generically look up "durationSeconds" for
                // any format shouldn't need format-specific handling.
                if let duration = info["durationSeconds"] as? Double {
                    result["durationSeconds"] = duration
                }
            case FLACBlocks.vorbisComment:
                result["vorbisComments"] = VorbisCommentCodec.decode(block.data)
            case FLACBlocks.picture:
                result["hasArtwork"] = true
                result["artworkInfo"] = parsePictureInfo(block.data)
            default:
                break
            }
        }

        result["format"] = "FLAC"
        return result
    }

    private static func parseStreamInfo(_ block: Data) -> [String: Any] {
        guard block.count >= 18 else { return [:] }
        let base = block.startIndex
        let b10 = Int(block[base + 10])
        let b11 = Int(block[base + 11])
        let b12 = Int(block[base + 12])
        let b13 = Int(block[base + 13])
        let b14 = Int(block[base + 14])
        let b15 = Int(block[base + 15])
        let b16 = Int(block[base + 16])
        let b17 = Int(block[base + 17])

        let sampleRate = (b10 << 12) | (b11 << 4) | (b12 >> 4)
        let channels = ((b12 >> 1) & 0x07) + 1
        let bitsPerSample = (((b12 & 0x01) << 4) | (b13 >> 4)) + 1

        // Total samples is a 36-bit field, picking up exactly where
        // bitsPerSample's bit-packing leaves off: the low 4 bits of byte 13
        // are its top 4 bits, followed by all of bytes 14-17 (32 more bits).
        let totalSamples = (Int(b13 & 0x0F) << 32) | (b14 << 24) | (b15 << 16) | (b16 << 8) | b17

        var result: [String: Any] = ["sampleRate": sampleRate, "channels": channels, "bitsPerSample": bitsPerSample]

        // A total-sample count of 0 is FLAC's own convention for "unknown
        // length" (e.g. a still-being-encoded stream) — omit duration
        // rather than falsely reporting zero.
        if totalSamples > 0 && sampleRate > 0 {
            result["durationSeconds"] = Double(totalSamples) / Double(sampleRate)
        }

        return result
    }

    /// Reports mime/dimensions only — raw picture bytes are handled
    /// separately by ArtworkExtractor, never surfaced through the general
    /// metadata read (which stays free of binary dumps).
    private static func parsePictureInfo(_ block: Data) -> [String: Any] {
        var i = block.startIndex
        func readUInt32BE() -> Int? {
            guard i + 4 <= block.endIndex else { return nil }
            let v = UInt32(block[i]) << 24 | UInt32(block[i + 1]) << 16
                  | UInt32(block[i + 2]) << 8 | UInt32(block[i + 3])
            i += 4
            return Int(v)
        }

        guard let pictureType = readUInt32BE(),
              let mimeLength = readUInt32BE(),
              i + mimeLength <= block.endIndex else { return [:] }
        let mime = String(decoding: block[i..<(i + mimeLength)], as: UTF8.self)
        i += mimeLength

        guard let descLength = readUInt32BE(), i + descLength <= block.endIndex else {
            return ["pictureType": pictureType, "mime": mime]
        }
        i += descLength

        guard let width = readUInt32BE(), let height = readUInt32BE() else {
            return ["pictureType": pictureType, "mime": mime]
        }
        return ["pictureType": pictureType, "mime": mime, "width": width, "height": height]
    }
}
