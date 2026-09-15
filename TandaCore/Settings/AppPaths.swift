//
//  AppPaths.swift
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

///
//  AppPaths.swift
//  TandaComposer
//

import Foundation

public enum AppPaths {

    static let appName = "TandaComposer"

    static let defaultLibraryName = "Default"


    // =============================================================
    // MARK: - Root
    // =============================================================

    /// The root for all TandaComposer data (DB, Setlists, Tandas,
    /// Smartlists, Settings): always `~/.TandaComposer`.
    ///
    /// TandaComposer used to also support an External (user-picked
    /// folder/drive) Location, switchable at runtime via Settings.
    /// That was removed — it needed security-scoped bookmarks, a
    /// sleep/USB-mount reconnect lifecycle, and a way to keep the
    /// database's actual Location in sync with what `root` resolved
    /// to, and each of those independently produced real bugs (stale
    /// cached roots surviving a switch, Setlist saves still targeting
    /// an unreachable drive after the DB itself fell back to
    /// Internal, Settings UI not reflecting an active fallback). None
    /// of that complexity is worth it for what External Location was
    /// actually for: keeping a backup / moving to another Mac — which
    /// "Export Backup…"/"Import Backup…" (LibraryActions.swift) now
    /// covers directly, as a zip of this whole folder, without ever
    /// needing TandaComposer to run against removable media.
    ///
    /// Music files themselves are unaffected by any of this — they
    /// can still live anywhere, internal or external drive; that's
    /// tracked per-track (Song.path) and handled by the existing
    /// status-dot/Rescan system, not by this root.
    static var root: URL {
        internalRoot
    }


    /// UserDefaults key for "the last active Setlist name". Used to
    /// be split per Internal/External Location (`LastPlaylist.
    /// Internal`/`.External`) — now there's only one Location, so
    /// back to a single key.
    static var lastPlaylistDefaultsKey: String {
        "LastPlaylist"
    }


    /// Permanent internal TandaComposer location.
    ///
    /// Lives directly in the user's home folder (not
    /// ~/Library/Application Support anymore), as a hidden
    /// dot-folder so it doesn't clutter the Finder view of ~
    /// alongside Documents/Desktop/etc.
    static var internalRoot: URL {

        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(
                ".\(appName)",
                isDirectory:
                    true
            )
    }


    // =============================================================
    // MARK: - Current TrackLibrary
    // =============================================================

    /// The name of the currently active TrackLibrary — the single
    /// piece of state that decides which subtree of `root` everything
    /// else in this file resolves against (see `libraryRoot` below).
    ///
    /// Kept as a plain static var rather than sourced fresh from
    /// `AppSettings` on every access: `AppSettings` is a `@MainActor`
    /// `ObservableObject` that itself isn't constructed yet at the
    /// point `TandaComposerApp.init()` needs to resolve paths for
    /// `AppEnvironment()`, and `AppPaths` — a plain static enum used
    /// from many non-isolated contexts — has no business depending on
    /// it directly anyway. `TandaComposerApp.init()` sets this from
    /// the loaded `AppSettings.currentLibraryName` before constructing
    /// `AppEnvironment()`; `LibraryStore`'s switch/create/reset
    /// methods update it from then on. Persisting the choice back to
    /// `AppSettings.json` is a separate, deliberate step the App-layer
    /// call sites (`LibraryActions`) take after a successful switch —
    /// not automatic here, since a plain static var can't itself own
    /// file I/O cleanly.
    public static var currentLibraryName: String = defaultLibraryName


    /// The active TrackLibrary's own subtree — its database file,
    /// Setlists, Smartlists, and Tandas all live under here. Switching
    /// `currentLibraryName` is what makes "switch TrackLibrary" also
    /// mean "switch which Setlists/Tandas/Smartlists are visible",
    /// with no per-item bookkeeping needed: the folder itself is the
    /// association.
    static var libraryRoot: URL {

        root.appendingPathComponent(
            currentLibraryName,
            isDirectory:
                true
        )
    }


    // =============================================================
    // MARK: - Main folders (all per-TrackLibrary)
    // =============================================================

    static var playlistsFolder: URL {

        libraryRoot.appendingPathComponent(
            "Setlists",
            isDirectory:
                true
        )
    }


    static var smartlistFolder: URL {

        libraryRoot.appendingPathComponent(
            "Smartlists",
            isDirectory:
                true
        )
    }


    /// `<root>/<library>/Tandas/` — previously computed ad hoc inside
    /// `TandaStore` as `AppPaths.root/Tandas`; centralized here now
    /// that it needs to move with the active TrackLibrary too.
    static var tandasFolder: URL {

        libraryRoot.appendingPathComponent(
            "Tandas",
            isDirectory:
                true
        )
    }


    // =============================================================
    // MARK: - App Settings (NOT per-TrackLibrary)
    // =============================================================

    /// `~/.TandaComposer/AppSettings.json` — deliberately a direct
    /// child of `root`, not of `libraryRoot`: it has to be readable
    /// before `currentLibraryName` is even known (it's the thing that
    /// supplies that name at startup), so it can't live inside the
    /// subtree that name selects.
    static var appSettingsFile: URL {

        internalRoot.appendingPathComponent(
            "AppSettings.json"
        )
    }


    // =============================================================
    // MARK: - Library files
    // =============================================================

    /// `<root>/<name>/<name>.sqlite` — the library's own subtree is
    /// named after it, and its database file sits directly inside,
    /// no extra "Libraries" nesting level.
    static func libraryFile(
        named name: String
    ) -> URL {

        root
            .appendingPathComponent(
                name,
                isDirectory:
                    true
            )
            .appendingPathComponent(
                name
            )
            .appendingPathExtension(
                "sqlite"
            )
    }


    static var defaultLibraryFile: URL {

        libraryFile(
            named:
                defaultLibraryName
        )
    }


    // =============================================================
    // MARK: - Folder creation
    // =============================================================

    /// Creates `root` plus everything the CURRENTLY active
    /// TrackLibrary (`currentLibraryName`) needs. Callers that just
    /// switched/created a TrackLibrary should set `currentLibraryName`
    /// first, then call this, so the right subtree gets created.
    static func createFolders() throws {

        let fm =
            FileManager.default

        try fm.createDirectory(
            at:
                root,
            withIntermediateDirectories:
                true
        )

        try fm.createDirectory(
            at:
                libraryRoot,
            withIntermediateDirectories:
                true
        )

        try fm.createDirectory(
            at:
                playlistsFolder,
            withIntermediateDirectories:
                true
        )

        try fm.createDirectory(
            at:
                smartlistFolder,
            withIntermediateDirectories:
                true
        )

        try fm.createDirectory(
            at:
                tandasFolder,
            withIntermediateDirectories:
                true
        )
    }


    // =============================================================
    // MARK: - Internal libraries
    // =============================================================

    /// Every TrackLibrary is now a top-level subfolder of `root`
    /// (`<root>/<name>/`) rather than a `.sqlite` file inside a shared
    /// `Libraries/` folder — so "list the libraries" means "list
    /// root's subdirectories" now, excluding `AppSettings.json` (a
    /// file, not a directory, so it's excluded automatically by the
    /// isDirectory filter below, but named here for clarity).
    static func internalLibraryNames() throws -> [String] {

        let fm =
            FileManager.default

        guard
            fm.fileExists(
                atPath:
                    root.path
            )
        else {
            return []
        }

        let contents =
            try fm.contentsOfDirectory(
                at:
                    root,
                includingPropertiesForKeys:
                    [.isDirectoryKey]
            )

        return contents
            .filter { url in

                (
                    try? url.resourceValues(
                        forKeys:
                            [.isDirectoryKey]
                    )
                )?.isDirectory
                    ==
                    true
            }
            .map {
                $0.lastPathComponent
            }
            .sorted {
                $0.localizedStandardCompare($1)
                    ==
                    .orderedAscending
            }
    }
}
