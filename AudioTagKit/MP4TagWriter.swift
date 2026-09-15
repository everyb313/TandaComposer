//
//  MP4TagWriter.swift
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

/// Writes iTunes-style metadata atoms for M4A/AAC/ALAC via a passthrough
/// export — re-muxes the container with new metadata without re-encoding
/// audio, so there's no quality loss and it's fast even for long files.
struct MP4TagWriter: TagWriter {

    static func canHandle(format: AudioFormat) -> Bool { format == .mp4Family }

    static func write(url: URL, changes: TagChanges) async throws {
        let asset = AVURLAsset(url: url)
        var items = try await asset.load(.metadata) // all formats combined, so untouched items (e.g. artwork) survive

        setOrReplace(&items, key: .iTunesMetadataKeySongName, value: changes.title)
        setOrReplace(&items, key: .iTunesMetadataKeyArtist, value: changes.artist)
        setOrReplace(&items, key: .iTunesMetadataKeyAlbum, value: changes.album)
        setOrReplace(&items, key: .iTunesMetadataKeyUserGenre, value: changes.genre)
        setOrReplace(&items, key: .iTunesMetadataKeyTrackNumber, value: changes.track)
        setOrReplace(&items, key: .iTunesMetadataKeyReleaseDate, value: changes.year)
        setOrReplace(&items, key: .iTunesMetadataKeyUserComment, value: changes.comment)

        try await export(asset: asset, metadata: items, to: url)
    }

    static func strip(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        try await export(asset: asset, metadata: [], to: url)
    }

    private static func setOrReplace(_ items: inout [AVMetadataItem], key: AVMetadataKey, value: String?) {
        guard let value else { return }
        items.removeAll { $0.keySpace == .iTunes && ($0.key as? String) == key.rawValue }

        let item = AVMutableMetadataItem()
        item.keySpace = .iTunes
        item.key = key.rawValue as NSString
        item.value = value as NSString
        items.append(item)
    }

    private static func export(asset: AVURLAsset, metadata: [AVMetadataItem], to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw TagWriteError.underlying("could not create export session for \(url.lastPathComponent)")
        }

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        session.metadata = metadata

        do {
            // macOS 15+ async export API — supersedes the deprecated
            // exportAsynchronously/status/error trio and sidesteps the
            // non-Sendable-capture warning that came with wrapping
            // AVAssetExportSession in a CheckedContinuation closure.
            try await session.export(to: tempURL, as: outputFileType(for: url))
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw TagWriteError.underlying(error.localizedDescription)
        }

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    private static func outputFileType(for url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "m4a", "m4b", "m4p": return .m4a
        default: return .mp4
        }
    }
}
