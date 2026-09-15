//
//  SavedSetlistViewerStore.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 26.08.26.
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
import Combine


// MARK: - Saved Setlist Viewer Store
//
// Loads a saved Setlist's songs, in their saved order, for read-only
// display in the "Setlist" library mode. Deliberately NOT the same as
// PlaylistStore.load(playlistName:) — that REPLACES the live, actively-
// edited Setlist (the Set column). This store is entirely separate, so
// browsing another saved Setlist never touches the one currently being
// worked on.

final class SavedSetlistViewerStore:
    ObservableObject {

    @Published
    private(set) var setlistName:
        String?

    @Published
    private(set) var songs:
        [Song] = []

    /// Mirrors `SetlistMetadataExport.savedAgainstLibraryName` for the
    /// currently loaded file — `resolveAgainstLibrary` below compares
    /// this against `AppPaths.currentLibraryName` to decide whether
    /// this file's song ids can be trusted at all.
    @Published
    private(set) var savedAgainstLibraryName:
        String?


    /// Loads `name` from `AppPaths.playlistsFolder/<name>.json` (the
    /// same file format/location PlaylistStore itself saves to), in
    /// its saved order — no sorting, this view always shows the actual
    /// saved sequence.
    ///
    /// `byID`/`missingSongIDs` are optional so existing call sites
    /// keep compiling — but when supplied, the loaded songs are
    /// immediately re-resolved against the current Library (see
    /// `resolveAgainstLibrary` below), so display/playback use the
    /// current on-disk path rather than whatever was saved in this
    /// Setlist's JSON at save time.
    func load(
        name:
            String,
        byID:
            [Int64: Song]? = nil,
        byPath:
            [String: Song] = [:],
        missingSongIDs:
            Set<Int64> = []
    ) throws {

        let url =
            AppPaths.playlistsFolder
                .appendingPathComponent(
                    name
                )
                .appendingPathExtension(
                    "json"
                )

        let export =
            try SetlistMetadataExporter.load(
                from:
                    url
            )

        self.setlistName =
            export.playlistName

        self.songs =
            export.songs

        self.savedAgainstLibraryName =
            export.savedAgainstLibraryName

        if let byID {

            resolveAgainstLibrary(
                byID:
                    byID,
                byPath:
                    byPath,
                missingSongIDs:
                    missingSongIDs
            )
        }
    }


    /// Re-derives each loaded song's live Library data in place —
    /// mirrors `SetlistStore.resolveAgainstLibrary`, but simpler since
    /// this store has no per-entry status to track, only the plain
    /// `Song` values used for display and Play. Matches by id first —
    /// unless `savedAgainstLibraryName` says these ids belong to a
    /// DIFFERENT TrackLibrary than the one currently active, in which
    /// case an id match would be coincidence, not identity, and this
    /// falls straight through to matching by path instead (see
    /// `LibraryReferenceResolver`'s `trustID` parameter). A song no
    /// longer found in the Library at all is left as its saved
    /// snapshot — Play will then correctly report "File not found"
    /// rather than silently vanishing from the list.
    ///
    /// Call this whenever the Library's songs/missing-set change while
    /// a saved Setlist is open for viewing, the same way `PlaylistView`
    /// re-resolves the live Set — otherwise a Setlist opened before a
    /// Library rescan would keep showing/playing the pre-rescan paths
    /// until reloaded. `byID`/`byPath` come from `LibraryStore`'s own
    /// cache (`songsByID`/`songsByNormalizedPath`) — built once there
    /// whenever `songs` changes, rather than rebuilt here on every
    /// call.
    func resolveAgainstLibrary(
        byID:
            [Int64: Song],
        byPath:
            [String: Song],
        missingSongIDs:
            Set<Int64>
    ) {

        let trustID =
            savedAgainstLibraryName == AppPaths.currentLibraryName

        songs =
            songs.map { song in

                LibraryReferenceResolver.resolve(
                    song,
                    byID: byID,
                    byPath: byPath,
                    missingSongIDs: missingSongIDs,
                    trustID: trustID
                ).live ?? song
            }
    }


    func clear() {

        setlistName =
            nil

        songs =
            []

        savedAgainstLibraryName =
            nil
    }
}
