//
//  TandaSaveError.swift
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


// MARK: - Tanda Save Error

enum TandaSaveError:
    LocalizedError {

    case tooFewTracks(Int)
    case tooManyTracks(Int)
    case duplicateTanda(existingName: String)
    case containsMissingTracks(titles: [String])

    /// Editing an existing Tanda (add/remove a track) would take it
    /// below the 3-track minimum. Distinct wording from `tooFewTracks`
    /// (which talks about the Setlist selection at creation time) —
    /// this one talks about the Tanda itself and points at the
    /// alternative (delete the whole Tanda).
    case wouldDropBelowMinimum(Int)

    var errorDescription:
        String? {

        switch self {

        case .tooFewTracks(let count):

            return "Please mark at least 3 tracks in the setlist for the Tanda (currently \(count))."

        case .tooManyTracks(let count):

            return "Please mark at most 8 tracks in the setlist for the Tanda (currently \(count))."

        case .duplicateTanda(let existingName):

            return "This Tanda (same tracks) already exists as \"\(existingName)\"."

        case .containsMissingTracks(let titles):

            let list =
                titles.joined(separator: ", ")

            return "Can't save a Tanda with track(s) missing on disk: \(list). Fix or remove them first."

        case .wouldDropBelowMinimum(let count):

            return "A Tanda needs at least 3 tracks (currently \(count)). Delete the whole Tanda instead if you want to remove it entirely."
        }
    }
}


// MARK: - Tanda Saver
//
// Single shared entry point for turning a set of songs into a saved
// Tanda file. Used by:
//   - PlaylistView.saveTanda() (the "Save Tanda" button)
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
                .tandaSaved,
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
    private static func commaTruncated(
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


    // MARK: Field Resolution

    private static func resolvedFields(
        for songs:
            [Song],
        settings:
            AppSettings
    ) -> ResolvedFields {

        ResolvedFields(

            artist:
                resolvedArtistField(
                    songs.map {
                        $0.resolvedOrchestra(using: settings)
                    }
                ),

            genre:
                resolvedField(
                    songs.map {
                        $0.genre
                    },
                    unknownFallback:
                        "Unknown Genre",
                    variousFallback:
                        "VariousGenres"
                ),

            albumArtist:
                resolvedField(
                    songs.map {
                        $0.resolvedSinger(using: settings)
                    },
                    unknownFallback:
                        // Also used as the Tandas/<Artist>/<...>/
                        // subfolder name (see ensureTandaFolder) —
                        // no special-casing there, so this value
                        // must itself already be filesystem-safe.
                        "unknownOrchestra",
                    variousFallback:
                        "VariousSingers"
                )
        )
    }


    // MARK: Artist Resolution
    //
    // Comparison remains case- and diacritic-insensitive.
    // The original artist string is returned unchanged.
    //
    // This is ONLY for determining whether all tracks have the
    // same artist.

    private static func resolvedArtistField(
        _ values:
            [String?]
    ) -> String {

        let cleanedValues =
            values.compactMap {
                value -> String? in

                let trimmed =
                    value?.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ) ?? ""

                return trimmed.isEmpty
                    ? nil
                    : trimmed
            }


        guard
            !cleanedValues.isEmpty
        else {

            return "Unknown Orchestra"
        }


        let normalizedValues =
            Set(
                cleanedValues.map {
                    normalizedArtistForComparison($0)
                }
            )


        // All artists are considered equal for Tanda generation.
        //
        // IMPORTANT:
        // Return the ORIGINAL artist string.
        // Normalization is applied only when creating the
        // filesystem folder and filename.
        if normalizedValues.count == 1 {

            return cleanedValues[0]
        }


        return "VariousOrchestras"
    }


    // MARK: Artist Comparison Normalization

    /// Used for comparing Artist (Orchestra) values, and also reused
    /// by `resolvedField` for Singer/AlbumArtist and Genre
    /// comparison (see "Generic Field Resolution" below).
    ///
    /// Case and diacritics are ignored here.
    ///
    ///     "Carlos Di Sarli"
    ///     "Carlos Dí Sarli"
    ///
    /// are therefore considered identical.

    private static func normalizedArtistForComparison(
        _ artist:
            String
    ) -> String {

        artist
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .folding(
                options:
                    [
                        .caseInsensitive,
                        .diacriticInsensitive
                    ],
                locale:
                    Locale(
                        identifier:
                            "es_ES"
                    )
            )
            .precomposedStringWithCanonicalMapping
    }


    // MARK: Generic Field Resolution
    //
    // Comparison is case- and diacritic-insensitive (same rule as
    // Artist Comparison Normalization above), so e.g. "Podestá" and
    // "Podesta", or "Tango" and "tango", are treated as the same
    // value instead of triggering the various* fallback. The
    // ORIGINAL string (first occurrence) is returned when all
    // values match, exactly like `resolvedArtistField`.

    private static func resolvedField(
        _ values:
            [String?],
        unknownFallback:
            String,
        variousFallback:
            String
    ) -> String {

        let cleanedValues =
            values.compactMap {
                value -> String? in

                let trimmed =
                    value?.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ) ?? ""

                return trimmed.isEmpty
                    ? nil
                    : trimmed
            }


        guard
            !cleanedValues.isEmpty
        else {

            return unknownFallback
        }


        let normalizedValues =
            Set(
                cleanedValues.map {
                    normalizedArtistForComparison($0)
                }
            )


        if normalizedValues.count == 1 {

            return cleanedValues[0]
        }


        return variousFallback
    }


    // MARK: Suggested Name
    //
    // <normalized Artist>_<normalized Genre>_<normalized AlbumArtist>
    //
    // IMPORTANT:
    // Diacritics are removed, but capitalization is preserved.
    //
    // Example:
    //
    //     Carlos Dí Sarli
    //     Tángo
    //     Carlos Di Sarli
    //
    // becomes:
    //
    //     Carlos Di Sarli_Tango_Carlos Di Sarli

    private static func suggestedName(
        fields:
            ResolvedFields,
        availableIn folder:
            URL,
        excluding excludedURL:
            URL? = nil
    ) -> String {

        let base =
            [
                normalizedFileNameComponent(
                    commaTruncated(
                        fields.artist
                    )
                ),

                normalizedFileNameComponent(
                    fields.genre
                ),

                normalizedFileNameComponent(
                    commaTruncated(
                        fields.albumArtist
                    )
                ),
            ]
            .joined(
                separator:
                    "_"
            )


        return firstAvailableName(
            base:
                base,
            in:
                folder,
            excluding:
                excludedURL
        )
    }


    // MARK: Filename / Folder Normalization
    //
    // THIS is the important part for Save.
    //
    // Unlike normalizedArtistForComparison(),
    // this function DOES NOT use .caseInsensitive.
    //
    // Therefore:
    //
    //     Rodríguez -> Rodriguez
    //     Tángo     -> Tango
    //     Carlos Dí Sarli -> Carlos Di Sarli
    //
    // while:
    //
    //     TANGO -> TANGO
    //     tango -> tango
    //     Tango -> Tango
    //
    // The original capitalization is preserved.

    private static func normalizedFileNameComponent(
        _ value:
            String
    ) -> String {

        let normalized =
            value
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .folding(
                    options:
                        [
                            .diacriticInsensitive
                        ],
                    locale:
                        Locale(
                            identifier:
                                "es_ES"
                        )
                )
                .precomposedStringWithCanonicalMapping


        return safeFileName(
            normalized
        )
    }


    // MARK: First Available Name

    /// `base` itself if `<base>.json` doesn't exist yet in `folder`;
    /// otherwise `<base>_2`, `<base>_3`, ... — the first ordinal whose
    /// file doesn't already exist.
    ///
    /// `excludedURL`, when given, is never treated as an existing
    /// collision — used by `resolvedLocation(for:settings:excluding:)`
    /// so a Tanda whose songs haven't actually changed doesn't
    /// collide with ITS OWN current file and get offered a pointless
    /// "_2" rename.

    private static func firstAvailableName(
        base:
            String,
        in folder:
            URL,
        excluding excludedURL:
            URL? = nil
    ) -> String {

        let excludedPath =
            excludedURL?.standardizedFileURL.path

        func exists(
            _ name:
                String
        ) -> Bool {

            let candidate =
                folder
                    .appendingPathComponent(
                        name,
                        isDirectory:
                            false
                    )
                    .appendingPathExtension(
                        "json"
                    )

            if candidate.standardizedFileURL.path
                == excludedPath {

                return false
            }

            return FileManager.default.fileExists(
                atPath:
                    candidate.path
            )
        }


        guard exists(base) else {

            return base
        }


        var ordinal = 2

        while exists(
            "\(base)_\(ordinal)"
        ) {

            ordinal += 1
        }


        return "\(base)_\(ordinal)"
    }


    // MARK: Safe Filename

    private static func safeFileName(
        _ name:
            String
    ) -> String {

        let trimmed =
            name.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )


        if trimmed.isEmpty {

            return "Untitled Tanda"
        }


        return trimmed
            .replacingOccurrences(
                of:
                    "/",
                with:
                    "-"
            )
            .replacingOccurrences(
                of:
                    ":",
                with:
                    "-"
            )
    }
}
