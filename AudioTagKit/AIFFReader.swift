//
//  AIFFReader.swift
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

/// Reads AIFF/AIFC metadata. Unlike MP3/M4A, this doesn't lean on
/// AVFoundation — AVAsset's AIFF metadata support is inconsistent across
/// macOS versions, so this is fully hand-rolled: chunk framing lives in
/// AIFFChunks.swift, ID3 tag decoding in ID3FrameCodec.swift.
struct AIFFReader: MetadataReader {

    static func canHandle(url: URL) -> Bool {
        if ["aiff", "aif", "aifc"].contains(url.pathExtension.lowercased()) { return true }
        return FormatSniffer.detect(url: url) == .aiff
    }

    static func read(url: URL) async throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let (formType, chunks) = try AIFFChunks.parse(data)

        var result: [String: Any] = [:]
        var common: [String: Any] = [:]
        var formatSpecific: [String: Any] = [:]

        if let comm = chunks.first(where: { $0.id == "COMM" }) {
            let info = parseCommChunk(comm.data)
            result["streamInfo"] = info
            // Surfaced at the top level too (not just nested in
            // streamInfo) to match AVFoundationReader's convention —
            // callers that generically look up "durationSeconds" for
            // any format shouldn't need format-specific handling.
            if let duration = info["durationSeconds"] as? Double {
                result["durationSeconds"] = duration
            }
        }

        if let id3Chunk = chunks.first(where: { $0.id == "ID3 " }) {
            let frames = ID3FrameCodec.parseTag(id3Chunk.data)
            var id3Fields: [String: Any] = [:]

            // Every frame gets surfaced in formatSpecific["ID3"], not just
            // a hardcoded handful — matching what MP3 already gets for
            // free via AVFoundation. The 7 canonical fields additionally
            // get mirrored into `common` for convenience/CanonicalTags.
            for f in frames {
                switch f.id {
                case "APIC":
                    result["hasArtwork"] = true
                case "TXXX":
                    // User-defined text frame: value is keyed by its own
                    // description (e.g. "REPLAYGAIN_TRACK_GAIN"), since a
                    // file can carry many TXXX frames side by side.
                    let (description, value) = ID3FrameCodec.decodeUserTextFrame(f.content)
                    let key = description.isEmpty ? "TXXX" : "TXXX:\(description)"
                    id3Fields[key] = value
                case "COMM":
                    // A file can carry several COMM frames distinguished
                    // only by description (e.g. a real comment alongside
                    // an iTunNORM/iTunSMPB analysis blob) — keying by
                    // description instead of just "COMM" stops one from
                    // silently overwriting another.
                    let (description, value) = ID3FrameCodec.decodeCommentFrame(f.content)
                    let key = description.isEmpty ? "COMM" : "COMM:\(description)"
                    id3Fields[key] = value
                    if description.isEmpty { common["description"] = value } // only a genuine plain comment maps to the canonical field
                case "TDRC":
                    id3Fields["TYER"] = ID3FrameCodec.decodeTextValue(f.content) // v2.4 unified date frame, normalized to the same key as legacy TYER
                case "TYER":
                    if id3Fields["TYER"] == nil { id3Fields["TYER"] = ID3FrameCodec.decodeTextValue(f.content) } // older v2.3 files; TDRC takes priority if both present
                default:
                    if f.id.hasPrefix("T") {
                        let value = ID3FrameCodec.decodeTextValue(f.content)
                        id3Fields[f.id] = value
                        switch f.id {
                        case "TIT2": common["title"] = value
                        case "TPE1": common["artist"] = value
                        case "TALB": common["albumName"] = value
                        default: break
                        }
                    } else {
                        // Non-text, non-picture frame we don't specifically
                        // decode (e.g. PRIV, UFID) — note its presence and
                        // size rather than silently dropping it or dumping
                        // raw bytes into the output.
                        id3Fields[f.id] = "<binary, \(f.content.count) bytes>"
                    }
                }
            }
            if !id3Fields.isEmpty { formatSpecific["ID3"] = id3Fields }
        } else {
            // No embedded ID3 tag — fall back to AIFF's own sparse,
            // old-school metadata chunks.
            if let name = chunks.first(where: { $0.id == "NAME" }) {
                common["title"] = String(decoding: name.data, as: UTF8.self)
            }
            if let auth = chunks.first(where: { $0.id == "AUTH" }) {
                common["artist"] = String(decoding: auth.data, as: UTF8.self)
            }
            if let anno = chunks.first(where: { $0.id == "ANNO" }) {
                common["description"] = String(decoding: anno.data, as: UTF8.self)
            }
        }

        if !common.isEmpty { result["common"] = common }
        if !formatSpecific.isEmpty { result["formatSpecific"] = formatSpecific }
        result["format"] = formType
        return result
    }

    /// COMM chunk layout (all big-endian): numChannels(2), numSampleFrames(4),
    /// sampleSize/bitsPerSample(2), sampleRate(10-byte IEEE 754 extended float).
    private static func parseCommChunk(_ data: Data) -> [String: Any] {
        guard data.count >= 18 else { return [:] }
        let base = data.startIndex
        let channels = Int(data[base]) << 8 | Int(data[base + 1])
        let numSampleFrames = Int(data[base + 2]) << 24 | Int(data[base + 3]) << 16
                             | Int(data[base + 4]) << 8 | Int(data[base + 5])
        let sampleSize = Int(data[base + 6]) << 8 | Int(data[base + 7])
        let extended = Array(data[(base + 8)..<(base + 18)])
        let sampleRate = decodeExtendedFloat80(extended)
        let roundedSampleRate = Int(sampleRate.rounded())

        var result: [String: Any] = [
            "channels": channels,
            "bitsPerSample": sampleSize,
            "sampleRate": roundedSampleRate
        ]

        // A sample-frame count of 0 can legitimately occur for an
        // in-progress/streamed AIFF — omit duration rather than falsely
        // reporting zero, same convention as FLACReader.
        if numSampleFrames > 0 && roundedSampleRate > 0 {
            result["durationSeconds"] = Double(numSampleFrames) / Double(roundedSampleRate)
        }

        return result
    }

    /// Decodes AIFF's 80-bit IEEE 754 "extended" float, used for sampleRate
    /// in the COMM chunk. Swift has no native type for this, so it's
    /// unpacked by hand: 1 sign bit + 15 exponent bits + 64-bit mantissa
    /// with an *explicit* (not implicit) leading integer bit.
    private static func decodeExtendedFloat80(_ bytes: [UInt8]) -> Double {
        guard bytes.count == 10 else { return 0 }
        let sign: Double = (bytes[0] & 0x80) != 0 ? -1.0 : 1.0
        let exponent = (Int(bytes[0] & 0x7F) << 8) | Int(bytes[1])

        var mantissa: UInt64 = 0
        for i in 2..<10 {
            mantissa = (mantissa << 8) | UInt64(bytes[i])
        }
        if exponent == 0 && mantissa == 0 { return 0 }

        let exp = exponent - 16383
        let normalizedMantissa = Double(mantissa) / Double(UInt64(1) << 63)
        return sign * normalizedMantissa * pow(2.0, Double(exp))
    }
}
