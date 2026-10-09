//
//  TandaSaver.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 25.08.26.
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

// MARK: - Tanda Saver
//
// Single shared entry point for turning a set of songs into a saved
// Tanda file. Used by:
//   - SetlistView.saveTanda() (the "Save Tanda" button)
//   - TandaLibraryView's Setlist-drag-and-drop (see onDrop)
// so both stay byte-for-byte identical in validation, naming, and
// folder placement — no risk of the two drifting apart.
//

enum TandaSaver {

    /// Validates, resolves the target folder/filename, exports, and
    /// posts `.tandaSaved` on success. Throws `TandaSaveError` for a
    /// 3-8 track violation, a duplicate, a missing-on-disk track, or a
    /// FileManager/export error otherwise.
    @discardableResult
    static func save(
        songs:
            [Song],
        existingTandas:
            [Tanda] = [],
        missingSongIDs:
            Set<Int64> = [],
        settings:
            AppSettings
    ) throws -> URL {

        guard
            songs.count >= 3
        else {

            throw TandaSaveError.tooFewTracks(
                songs.count
            )
        }

        guard
            songs.count <= 8
        else {

            throw TandaSaveError.tooManyTracks(
                songs.count
            )
        }


        // A Tanda saved with a track that's missing on disk would be
        // unplayable from the moment it's created — reject it up
        // front instead of producing a red-dotted Tanda the user then
        // has to notice and undo. Checked by id against the CURRENT
        // Library, same source of truth as every other Status dot.
        let missingTitles =
            songs.compactMap { song -> String? in

                guard
                    let id = song.id,
                    missingSongIDs.contains(id)
                else {
                    return nil
                }

                return song.title ?? song.filename
            }

        guard missingTitles.isEmpty else {

            throw TandaSaveError.containsMissingTracks(
                titles: missingTitles
            )
        }


        // Duplicate check — same set of tracks already saved
        // somewhere in the Tanda library, regardless of order.
        // Compared by normalizedPath (stable file identity) rather
        // than song.id, since id is Optional and only meaningful
        // within a single Library.
        let newPaths =
            Set(
                songs.map {
                    $0.normalizedPath
                }
            )

        if let existingMatch =
            existingTandas.first(where: { tanda in

                Set(tanda.songs.map { $0.normalizedPath }) == newPaths
            }) {

            throw TandaSaveError.duplicateTanda(
                existingName:
                    existingMatch.name
            )
        }


        // Artist/Genre/AlbumArtist are each resolved across ALL tracks
        // in the Tanda, not just the first — if they don't all agree,
        // that field falls back to "Various...".
        let fields =
            resolvedFields(
                for:
                    songs,
                settings:
                    settings
            )


        // Subdirectory is Tandas/<Artist>/<AlbumArtist>/, both
        // RESOLVED AND NORMALIZED. Physical nesting — not a virtual/
        // faked display grouping — so TandaFolderTree, TandaStore.
        // reload(), and TandaLibraryView's folder filter (which
        // already matches by path prefix) pick this up with no
        // further changes.
        let tandaFolder =
            try ensureTandaFolder(
                forArtist:
                    fields.artist,
                albumArtist:
                    fields.albumArtist
            )


        // Suggested name uses NORMALIZED names for all components.
        let tandaName =
            suggestedName(
                fields:
                    fields,
                availableIn:
                    tandaFolder
            )


        let fileURL =
            tandaFolder
                .appendingPathComponent(
                    tandaName,
                    isDirectory:
                        false
                )
                .appendingPathExtension(
                    "json"
                )


        try TandaMetadataExporter.export(
            songs:
                songs,
            tandaName:
                tandaName,
            to:
                fileURL
        )


        NotificationCenter.default.post(
            name:
                AppNotification.tandaSaved,
            object:
                nil
        )


        return fileURL
    }


    // MARK: - Folder

    struct ResolvedFields {

        let artist:
            String

        let genre:
            String

        let albumArtist:
            String
    }


    /// Ensures (creating if necessary) and returns the
    /// `Tandas/<Artist>/<AlbumArtist>/` subdirectory a Tanda should be
    /// saved into.
    ///
    /// Both components are normalized for filesystem use the same
    /// way:
    ///
    ///     "Rodríguez" -> "Rodriguez"
    ///     "Carlos Dí Sarli" -> "Carlos Di Sarli"
    ///
    /// Capitalization is preserved. No special-casing for the
    /// "unknownArtist" fallback (see `resolvedField`'s
    /// `unknownFallback` argument in `resolvedFields(for:)`) — it's
    /// just another string value and goes through the identical
    /// normalization/folder-creation path as a real AlbumArtist name,
    /// same as `VariousSingers`.
    private static func ensureTandaFolder(
        forArtist artist:
            String,
        albumArtist:
            String
    ) throws -> URL {

        let folder =
            tandaFolderURL(
                forArtist: artist,
                albumArtist: albumArtist
            )

        try FileManager.default.createDirectory(
            at:
                folder,
            withIntermediateDirectories:
                true
        )


        return folder
    }


    /// Pure path computation — no directory creation, no disk access.
    /// Split out of `ensureTandaFolder` so `resolvedLocation(for:
    /// settings:excluding:)` (used read-only by Rescan TandaLibrary,
    /// see below) can compute where a Tanda WOULD live without
    /// creating anything.
    private static func tandaFolderURL(
        forArtist artist:
            String,
        albumArtist:
            String
    ) -> URL {

        let artistFolderName =
            normalizedFileNameComponent(
                commaTruncated(
                    artist
                )
            )

        let albumArtistFolderName =
            normalizedFileNameComponent(
                commaTruncated(
                    albumArtist
                )
            )


        return AppPaths.tandasFolder
            .appendingPathComponent(
                artistFolderName,
                isDirectory:
                    true
            )
            .appendingPathComponent(
                albumArtistFolderName,
                isDirectory:
                    true
            )
    }


    /// `"Biagi, Rodolfo"` -> `"Biagi"`.
    ///
    /// If `value` contains a comma, only the part before the FIRST
    /// comma is used (trimmed).
    static func commaTruncated(
        _ value:
            String
    ) -> String {

        guard
            let commaIndex =
                value.firstIndex(
                    of:
                        ","
                )
        else {

            return value
        }


        return String(
            value[
                value.startIndex
                ..<
                commaIndex
            ]
        )
        .trimmingCharacters(
            in:
                .whitespacesAndNewlines
        )
    }


    // MARK: - Resolved Location (read-only, for Rescan)
    //
    // Computes where a Tanda with these songs WOULD be saved/named
    // right now — same resolution `save(...)` itself uses — WITHOUT
    // creating any folder or writing anything. Used by TandaStore's
    // Rescan TandaLibrary to detect when an existing Tanda's saved
    // name/folder has drifted from what its CURRENT songs resolve to
    // (e.g. after a track was added/removed and the Orchestra/Singer
    // mix changed). Not `private` — this is the one entry point
    // TandaStore (a different file/type) is meant to call; everything
    // it depends on internally stays private to this enum.
    //
    // `excludingURL` should be the Tanda's own current file, so an
    // unchanged Tanda's collision check never collides with itself
    // (see `firstAvailableName`'s `excluding` parameter).

    static func resolvedLocation(
        for songs:
            [Song],
        settings:
            AppSettings,
        excluding excludingURL:
            URL? = nil
    ) -> (folder: URL, name: String) {

        let fields =
            resolvedFields(
                for: songs,
                settings: settings
            )

        let folder =
            tandaFolderURL(
                forArtist: fields.artist,
                albumArtist: fields.albumArtist
            )

        let name =
            suggestedName(
                fields: fields,
                availableIn: folder,
                excluding: excludingURL
            )

        return (folder, name)
    }
}
