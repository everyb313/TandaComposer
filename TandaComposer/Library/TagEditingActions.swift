//
//  TagEditingActions.swift
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

// No `import AudioTagKit` — like LibraryScanner.swift elsewhere in the
// project, AudioTagKit's files are compiled directly into this target
// rather than pulled in as a separate module, so its types (TagChanges,
// TagWriterKit, ...) are already visible here without one.

/// Bridges the "Edit Tags…" sheet to the two halves of a tag edit that
/// otherwise have no reason to know about each other: the actual audio
/// file (via AudioTagKit's TagWriterKit) and the app's own cached copy
/// of that song (via LibraryStore). Writing only one of the two would
/// leave them silently out of sync until the next full Rescan — the
/// same class of problem the Tanda side already solved once (see
/// TandaStore's addSongs/removeSong writing the file, then updating
/// the in-memory Tanda to match).
///
/// File first, then the cached row second — same ordering as every
/// other "edit something, then persist it" flow in this app. Writing
/// the file first also means TagWriterKit's own automatic backup
/// (BackupUtility.backupOriginalIfNeeded) has already run before
/// LibraryStore is touched at all.
enum TagEditingActions {

    /// Writes `changes` to every one of `songs`' underlying files, then
    /// applies the SAME values to their cached Library rows in one
    /// batch. A song whose file write fails is skipped for the DB
    /// update too (its file — and therefore its displayed tags — is
    /// simply unchanged, not left half-updated), but doesn't block the
    /// rest of the batch: one locked or missing file during a
    /// multi-track edit shouldn't undo everything else that DID
    /// succeed.
    ///
    /// Returns the filenames whose file write failed — empty means
    /// every song in `songs` was fully updated, file and cache alike.
    @discardableResult
    static func apply(
        _ changes: TagChanges,
        to songs: [Song],
        libraryStore: LibraryStore
    ) async -> [String] {

        guard !changes.isEmpty else {
            return []
        }

        var failedFilenames: [String] = []
        var succeededIDs: Set<Int64> = []

        for song in songs {

            do {

                try await TagWriterKit.write(
                    url: URL(fileURLWithPath: song.path),
                    changes: changes
                )

                if let id = song.id {
                    succeededIDs.insert(id)
                }

            } catch {

                failedFilenames.append(song.filename)
            }
        }

        guard !succeededIDs.isEmpty else {
            return failedFilenames
        }

        do {

            try libraryStore.updateSongTags(
                ids: succeededIDs,
                title: changes.title,
                artist: changes.artist,
                albumArtist: changes.albumArtist,
                genre: changes.genre,
                year: changes.year.flatMap(Int.init),
                comment: changes.comment
            )

        } catch {

            // The files themselves are already correct at this point —
            // only the cached DB rows failed to refresh. Not folded
            // into failedFilenames: those specific songs' FILES did
            // not fail, only LibraryStore's own reload did, and a
            // later Rescan (or simply relaunching) will pick the
            // correct values back up from disk regardless. Not silent
            // either — surfaced separately so the caller can still
            // tell the user something's off.
            failedFilenames.append(
                "(Library display may be stale until the next Rescan — \(error.localizedDescription))"
            )
        }

        return failedFilenames
    }
}
