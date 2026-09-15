//
//  ID3Writer.swift
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

/// Writes ID3v2.4 tags for standalone MP3 files. The tag format itself
/// (header/frame build/parse) lives in ID3FrameCodec.swift, shared with
/// AIFFWriter — this file only handles where the tag sits in an MP3: at
/// byte 0, with audio data immediately after, plus an optional trailing
/// ID3v1 tag to clean up on strip.
struct ID3Writer: TagWriter {

    static func canHandle(format: AudioFormat) -> Bool { format == .mp3 }

    static func write(url: URL, changes: TagChanges) async throws {
        let data = try Data(contentsOf: url)
        let audioStart = existingTagSize(in: data)
        let audioData = data.subdata(in: (data.startIndex + audioStart)..<data.endIndex)

        var newFrames: [Data] = []
        if let v = changes.title { newFrames.append(ID3FrameCodec.textFrame("TIT2", v)) }
        if let v = changes.artist { newFrames.append(ID3FrameCodec.textFrame("TPE1", v)) }
        if let v = changes.album { newFrames.append(ID3FrameCodec.textFrame("TALB", v)) }
        if let v = changes.genre { newFrames.append(ID3FrameCodec.textFrame("TCON", v)) }
        if let v = changes.track { newFrames.append(ID3FrameCodec.textFrame("TRCK", v)) }
        // v2.4 unifies year/date into TDRC; the older v2.3 split
        // (TYER/TDAT/TIME) is handled below by dropping those from any
        // preserved frames, so a file never ends up with both.
        if let v = changes.year { newFrames.append(ID3FrameCodec.textFrame("TDRC", v)) }
        if let v = changes.comment { newFrames.append(ID3FrameCodec.commentFrame(v)) }

        var frames = newFrames
        if audioStart > 0 {
            let existingTag = data.subdata(in: data.startIndex..<(data.startIndex + audioStart))
            let existingFrames = ID3FrameCodec.parseTag(existingTag)
            var droppedIDs = Set(newFrames.compactMap { ID3FrameCodec.frameID(of: $0) })
            // Setting the year replaces whichever date frame(s) already
            // exist, v2.3-style or v2.4-style — otherwise a legacy TYER
            // could survive alongside a freshly written TDRC, and players
            // could show either one depending on which they prefer.
            if changes.year != nil {
                droppedIDs.formUnion(["TYER", "TDAT", "TIME"])
            }
            // Rebuild (not copy) preserved frames: we always emit a v2.4
            // header below, but a preserved frame's *original* raw bytes
            // might carry a v2.3 plain-integer size field. Reusing those
            // bytes verbatim under a v2.4 header would mean a future reader
            // misinterprets that size again — same bug, just re-introduced
            // on write. Rebuilding from the already-correctly-decoded
            // `content` guarantees the size field matches the header we claim.
            let preserved = existingFrames
                .filter { !droppedIDs.contains($0.id) }
                .map { ID3FrameCodec.frame(id: $0.id, content: $0.content) }
            frames = preserved + newFrames
        }

        let tagBody = frames.reduce(Data(), +)
        var output = ID3FrameCodec.header(bodySize: tagBody.count)
        output.append(tagBody)
        output.append(audioData)

        try output.write(to: url, options: .atomic)
    }

    static func strip(url: URL) async throws {
        let data = try Data(contentsOf: url)
        let audioStart = existingTagSize(in: data)
        var audioEnd = data.count

        // Also drop a trailing ID3v1 tag if present (fixed last 128 bytes,
        // starts with "TAG").
        if data.count >= 128 {
            let tail = data.subdata(in: (data.endIndex - 128)..<data.endIndex)
            if tail.prefix(3).elementsEqual("TAG".utf8) {
                audioEnd -= 128
            }
        }

        let safeEnd = max(audioStart, audioEnd)
        let stripped = data.subdata(in: (data.startIndex + audioStart)..<(data.startIndex + safeEnd))
        try stripped.write(to: url, options: .atomic)
    }

    /// Byte offset right after any existing ID3v2 tag (0 if none present).
    private static func existingTagSize(in data: Data) -> Int {
        guard data.count >= 10, data.prefix(3).elementsEqual("ID3".utf8) else { return 0 }
        let sizeBytes = data.subdata(in: (data.startIndex + 6)..<(data.startIndex + 10))
        return 10 + ID3FrameCodec.syncsafeDecode(sizeBytes)
    }
}
