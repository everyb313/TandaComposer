//
//  AIFFWriter.swift
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

/// Writes tags for AIFF/AIFC by rewriting (or inserting) an embedded
/// "ID3 " chunk — the same ID3v2.4 tag format MP3 uses, just relocated
/// into an IFF chunk. Frame-level logic is shared via ID3FrameCodec.swift.
struct AIFFWriter: TagWriter {

    static func canHandle(format: AudioFormat) -> Bool { format == .aiff }

    static func write(url: URL, changes: TagChanges) async throws {
        let data = try Data(contentsOf: url)
        let (formType, chunks) = try AIFFChunks.parse(data)

        var newChunks = chunks
        var existingFrames: [ID3FrameCodec.Frame] = []
        var id3Index: Int?

        for (i, chunk) in chunks.enumerated() where chunk.id == "ID3 " {
            existingFrames = ID3FrameCodec.parseTag(chunk.data)
            id3Index = i
        }

        var newFrames: [Data] = []
        if let v = changes.title { newFrames.append(ID3FrameCodec.textFrame("TIT2", v)) }
        if let v = changes.artist { newFrames.append(ID3FrameCodec.textFrame("TPE1", v)) }
        if let v = changes.album { newFrames.append(ID3FrameCodec.textFrame("TALB", v)) }
        if let v = changes.genre { newFrames.append(ID3FrameCodec.textFrame("TCON", v)) }
        if let v = changes.track { newFrames.append(ID3FrameCodec.textFrame("TRCK", v)) }
        // v2.4 unifies year/date into TDRC; dropped IDs below take care of
        // any older v2.3-style TYER/TDAT/TIME so a file never ends up
        // carrying both.
        if let v = changes.year { newFrames.append(ID3FrameCodec.textFrame("TDRC", v)) }
        if let v = changes.comment { newFrames.append(ID3FrameCodec.commentFrame(v)) }

        var droppedIDs = Set(newFrames.compactMap { ID3FrameCodec.frameID(of: $0) })
        if changes.year != nil {
            droppedIDs.formUnion(["TYER", "TDAT", "TIME"])
        }
        // Rebuild (not copy) preserved frames: we always emit a v2.4 header
        // below, but the source AIFF's embedded tag may be older v2.3
        // (plain frame sizes). Reusing original raw bytes verbatim under a
        // v2.4 header would leave a mismatched size field — same bug the
        // parser fixed, reintroduced on write. Rebuilding from `content`
        // (already correctly decoded regardless of source version)
        // guarantees the size field matches the header we claim.
        let preserved = existingFrames
            .filter { !droppedIDs.contains($0.id) }
            .map { ID3FrameCodec.frame(id: $0.id, content: $0.content) }

        let tagBody = (preserved + newFrames).reduce(Data(), +)
        var tagData = ID3FrameCodec.header(bodySize: tagBody.count)
        tagData.append(tagBody)

        let newID3Chunk = AIFFChunk(id: "ID3 ", data: tagData)
        if let idx = id3Index {
            newChunks[idx] = newID3Chunk
        } else {
            newChunks.append(newID3Chunk)
        }

        let output = AIFFChunks.serialize(formType: formType, chunks: newChunks)
        try output.write(to: url, options: .atomic)
    }

    static func strip(url: URL) async throws {
        let data = try Data(contentsOf: url)
        let (formType, chunks) = try AIFFChunks.parse(data)

        // Keep technical chunks (COMM, SSND, FVER, etc.); drop the embedded
        // ID3 tag and AIFF's own sparse native metadata chunks.
        let kept = chunks.filter { !["ID3 ", "NAME", "AUTH", "ANNO", "(c) "].contains($0.id) }

        let output = AIFFChunks.serialize(formType: formType, chunks: kept)
        try output.write(to: url, options: .atomic)
    }
}
