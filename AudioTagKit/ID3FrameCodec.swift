//
//  ID3FrameCodec.swift
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

/// Shared ID3v2.4 tag codec: builds/parses the *complete* tag blob (header
/// + frames). Used standalone at the start of an MP3 file (ID3Writer) and
/// embedded inside an AIFF "ID3 " chunk (AIFFReader/AIFFWriter) — the tag
/// format itself is identical in both places, only its surrounding
/// container differs.
///
/// Writes always use v2.4 (syncsafe frame sizes, unified TDRC date frame)
/// rather than the older v2.3 — real-world files from modern taggers
/// (iTunes/Music.app, JRiver, etc.) are overwhelmingly v2.4 already, so
/// writing v2.3 was mostly just downgrading files unnecessarily. *Parsing*
/// still auto-detects the source tag's actual version (see `parseTag`),
/// so older v2.3 files read correctly too — only the format we emit is fixed.
enum ID3FrameCodec {

    struct Frame {
        let id: String
        let raw: Data      // full frame including its own 10-byte header
        let content: Data  // frame payload only
    }

    // MARK: - Parsing a complete tag blob (header + frames)

    /// `data` must start with "ID3" (the standard v2 header) — e.g. the
    /// first bytes of an MP3 file, or the full contents of an AIFF
    /// "ID3 " chunk.
    ///
    /// Frame *sizes* are encoded differently depending on tag version:
    /// ID3v2.3 uses a plain 32-bit big-endian integer; ID3v2.4 uses a
    /// syncsafe (7-bits-per-byte) integer, same scheme as the outer tag
    /// header's size field. Getting this wrong only shows up on frames
    /// large enough that a size byte needs its top bit set (e.g. embedded
    /// artwork) — small text frames decode identically either way, which
    /// is exactly why this was easy to miss.
    static func parseTag(_ data: Data) -> [Frame] {
        guard data.count >= 10, data.prefix(3).elementsEqual("ID3".utf8) else { return [] }
        let majorVersion = data[data.startIndex + 3]
        let sizesAreSyncsafe = majorVersion >= 4

        let sizeBytes = data.subdata(in: (data.startIndex + 6)..<(data.startIndex + 10))
        let bodySize = syncsafeDecode(sizeBytes)
        let bodyStart = data.startIndex + 10
        let bodyEnd = min(bodyStart + bodySize, data.endIndex)
        guard bodyStart <= bodyEnd else { return [] }
        return parseFrames(data.subdata(in: bodyStart..<bodyEnd), sizesAreSyncsafe: sizesAreSyncsafe)
    }

    /// Parses a raw frame sequence (tag body only, no outer ID3 header).
    /// `sizesAreSyncsafe` should be `true` for ID3v2.4 tags, `false` for
    /// older v2.3 tags. Defaults to `false` only because that's the safer
    /// assumption for a bare frame sequence with no header to check —
    /// `parseTag` (which does have the header) always passes the real,
    /// detected value explicitly rather than relying on this default.
    static func parseFrames(_ tagBody: Data, sizesAreSyncsafe: Bool = false) -> [Frame] {
        var result: [Frame] = []
        var offset = tagBody.startIndex

        while offset + 10 <= tagBody.endIndex {
            let idBytes = tagBody.subdata(in: offset..<(offset + 4))
            if idBytes.allSatisfy({ $0 == 0 }) { break } // padding reached
            let id = String(decoding: idBytes, as: UTF8.self)

            let sizeBytes = tagBody.subdata(in: (offset + 4)..<(offset + 8))
            let size = sizesAreSyncsafe ? syncsafeDecode(sizeBytes) : plainSizeDecode(sizeBytes)

            let frameEnd = offset + 10 + size
            guard size >= 0, frameEnd <= tagBody.endIndex else { break }

            let raw = tagBody.subdata(in: offset..<frameEnd)
            let content = tagBody.subdata(in: (offset + 10)..<frameEnd)
            result.append(Frame(id: id, raw: raw, content: content))
            offset = frameEnd
        }
        return result
    }

    private static func plainSizeDecode(_ sizeBytes: Data) -> Int {
        Int(sizeBytes[sizeBytes.startIndex]) << 24
            | Int(sizeBytes[sizeBytes.startIndex + 1]) << 16
            | Int(sizeBytes[sizeBytes.startIndex + 2]) << 8
            | Int(sizeBytes[sizeBytes.startIndex + 3])
    }

    static func frameID(of rawFrame: Data) -> String? {
        guard rawFrame.count >= 4 else { return nil }
        return String(decoding: rawFrame.prefix(4), as: UTF8.self)
    }

    // MARK: - Tag header (syncsafe size)

    static func header(bodySize: Int) -> Data {
        var header = Data("ID3".utf8)
        header.append(contentsOf: [0x04, 0x00]) // version 2.4.0
        header.append(0x00)                     // flags
        header.append(syncsafeEncode(bodySize))
        return header
    }

    static func syncsafeEncode(_ value: Int) -> Data {
        var v = UInt32(value)
        var bytes = [UInt8](repeating: 0, count: 4)
        for i in stride(from: 3, through: 0, by: -1) {
            bytes[i] = UInt8(v & 0x7F)
            v >>= 7
        }
        return Data(bytes)
    }

    static func syncsafeDecode(_ data: Data) -> Int {
        var result = 0
        for byte in data { result = (result << 7) | Int(byte & 0x7F) }
        return result
    }

    // MARK: - Frame building (writing)
    // Text frames use encoding $01 (UTF-16 with an explicit BOM) so any
    // script round-trips correctly, not just ISO-8859-1-safe text.

    static func textFrame(_ id: String, _ value: String) -> Data {
        var content = Data([0x01])
        if let bytes = "\u{FEFF}\(value)".data(using: .utf16LittleEndian) {
            content.append(bytes)
        }
        content.append(contentsOf: [0x00, 0x00])
        return frame(id: id, content: content)
    }

    static func commentFrame(_ value: String) -> Data {
        var content = Data([0x01])
        content.append(contentsOf: Array("eng".utf8))
        content.append(contentsOf: [0x00, 0x00]) // empty short description, terminated
        if let text = "\u{FEFF}\(value)".data(using: .utf16LittleEndian) {
            content.append(text)
        }
        return frame(id: "COMM", content: content)
    }

    /// Frame header layout is the same shape in v2.3 and v2.4 (4-byte id,
    /// 4-byte size, 2-byte flags) but the *size* encoding differs: v2.3
    /// uses a plain 32-bit integer, v2.4 uses syncsafe — same scheme as
    /// the outer tag header. Since we write v2.4, frame sizes here are
    /// syncsafe too, not just the tag-level size.
    static func frame(id: String, content: Data) -> Data {
        var out = Data(id.utf8)
        out.append(syncsafeEncode(content.count))
        out.append(contentsOf: [0x00, 0x00]) // frame flags
        out.append(content)
        return out
    }

    // MARK: - Frame decoding (reading — new in audiotag4, needed because
    // AIFF can't lean on AVFoundation the way MP3 reading does)

    /// Decodes a text-frame payload (TIT2/TPE1/TALB/TCON/TDRC/TRCK/...):
    /// one encoding byte, then the string in that encoding.
    static func decodeTextValue(_ content: Data) -> String {
        guard let encodingByte = content.first else { return "" }
        let textBytes = Data(content.dropFirst())

        switch encodingByte {
        case 0x00: // ISO-8859-1 (Latin-1) — NOT the same as UTF-8; any
                   // accented character (é, ü, ñ) decodes wrong if treated
                   // as UTF-8, so this needs its own real Latin-1 decode.
            let str = String(data: textBytes, encoding: .isoLatin1) ?? String(decoding: textBytes, as: UTF8.self)
            return str.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        case 0x01: // UTF-16 with BOM
            let str = String(data: textBytes, encoding: .utf16) ?? ""
            return str.trimmingCharacters(in: CharacterSet(charactersIn: "\0\u{FEFF}"))
        case 0x02: // UTF-16BE, no BOM
            let str = String(data: textBytes, encoding: .utf16BigEndian) ?? ""
            return str.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        default: // 0x03 UTF-8 (v2.4)
            return String(decoding: textBytes, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }
    }

    /// Decodes a COMM frame's payload and returns *both* its description
    /// and its value — a file can carry several COMM frames distinguished
    /// only by description (a real comment alongside an iTunNORM/iTunSMPB
    /// analysis blob, for instance), so the description matters for
    /// telling them apart, not just for display.
    static func decodeCommentFrame(_ content: Data) -> (description: String, value: String) {
        guard content.count > 4 else { return ("", "") }
        let encodingByte = content[content.startIndex]
        let descStart = content.index(content.startIndex, offsetBy: 4) // skip encoding + 3-byte language
        var i = descStart
        var descEnd: Data.Index

        if encodingByte == 0x00 || encodingByte == 0x03 {
            descEnd = content[i...].firstIndex(of: 0x00) ?? content.endIndex
            i = descEnd < content.endIndex ? content.index(after: descEnd) : content.endIndex
        } else {
            var j = i
            while j + 1 < content.endIndex {
                if content[j] == 0x00 && content[j + 1] == 0x00 { break }
                j += 2
            }
            descEnd = j
            i = content.index(j, offsetBy: 2, limitedBy: content.endIndex) ?? content.endIndex
        }

        let descriptionBytes = Data(content[descStart..<descEnd])
        let valueBytes = Data(content[i...])
        return (decodeStringBytes(descriptionBytes, encodingByte: encodingByte),
                decodeStringBytes(valueBytes, encodingByte: encodingByte))
    }

    /// Decodes a COMM frame's value only, discarding its description —
    /// kept for callers that don't need to distinguish multiple COMM
    /// frames (most legitimate uses only have one anyway).
    static func decodeCommentValue(_ content: Data) -> String {
        decodeCommentFrame(content).value
    }

    /// Decodes a TXXX (user-defined text) frame: encoding byte,
    /// description (terminated), then the value — the rest of the frame,
    /// with no further terminator needed since it runs to frame end.
    /// Structurally identical to COMM's description+value shape, just
    /// without the 3-byte language field COMM has.
    static func decodeUserTextFrame(_ content: Data) -> (description: String, value: String) {
        guard let encodingByte = content.first else { return ("", "") }
        let descStart = content.index(after: content.startIndex)
        var i = descStart
        var descEnd: Data.Index

        if encodingByte == 0x00 || encodingByte == 0x03 {
            descEnd = content[i...].firstIndex(of: 0x00) ?? content.endIndex
            i = descEnd < content.endIndex ? content.index(after: descEnd) : content.endIndex
        } else {
            var j = i
            while j + 1 < content.endIndex {
                if content[j] == 0x00 && content[j + 1] == 0x00 { break }
                j += 2
            }
            descEnd = j
            i = content.index(j, offsetBy: 2, limitedBy: content.endIndex) ?? content.endIndex
        }

        let descriptionBytes = Data(content[descStart..<descEnd])
        let valueBytes = Data(content[i...])
        return (decodeStringBytes(descriptionBytes, encodingByte: encodingByte),
                decodeStringBytes(valueBytes, encodingByte: encodingByte))
    }

    /// Shared string decode for a byte range + ID3 encoding byte — used by
    /// both COMM and TXXX decoding, which have identical per-field text
    /// encoding rules, just different frame layouts around those fields.
    private static func decodeStringBytes(_ bytes: Data, encodingByte: UInt8) -> String {
        switch encodingByte {
        case 0x00: // ISO-8859-1
            let str = String(data: bytes, encoding: .isoLatin1) ?? String(decoding: bytes, as: UTF8.self)
            return str.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        case 0x01: // UTF-16 with BOM
            let str = String(data: bytes, encoding: .utf16) ?? ""
            return str.trimmingCharacters(in: CharacterSet(charactersIn: "\0\u{FEFF}"))
        case 0x02: // UTF-16BE, no BOM
            let str = String(data: bytes, encoding: .utf16BigEndian) ?? ""
            return str.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        default: // 0x03 UTF-8
            return String(decoding: bytes, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }
    }

    /// Decodes an APIC (attached picture) frame's payload: encoding byte,
    /// MIME type (always ISO-8859-1, null-terminated), picture type byte,
    /// description (encoded per the encoding byte, skipped here), then the
    /// raw image bytes for the rest of the frame.
    static func decodePictureFrame(_ content: Data) -> (mime: String, data: Data)? {
        guard let encodingByte = content.first else { return nil }
        var i = content.index(after: content.startIndex)

        guard let mimeEnd = content[i...].firstIndex(of: 0x00) else { return nil }
        let mime = String(decoding: content[i..<mimeEnd], as: UTF8.self)
        i = content.index(after: mimeEnd)

        guard i < content.endIndex else { return nil }
        i = content.index(after: i) // picture type byte

        if encodingByte == 0x00 || encodingByte == 0x03 {
            guard let descEnd = content[i...].firstIndex(of: 0x00) else { return nil }
            i = content.index(after: descEnd)
        } else {
            var j = i
            while j + 1 < content.endIndex {
                if content[j] == 0x00 && content[j + 1] == 0x00 { break }
                j += 2
            }
            i = content.index(j, offsetBy: 2, limitedBy: content.endIndex) ?? content.endIndex
        }

        return (mime, Data(content[i...]))
    }
}
