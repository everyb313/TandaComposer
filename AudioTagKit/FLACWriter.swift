//
//  FLACWriter.swift
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

struct FLACWriter: TagWriter {

    static func canHandle(format: AudioFormat) -> Bool { format == .flac }

    static func write(url: URL, changes: TagChanges) async throws {
        let data = try Data(contentsOf: url)
        let (blocks, audioOffset) = try FLACBlocks.parse(data)
        let audioData = data.subdata(in: (data.startIndex + audioOffset)..<data.endIndex)

        var newBlocks = blocks
        var existingComments: [String: String] = [:]
        var vorbisIndex: Int?

        for (i, block) in blocks.enumerated() where block.type == FLACBlocks.vorbisComment {
            existingComments = VorbisCommentCodec.decode(block.data)
            vorbisIndex = i
        }

        apply(changes, to: &existingComments)
        let newBlock = FLACBlock(type: FLACBlocks.vorbisComment, data: VorbisCommentCodec.encode(existingComments))

        if let idx = vorbisIndex {
            newBlocks[idx] = newBlock
        } else {
            // No existing comment block — insert right after STREAMINFO if
            // present (STREAMINFO is required to be first), else at the front.
            let insertAt = (newBlocks.first?.type == FLACBlocks.streamInfo) ? 1 : 0
            newBlocks.insert(newBlock, at: insertAt)
        }

        let output = FLACBlocks.serialize(blocks: newBlocks, audioData: audioData)
        try output.write(to: url, options: .atomic)
    }

    static func strip(url: URL) async throws {
        let data = try Data(contentsOf: url)
        let (blocks, audioOffset) = try FLACBlocks.parse(data)
        let audioData = data.subdata(in: (data.startIndex + audioOffset)..<data.endIndex)

        // Keep technical blocks (STREAMINFO, SEEKTABLE, CUESHEET, PADDING,
        // APPLICATION) — a privacy scrub should still leave a playable file.
        // Drop VORBIS_COMMENT and PICTURE: the identifying/metadata blocks.
        let kept = blocks.filter {
            $0.type != FLACBlocks.vorbisComment && $0.type != FLACBlocks.picture
        }

        let output = FLACBlocks.serialize(blocks: kept, audioData: audioData)
        try output.write(to: url, options: .atomic)
    }

    private static func apply(_ changes: TagChanges, to comments: inout [String: String]) {
        if let v = changes.title { comments["TITLE"] = v }
        if let v = changes.artist { comments["ARTIST"] = v }
        if let v = changes.album { comments["ALBUM"] = v }
        if let v = changes.genre { comments["GENRE"] = v }
        if let v = changes.track { comments["TRACKNUMBER"] = v }
        if let v = changes.year { comments["DATE"] = v }
        if let v = changes.comment { comments["COMMENT"] = v }
    }
}
