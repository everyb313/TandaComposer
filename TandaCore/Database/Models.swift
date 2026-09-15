//
//  Models.swift
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
import GRDB

/// One imported track. `path` is the on-disk source of truth; `normalizedPath`
/// (Unicode-canonicalized) is what duplicate-detection and lookups should
/// use, since the same file can arrive with differently-encoded accented
/// characters depending on how it was created (see TandaKit.PathNormalizer).
///
/// `bpm`/`key`/`year` are populated on a best-effort basis. "key" is tagged
/// inconsistently across real-world libraries (different DJ tools disagree
/// on convention) and always `nil` today. "year" works for FLAC/AIFF/M4A
/// but not yet MP3 (a known AudioTagKit gap — MP3's modern TDRC date frame
/// isn't checked yet, only the older TYER). Treat `nil` as "not available,"
/// not "silently wrong."
public struct Song: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public var id: Int64?
    public var filename: String
    public var path: String
    public var normalizedPath: String
    public var title: String?
    public var artist: String?
    public var albumArtist: String? // AudioTagKit's CanonicalTags.albumArtist — commonly repurposed by tango taggers as "Singer" (orchestra goes in artist, vocalist here)
    public var genre: String?
    public var grouping: String?  // AudioTagKit's CanonicalTags.grouping — Vorbis GROUPING / ID3 TIT1
    public var year: Int?         // recording year; parsed from whatever the tag's date field contains (see LibraryScanner)
    public var comment: String?   // AudioTagKit's CanonicalTags.comment — Vorbis COMMENT / ID3 COMM
    public var fileType: String? = nil  // file extension, uppercased (FLAC/MP3/M4A/AIFF/...) — derived from the path, not a tag
    public var duration: Int?     // seconds; currently nil for FLAC/AIFF — see LibraryScanner
    public var sampleRate: Int? = nil   // Hz (e.g. 44100); best-effort, see LibraryScanner.extractSampleRate
    public var replayGain: Double? = nil // dB, R128/ReplayGain track gain; best-effort, see LibraryScanner.extractReplayGain
    public var album: String?
    public var key: String?
    public var bpm: Double?
    public var fileSize: Int64?
    public var lastModified: Int? // unix timestamp, for change detection on rescan

    // MARK: - Library Tracking

    /// Date/time when this track was first added to the Track Library.
    public var addedToLibrary: Date = Date()

    /// Date/time when this track was last inspected by a Library scan.
    public var lastLibraryScan: Date = Date()

    /// Filesystem modification date observed during the last Library scan.
    public var fileModificationDateAtScan: Date = Date()

    /// Filesystem size observed during the last Library scan.
    public var fileSizeAtScan: Int64 = 0

    /// SHA-256 hash of the complete file contents.
    ///
    /// This identifies the exact file contents independently of its path.
    /// It is calculated when a file is first added to the library.
    public var fileHash: String? = nil


    public static let databaseTableName = "songs"

    public mutating func didInsert(
        _ inserted: InsertionSuccess
    ) {
        id = inserted.rowID
    }
}


/// One "Add Files" import, recorded so a Library's dependence on an
/// external volume can be checked cheaply later (compare
/// `volumeUUID`s against currently mounted volumes) instead of
/// having to stat every song file.
public struct ImportSource: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public var id: Int64?
    public var path: String          // folder path at import time
    public var volumeUUID: String?   // stable across remounts; nil if it couldn't be determined
    public var volumeName: String?   // display only — NOT used for matching, since it isn't stable
    public var importedAt: Date

    public static let databaseTableName = "import_sources"

    public mutating func didInsert(
        _ inserted: InsertionSuccess
    ) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        path: String,
        volumeUUID: String?,
        volumeName: String?,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.volumeUUID = volumeUUID
        self.volumeName = volumeName
        self.importedAt = importedAt
    }
}


// NOTE: The `Playlist` / `PlaylistSong` GRDB models that used to back
// the `playlists` / `playlist_songs` tables were removed here — Setlists
// are stored as JSON now (see PlaylistStore), so nothing in the app
// reads or writes those two structs anymore. The underlying SQLite
// tables are intentionally left in place (see DatabaseManager) since
// they're part of the migration history of every existing library
// file; only the now-unused Swift models were deleted.
