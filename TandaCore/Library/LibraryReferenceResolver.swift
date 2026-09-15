//
//  LibraryReferenceResolver.swift
//  TandaComposer
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


// MARK: - Library Reference Resolver
//
// The one place that decides, for a single saved `Song` snapshot,
// "which current Library song is this, and has anything about it
// changed" — matching by id first (robust to the Library having
// relocated the file — same id, new path), falling back to
// `normalizedPath` only for legacy entries saved without an id.
//
// Previously this exact id-then-path lookup was reimplemented
// separately (and, for a while, inconsistently — some call sites had
// no path fallback at all) in SetlistStore.resolveAgainstLibrary,
// SetlistStore.previewRescan, TandaStore.previewRescan,
// SavedSetlistViewerStore.resolveAgainstLibrary, and
// SavedSetlistsRescanner.previewRescan. All five now call this
// instead, so "is this the same track, and is it current" has exactly
// one definition. What each of those five callers DOES with the
// result (write a status field, count it as a fix, list it as
// missing, ignore it) is still entirely up to them — this only
// answers the matching/diffing question, not the policy on top.

public enum LibraryReferenceResolver {

    /// The result of resolving one saved `Song` against the current
    /// Library. `live` is nil when the song couldn't be matched at
    /// all (no id match, and no path match either) — callers decide
    /// what that means for them (e.g. `.notInLibrary` for a live
    /// Setlist entry, "leave the saved snapshot as-is" for a saved
    /// Setlist file).
    public struct Resolution {
        public let live: Song?
        public let pathChanged: Bool
        public let isMissing: Bool
    }

    public static func resolve(
        _ song: Song,
        byID: [Int64: Song],
        byPath: [String: Song],
        missingSongIDs: Set<Int64>,
        trustID: Bool = true
    ) -> Resolution {

        // When the caller has determined the saved ids don't belong
        // to the currently active TrackLibrary (a different, and
        // independently auto-incremented, database — see
        // SetlistMetadataExport.savedAgainstLibraryName), an id match
        // is coincidence, not identity, and would silently substitute
        // the WRONG song at this position. Falling straight through
        // to the path lookup avoids that; the path itself is exactly
        // as reliable across libraries as it always was.
        let live: Song? =
            (trustID ? song.id.flatMap { byID[$0] } : nil)
                ?? byPath[song.normalizedPath]

        guard let live else {

            return Resolution(
                live: nil,
                pathChanged: false,
                isMissing: false
            )
        }

        let isMissing =
            live.id.map {
                missingSongIDs.contains($0)
            } ?? false

        let pathChanged =
            live.path != song.path

        return Resolution(
            live: live,
            pathChanged: pathChanged,
            isMissing: isMissing
        )
    }
}
