//
//  TagWriter.swift
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

enum TagWriteError: Error, CustomStringConvertible {
    case unsupportedFormat
    case noChangesSpecified
    case underlying(String)

    var description: String {
        switch self {
        case .unsupportedFormat: return "This file's format doesn't support writing yet."
        case .noChangesSpecified: return "No tag changes were specified."
        case .underlying(let msg): return "Write failed: \(msg)"
        }
    }
}

/// Format-independent set of tags audiotag4 can write. Each writer maps
/// these onto its own container's native fields (Vorbis comments for FLAC,
/// ID3v2 frames for MP3, iTunes atoms for MP4-family).
public struct TagChanges {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var genre: String?
    public var track: String?
    public var year: String?
    public var comment: String?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        track: String? = nil,
        year: String? = nil,
        comment: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.track = track
        self.year = year
        self.comment = comment
    }

    public var isEmpty: Bool {
        title == nil && artist == nil && album == nil
            && genre == nil && track == nil && year == nil && comment == nil
    }
}

protocol TagWriter {
    static func canHandle(format: AudioFormat) -> Bool
    static func write(url: URL, changes: TagChanges) async throws
    static func strip(url: URL) async throws
}

public enum TagWriterKit {
    static let writers: [TagWriter.Type] = [FLACWriter.self, ID3Writer.self, MP4TagWriter.self, AIFFWriter.self]

    static func writer(for url: URL) throws -> TagWriter.Type {
        let format = FormatSniffer.detect(url: url)
        guard let match = writers.first(where: { $0.canHandle(format: format) }) else {
            throw TagWriteError.unsupportedFormat
        }
        return match
    }

    public static func write(url: URL, changes: TagChanges) async throws {
        guard !changes.isEmpty else { throw TagWriteError.noChangesSpecified }
        try BackupUtility.backupOriginalIfNeeded(for: url)
        let writer = try writer(for: url)
        try await writer.write(url: url, changes: changes)
    }

    public static func strip(url: URL) async throws {
        try BackupUtility.backupOriginalIfNeeded(for: url)
        let writer = try writer(for: url)
        try await writer.strip(url: url)
    }
}
