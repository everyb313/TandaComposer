//
//  RescanSummary.swift
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

public enum ImportError: Error {
    /// The import completed, but some files couldn't be read. Carries
    /// each failing file's URL and the underlying error so the UI can
    /// show something more useful than "import failed."
    case partialFailure([(url: URL, error: Error)])
}


/// One relocated track — the Song's updated data plus the path it
/// used to live at, so a results view/report can show "moved from X".
public struct RelocatedTrack {
    public let oldPath: String
    public let song: Song
}


/// Result of a `LibraryScanner.rescanLibrary(scope:)` run.
public struct RescanSummary {

    /// File still present, filesystem mod-date/size unchanged since the
    /// last scan — only `lastLibraryScan` was updated, no re-read. Not
    /// listed individually (nothing interesting per-file to show),
    /// just a count.
    public var unchangedCount = 0

    /// File still present, but mod-date/size differed from the last
    /// scan — metadata and hash were re-read and the row updated.
    public var updatedSongs: [Song] = []

    /// File no longer found at its known path during this run. NOT
    /// persisted anywhere (per design: live/session-only, same spirit
    /// as LibraryStore's existing missingSongIDs) — used only within
    /// this same rescan to try matching against newly-found files by
    /// hash (see `relocatedTracks`).
    public var missingSongs: [Song] = []

    /// A file found on disk that didn't match any known path and
    /// didn't match any missing track's hash either — imported as a
    /// genuinely new Song.
    public var newlyImportedSongs: [Song] = []

    /// A file found on disk that didn't match any known path, but DID
    /// match a track that went missing earlier in this same run by
    /// content hash — treated as a move: the existing Song's path was
    /// updated in place rather than creating a duplicate row.
    public var relocatedTracks: [RelocatedTrack] = []

    /// Files that failed to read (corrupt, permissions, etc.) during
    /// either the "changed" re-read pass or the "new file" import pass.
    public var failedReads: [(url: URL, error: Error)] = []

    /// Rows whose files were unchanged on disk (same mod-date/size) but
    /// still need `lastLibraryScan` bumped. Not shown to the user (see
    /// `unchangedCount` below) — carried here only so `applyRescan(_:)`
    /// can write them once the user approves the rescan.
    public var unchangedSongsToRefresh: [Song] = []


    public var updatedCount: Int { updatedSongs.count }
    public var missingCount: Int { missingSongs.count }
    public var newlyImportedCount: Int { newlyImportedSongs.count }
    public var relocatedCount: Int { relocatedTracks.count }

    /// Whether applying this summary would change anything *meaningful*
    /// in the Library — used to skip the confirmation step when a
    /// rescan comes back completely clean. Deliberately excludes
    /// `unchangedSongsToRefresh`: that's just a `lastLibraryScan`
    /// timestamp bump on files that were already fine, present on
    /// essentially every scan, and not something a user should ever
    /// need to review or confirm — see `startRescan()` in
    /// RescanLibraryView, which writes that housekeeping refresh
    /// silently instead of prompting for it.
    public var hasChangesToApply: Bool {
        !updatedSongs.isEmpty ||
        !relocatedTracks.isEmpty ||
        !newlyImportedSongs.isEmpty
    }
}

@MainActor
public enum RescanPhase {
    case checkingKnownFiles
    case checkingForNewFiles

    public var label: String {
        switch self {
        case .checkingKnownFiles:
            return "Checking missing and updated references"
        case .checkingForNewFiles:
            return "Checking for relocated and newly added files"
        }
    }
}
