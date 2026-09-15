//
//  SavedSetlistsRescanner.swift
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


// MARK: - Saved Setlists Rescanner
//
// Option-C counterpart to SavedSetlistViewerStore's in-memory-only fix
// (option A, already applied): where that one keeps a currently-OPEN
// saved Setlist's *display* current without touching its file, this
// rescans every saved Setlist FILE on disk and rewrites the ones whose
// stored paths have drifted from the Library — same "scan (read-only)
// → preview → Apply Fixes → only Apply writes" shape as
// LibraryScanner.rescanLibrary and TandaStore.previewRescan/
// applyRescan, just operating on Setlist JSON files instead of Tanda
// JSON files or DB rows.
//
// Deliberately NOT a class that keeps every saved Setlist loaded in
// memory the way TandaStore keeps `tandas` — saved Setlists aren't
// otherwise needed all-at-once elsewhere in the app, so this loads
// each file fresh at scan time and discards it again once the preview
// is built.


/// One saved Setlist file a rescan looked at — a preview, computed by
/// `SavedSetlistsRescanner.previewRescan`. Nothing is written to disk
/// until this is handed to `applyRescan`, and `applyRescan` itself
/// only writes when `fixedSongCount > 0` — a Setlist that only has
/// `missingSongTitles` (no path drift, just a file that's currently
/// gone) has nothing in it worth rewriting, since there's no status
/// field in the saved file format to update; it's reported so the
/// user knows, not so the file gets touched.
public struct SavedSetlistRescanFix {
    public let name: String
    public let url: URL
    public let updatedSongs: [Song]
    public let fixedSongCount: Int
    /// Titles of songs matched in the Library (by id or, for legacy
    /// entries, by path) but currently missing on disk there — i.e.
    /// `LibraryStore.missingSongIDs` — regardless of whether their
    /// path also needed fixing. Informational only; nothing is
    /// written for these beyond whatever `fixedSongCount` already
    /// covers.
    public let missingSongTitles: [String]
}


/// Result of a `SavedSetlistsRescanner.applyRescan` run.
public struct SavedSetlistRescanSummary {
    public var fixedReferenceCount = 0
    public var updatedSetlistCount = 0
    /// Carried over from the applied fixes' `missingSongTitles`, for
    /// a single end-of-run message — still nothing was written for
    /// these, see `SavedSetlistRescanFix.missingSongTitles`.
    public var missingReferenceCount = 0
    public var failedWrites: [(url: URL, error: Error)] = []
}


public enum SavedSetlistsRescanner {

    /// Read-only: diffs every saved Setlist file's songs against the
    /// Library and returns what a rescan found — path drifts a rescan
    /// WOULD fix, plus (informational, not written) tracks whose file
    /// is currently missing per `LibraryStore.missingSongIDs`. Doesn't
    /// touch any file. Setlists that fail to load (corrupt/unreadable
    /// file) are silently skipped, same as a missing Tanda file would
    /// be — this is a best-effort sweep, not a validator.
    ///
    /// Matches by Library id first; for legacy entries saved without
    /// one, falls back to `normalizedPath` — same two-step lookup
    /// `SavedSetlistViewerStore.resolveAgainstLibrary` already uses
    /// for display, so a Setlist opened for viewing and this rescan
    /// agree on which songs are the same track.
    public static func previewRescan(
        byID: [Int64: Song],
        byPath: [String: Song],
        missingSongIDs: Set<Int64>
    ) -> [SavedSetlistRescanFix] {

        let names =
            (try? PlaylistStore.listPlaylistNamesOnDisk()) ?? []

        var fixes: [SavedSetlistRescanFix] = []

        for name in names {

            let url =
                PlaylistStore.fileURLOnDisk(forName: name)

            guard
                let export =
                    try? SetlistMetadataExporter.load(from: url)
            else {
                continue
            }

            var fixedSongCount = 0
            var missingSongTitles: [String] = []

            let trustID =
                export.savedAgainstLibraryName == AppPaths.currentLibraryName

            let updatedSongs: [Song] =
                export.songs.map { song in

                    let resolution =
                        LibraryReferenceResolver.resolve(
                            song,
                            byID: byID,
                            byPath: byPath,
                            missingSongIDs: missingSongIDs,
                            trustID: trustID
                        )

                    guard let live = resolution.live else {
                        return song
                    }

                    if resolution.isMissing {

                        missingSongTitles.append(
                            live.title ?? live.filename
                        )
                    }

                    guard resolution.pathChanged else {
                        return song
                    }

                    fixedSongCount += 1

                    return live
                }

            guard fixedSongCount > 0 || !missingSongTitles.isEmpty else {
                continue
            }

            fixes.append(
                SavedSetlistRescanFix(
                    name: name,
                    url: url,
                    updatedSongs: updatedSongs,
                    fixedSongCount: fixedSongCount,
                    missingSongTitles: missingSongTitles
                )
            )
        }

        return fixes
    }


    /// Commits a previously-computed set of `SavedSetlistRescanFix`es
    /// — rewrites each affected Setlist's JSON file on disk, but only
    /// where `fixedSongCount > 0`; a fix that's purely
    /// `missingSongTitles` has nothing to write (see
    /// `SavedSetlistRescanFix`) and is only folded into
    /// `missingReferenceCount` for the summary. A write failure for
    /// one file doesn't stop the others; it's recorded in
    /// `failedWrites` instead (mirrors `TandaStore.applyRescan`).
    @discardableResult
    public static func applyRescan(
        _ fixes: [SavedSetlistRescanFix]
    ) -> SavedSetlistRescanSummary {

        var summary = SavedSetlistRescanSummary()

        guard !fixes.isEmpty else {
            return summary
        }

        for fix in fixes {

            summary.missingReferenceCount += fix.missingSongTitles.count

            guard fix.fixedSongCount > 0 else {
                continue
            }

            do {

                try SetlistMetadataExporter.export(
                    songs: fix.updatedSongs,
                    playlistName: fix.name,
                    to: fix.url
                )

                summary.fixedReferenceCount += fix.fixedSongCount
                summary.updatedSetlistCount += 1

            } catch {

                summary.failedWrites.append(
                    (url: fix.url, error: error)
                )
            }
        }

        return summary
    }
}
