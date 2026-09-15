//
//  ArtworkExtractor.swift
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
import AVFoundation
import ImageIO

public struct ExtractedArtwork {
    public let data: Data
    public let mimeType: String
    public let width: Int?
    public let height: Int?
}

public enum ArtworkExtractor {
    public static func extract(from url: URL) async throws -> ExtractedArtwork? {
        switch FormatSniffer.detect(url: url) {
        case .flac:
            return try extractFromFLAC(url: url)
        case .aiff:
            return try extractFromAIFF(url: url)
        default:
            return try await extractViaAVFoundation(url: url)
        }
    }

    // MARK: - AIFF (embedded ID3 "APIC" frame, via the shared ID3 codec)

    private static func extractFromAIFF(url: URL) throws -> ExtractedArtwork? {
        let data = try Data(contentsOf: url)
        let (_, chunks) = try AIFFChunks.parse(data)
        guard let id3Chunk = chunks.first(where: { $0.id == "ID3 " }) else { return nil }

        let frames = ID3FrameCodec.parseTag(id3Chunk.data)
        guard let apicFrame = frames.first(where: { $0.id == "APIC" }),
              let (mime, imageData) = ID3FrameCodec.decodePictureFrame(apicFrame.content) else {
            return nil
        }

        var width: Int?
        var height: Int?
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int
            height = props[kCGImagePropertyPixelHeight] as? Int
        }

        return ExtractedArtwork(data: imageData, mimeType: mime, width: width, height: height)
    }

    // MARK: - FLAC (hand-rolled PICTURE block parse)

    private static func extractFromFLAC(url: URL) throws -> ExtractedArtwork? {
        let data = try Data(contentsOf: url)
        let (blocks, _) = try FLACBlocks.parse(data)
        guard let pictureBlock = blocks.first(where: { $0.type == FLACBlocks.picture }) else {
            return nil
        }
        return try parsePictureBlock(pictureBlock.data)
    }

    private static func parsePictureBlock(_ block: Data) throws -> ExtractedArtwork {
        var i = block.startIndex
        func readUInt32BE() throws -> Int {
            guard i + 4 <= block.endIndex else { throw FLACParseError.truncated }
            let v = UInt32(block[i]) << 24 | UInt32(block[i + 1]) << 16
                  | UInt32(block[i + 2]) << 8 | UInt32(block[i + 3])
            i += 4
            return Int(v)
        }

        _ = try readUInt32BE() // picture type, not needed here

        let mimeLength = try readUInt32BE()
        guard i + mimeLength <= block.endIndex else { throw FLACParseError.truncated }
        let mime = String(decoding: block[i..<(i + mimeLength)], as: UTF8.self)
        i += mimeLength

        let descLength = try readUInt32BE()
        guard i + descLength <= block.endIndex else { throw FLACParseError.truncated }
        i += descLength // description text, not needed

        let width = try readUInt32BE()
        let height = try readUInt32BE()
        _ = try readUInt32BE() // color depth
        _ = try readUInt32BE() // number of colors used

        let dataLength = try readUInt32BE()
        guard i + dataLength <= block.endIndex else { throw FLACParseError.truncated }
        let pictureData = block.subdata(in: i..<(i + dataLength))

        return ExtractedArtwork(data: pictureData, mimeType: mime, width: width, height: height)
    }

    // MARK: - MP3 / M4A / AAC / ALAC (via AVFoundation's common artwork key)

    private static func extractViaAVFoundation(url: URL) async throws -> ExtractedArtwork? {
        let asset = AVURLAsset(url: url)
        let items = try await asset.load(.commonMetadata)
        guard let artworkItem = items.first(where: { $0.commonKey == .commonKeyArtwork }) else {
            return nil
        }
        guard let value = try await artworkItem.load(.value), let data = value as? Data else {
            return nil
        }

        let mime = sniffImageMIME(data)
        var width: Int?
        var height: Int?
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int
            height = props[kCGImagePropertyPixelHeight] as? Int
        }

        return ExtractedArtwork(data: data, mimeType: mime, width: width, height: height)
    }

    private static func sniffImageMIME(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: Array("GIF8".utf8)) { return "image/gif" }
        return "application/octet-stream"
    }
}
