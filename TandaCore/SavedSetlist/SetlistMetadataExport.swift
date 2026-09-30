//
//  SetlistMetadataExport.swift
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

// MARK: - Shared Song JSON serialization

/// Provides the canonical JSON representation of a Song.
///
/// Both Setlists and Tandas use exactly the same Song representation.
/// This prevents the two file formats from drifting apart over time.
///
/// Pure data type — never touches actor-isolated state, so marked
/// `nonisolated` for the same reason `JSONValue` is (see its doc
/// comment in OrderedJSON.swift): under this project's default
/// MainActor isolation, `orderedValue` would otherwise become
/// MainActor-isolated, which breaks passing it as a bare function
/// value to `.map(...)` (see SetlistMetadataExporter.export and
/// TandaMetadataExporter's analogous export) from a synchronous
/// nonisolated context.
public nonisolated enum SongMetadataJSON {

    /// Song fields in the exact order used by TandaComposer metadata files.
    ///
    /// This includes ALL Song properties, including Library Tracking data.
    public static func orderedValue(_ song: Song) -> JSONValue {
        .object([
            ("id", .opt(song.id)),
            ("filename", .string(song.filename)),
            ("path", .string(song.path)),
            ("normalizedPath", .string(song.normalizedPath)),
            ("title", .opt(song.title)),
            ("artist", .opt(song.artist)),
            ("albumArtist", .opt(song.albumArtist)),
            ("genre", .opt(song.genre)),
            ("grouping", .opt(song.grouping)),
            ("year", .opt(song.year)),
            ("comment", .opt(song.comment)),
            ("fileType", .opt(song.fileType)),
            ("duration", .opt(song.duration)),
            ("sampleRate", .opt(song.sampleRate)),
            ("replayGain", .opt(song.replayGain)),
            ("album", .opt(song.album)),
            ("key", .opt(song.key)),
            ("bpm", .opt(song.bpm)),
            ("fileSize", .opt(song.fileSize)),
            ("lastModified", .opt(song.lastModified)),

            // MARK: Library Tracking

            ("addedToLibrary", .string(
                iso8601String(song.addedToLibrary)
            )),

            ("lastLibraryScan", .string(
                iso8601String(song.lastLibraryScan)
            )),

            ("fileModificationDateAtScan", .string(
                iso8601String(song.fileModificationDateAtScan)
            )),

            ("fileSizeAtScan", .number(
                String(song.fileSizeAtScan)
            )),

            ("fileHash", .opt(song.fileHash))
        ])
    }


    /// Matches JSONEncoder's `.iso8601` encoding strategy.
    public static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}


// MARK: - Setlist metadata

/// File format for a TandaComposer Setlist.
///
/// Used both as the internal save/load format
/// (Playlists/<name>.json) and as the sidecar metadata
/// written next to an M3U8 export.
///
/// Contains the complete Song records for the Setlist,
/// including Library Tracking information.
public struct SetlistMetadataExport: Codable {

    public let format: String
    public let version: Int
    public let playlistName: String
    public let savedAt: Date
    public let songs: [Song]

    /// Which TrackLibrary this file's song `id`s were resolved
    /// against when it was last saved. `nil` for files saved before
    /// this field existed, or files copied in from elsewhere by hand
    /// — either way, `nil` (or a name that doesn't match the
    /// currently active library) means those ids can't be trusted:
    /// two independent libraries assign the same small integers to
    /// completely different songs, so an id match across libraries
    /// is coincidence, not identity. See `LibraryReferenceResolver`'s
    /// `trustID` parameter — this is what callers compare against
    /// `AppPaths.currentLibraryName` to decide it.
    public let savedAgainstLibraryName: String?

    public init(
        playlistName: String,
        songs: [Song],
        savedAt: Date = Date(),
        savedAgainstLibraryName: String? = AppPaths.currentLibraryName
    ) {
        self.format = "TandaComposer Setlist"
        self.version = 1
        self.playlistName = playlistName
        self.savedAt = savedAt
        self.songs = songs
        self.savedAgainstLibraryName = savedAgainstLibraryName
    }
}


// MARK: - Setlist exporter

public enum SetlistMetadataExporter {

    /// Exports the complete Song metadata for the songs
    /// contained in the current Setlist.
    ///
    /// ALL Song properties are written, including:
    ///
    /// - Library tracking dates
    /// - file size at scan
    /// - file hash
    ///
    /// The order of `songs` is preserved exactly as supplied.
    /// Duplicate songs are also preserved.
    public static func export(
        songs: [Song],
        playlistName: String,
        to fileURL: URL,
        savedAt: Date = Date(),
        savedAgainstLibraryName: String? = AppPaths.currentLibraryName
    ) throws {

        let export =
            SetlistMetadataExport(
                playlistName:
                    playlistName,
                songs:
                    songs,
                savedAt:
                    savedAt,
                savedAgainstLibraryName:
                    savedAgainstLibraryName
            )


        let doc =
            JSONValue.object([
                ("format", .string(export.format)),

                ("version", .number(
                    String(export.version)
                )),

                ("playlistName", .string(
                    export.playlistName
                )),

                ("savedAt", .string(
                    SongMetadataJSON.iso8601String(
                        export.savedAt
                    )
                )),

                ("savedAgainstLibraryName", .opt(
                    export.savedAgainstLibraryName
                )),

                ("songs", .array(
                    export.songs.map(
                        SongMetadataJSON.orderedValue
                    )
                ))
            ])


        guard
            let data =
                doc.serialized().data(
                    using:
                        .utf8
                )
        else {
            throw CocoaError(
                .fileWriteInapplicableStringEncoding
            )
        }


        try data.write(
            to:
                fileURL,
            options:
                .atomic
        )
    }


    /// Reads a previously exported/saved Setlist file back.
    ///
    /// The complete Song records are restored, including all Library
    /// Tracking properties.
    public static func load(
        from fileURL: URL
    ) throws -> SetlistMetadataExport {

        let data =
            try Data(
                contentsOf:
                    fileURL
            )


        let decoder =
            JSONDecoder()


        decoder.dateDecodingStrategy =
            .iso8601


        return try decoder.decode(
            SetlistMetadataExport.self,
            from:
                data
        )
    }
}
