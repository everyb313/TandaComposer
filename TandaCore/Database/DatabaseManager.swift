//
//  DatabaseManager.swift
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

/// Owns the active GRDB connection and its database schema.
///
/// The active database can be switched at runtime. LibraryStore,
/// PlaylistStore and LibraryScanner all keep the same DatabaseManager
/// instance, so switching the database automatically switches the
/// database used by all three stores.
public final class DatabaseManager {

    public private(set) var dbQueue: DatabaseQueue


    /// Runs SQLite's `VACUUM` on the currently open database —
    /// rebuilds the file from scratch, reclaiming the disk space
    /// freed by deleted rows. SQLite doesn't shrink the file back
    /// down on its own after a `DELETE`; the freed pages just sit in
    /// an internal freelist, reused by future inserts but never
    /// released back to the filesystem without this. Must run OUTSIDE
    /// a transaction — SQLite disallows `VACUUM` inside one, hence
    /// `writeWithoutTransaction` rather than the usual `write`.
    public func vacuum() throws {

        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
    }


    // MARK: - Initializers

    public init(path: String) throws {

        let queue =
            try Self.openAndMigrate(
                path: path
            )

        dbQueue =
            queue
    }


    /// In-memory database — used by SwiftUI previews and unit tests.
    public init() throws {

        let queue =
            try DatabaseQueue()

        try Self.migrator.migrate(
            queue
        )

        dbQueue =
            queue
    }


    // MARK: - Switch Database

    /// Opens an existing TandaComposer library database.
    ///
    /// The current database remains untouched until the new database
    /// has been successfully opened and migrated.
    public func switchDatabase(
        to path: String
    ) throws {

        let newQueue =
            try Self.openAndMigrate(
                path:
                    path
            )

        dbQueue =
            newQueue
    }


    /// Temporarily switches to an in-memory database, dropping the
    /// only reference to the current on-disk connection so ARC closes
    /// it (GRDB's DatabaseQueue closes its underlying SQLite
    /// connection/file handle on deinit).
    ///
    /// Call this BEFORE any external process replaces the .sqlite
    /// file this connection currently has open — e.g. `ditto` during
    /// Import Backup (LibraryActions.importBackup()). Skipping this
    /// is what caused "BUG IN CLIENT OF libsqlite3.dylib: … vnode
    /// unlinked while in use" followed by "disk I/O error" on every
    /// query afterwards: `ditto` unlinks (deletes) and recreates the
    /// destination file rather than overwriting it in place, and
    /// SQLite treats a file disappearing out from under an open
    /// connection as a serious integrity violation — the connection
    /// stays broken for the rest of the session, only a full app
    /// restart clears it.
    ///
    /// Call `switchDatabase(to:)` afterwards to reopen cleanly once
    /// the external process is done.
    public func detachForExternalReplace() throws {

        let queue =
            try DatabaseQueue()

        try Self.migrator.migrate(
            queue
        )

        dbQueue =
            queue
    }


    // MARK: - Open / Validate / Migrate

    private static func openAndMigrate(
        path: String
    ) throws -> DatabaseQueue {

        let fileManager =
            FileManager.default

        guard
            fileManager.fileExists(
                atPath:
                    path
            )
        else {

            throw DatabaseManagerError.fileNotFound(
                path
            )
        }


        let queue =
            try DatabaseQueue(
                path:
                    path
            )


        let isValid =
            try queue.read { db in

                let songsExists =
                    try db.tableExists(
                        "songs"
                    )

                let playlistsExists =
                    try db.tableExists(
                        "playlists"
                    )

                let playlistSongsExists =
                    try db.tableExists(
                        "playlist_songs"
                    )

                return
                    songsExists &&
                    playlistsExists &&
                    playlistSongsExists
            }


        guard isValid
        else {

            throw DatabaseManagerError.invalidLibrary
        }


        // Current schema.
        //
        // Existing databases are expected to have been recreated
        // with this schema. No historical migrations are required.

        try Self.migrator.migrate(
            queue
        )


        return queue
    }


    // MARK: - Create Empty Library

    /// Creates a brand-new, empty TandaComposer library at `path`.
    ///
    /// The destination must not already exist.
    @discardableResult
    static func createEmptyLibrary(
        at path: String
    ) throws -> DatabaseQueue {

        let fileManager =
            FileManager.default

        guard
            !fileManager.fileExists(
                atPath:
                    path
            )
        else {

            throw DatabaseManagerError.destinationAlreadyExists(
                path
            )
        }


        let directory =
            (path as NSString).deletingLastPathComponent

        try fileManager.createDirectory(
            atPath:
                directory,
            withIntermediateDirectories:
                true
        )


        let queue =
            try DatabaseQueue(
                path:
                    path
            )


        try Self.migrator.migrate(
            queue
        )


        return queue
    }


    /// Creates a brand-new, empty library at `path` and makes it
    /// the active database of this manager.
    public func createAndSwitchToEmptyLibrary(
        at path: String
    ) throws {

        let newQueue =
            try Self.createEmptyLibrary(
                at:
                    path
            )

        dbQueue =
            newQueue
    }


    /// Switches the active connection to a throwaway in-memory
    /// database.
    ///
    /// Used before deleting a folder that may contain the file the
    /// active connection is pointing at.
    public func switchToInMemory() throws {

        let queue =
            try DatabaseQueue()

        try Self.migrator.migrate(
            queue
        )

        dbQueue =
            queue
    }


    // MARK: - Database Schema

    private static var migrator:
        DatabaseMigrator {

        var migrator =
            DatabaseMigrator()


        // MARK: Songs

        migrator.registerMigration(
            "createSongs"
        ) { db in

            try db.create(
                table:
                    "songs"
            ) { t in

                // 1
                t.autoIncrementedPrimaryKey(
                    "id"
                )


                // 2
                t.column(
                    "filename",
                    .text
                )
                .notNull()


                // 3
                t.column(
                    "path",
                    .text
                )
                .notNull()
                .unique()


                // 4
                t.column(
                    "normalizedPath",
                    .text
                )
                .notNull()
                .indexed()


                // 5
                t.column(
                    "title",
                    .text
                )


                // 6
                t.column(
                    "artist",
                    .text
                )


                // 7
                t.column(
                    "albumArtist",
                    .text
                )


                // 8
                t.column(
                    "genre",
                    .text
                )


                // 9
                t.column(
                    "grouping",
                    .text
                )


                // 10
                t.column(
                    "year",
                    .integer
                )


                // 11
                t.column(
                    "comment",
                    .text
                )


                // 12
                t.column(
                    "fileType",
                    .text
                )


                // 13
                t.column(
                    "duration",
                    .integer
                )


                // 14
                t.column(
                    "sampleRate",
                    .integer
                )


                // 15
                t.column(
                    "replayGain",
                    .double
                )


                // 16
                t.column(
                    "album",
                    .text
                )


                // 17
                t.column(
                    "key",
                    .text
                )


                // 18
                t.column(
                    "bpm",
                    .double
                )


                // 19
                t.column(
                    "fileSize",
                    .integer
                )


                // 20
                t.column(
                    "lastModified",
                    .integer
                )


                // 21
                t.column(
                    "addedToLibrary",
                    .datetime
                )


                // 22
                t.column(
                    "lastLibraryScan",
                    .datetime
                )


                // 23
                t.column(
                    "fileModificationDateAtScan",
                    .datetime
                )


                // 24
                t.column(
                    "fileSizeAtScan",
                    .integer
                )


                // 25
                // SHA-256 hash of the complete file contents.
                t.column(
                    "fileHash",
                    .text
                )
            }
        }


        // MARK: Playlists

        migrator.registerMigration(
            "createPlaylists"
        ) { db in

            try db.create(
                table:
                    "playlists"
            ) { t in

                t.autoIncrementedPrimaryKey(
                    "id"
                )

                t.column(
                    "name",
                    .text
                )
                .notNull()

                t.column(
                    "createdAt",
                    .datetime
                )
                .notNull()
            }
        }


        // MARK: Playlist Songs

        // Every playlist occurrence gets its own ID.
        //
        // This intentionally allows the same song to occur multiple
        // times in the same playlist.

        migrator.registerMigration(
            "createPlaylistSongs"
        ) { db in

            try db.create(
                table:
                    "playlist_songs"
            ) { t in

                t.autoIncrementedPrimaryKey(
                    "id"
                )

                t.column(
                    "playlistId",
                    .integer
                )
                .notNull()
                .references(
                    "playlists",
                    onDelete:
                        .cascade
                )

                t.column(
                    "songId",
                    .integer
                )
                .notNull()
                .references(
                    "songs",
                    onDelete:
                        .cascade
                )

                t.column(
                    "position",
                    .integer
                )
                .notNull()
            }
        }


        // MARK: Import Sources

        migrator.registerMigration(
            "createImportSources"
        ) { db in

            try db.create(
                table:
                    "import_sources"
            ) { t in

                t.autoIncrementedPrimaryKey(
                    "id"
                )

                t.column(
                    "path",
                    .text
                )
                .notNull()

                t.column(
                    "volumeUUID",
                    .text
                )

                t.column(
                    "volumeName",
                    .text
                )

                t.column(
                    "importedAt",
                    .datetime
                )
                .notNull()
            }
        }


        return migrator
    }


    // MARK: - Default Path

    /// Path of the default internal library.
    ///
    /// Creates the `Libraries` folder and, if this is the very first
    /// launch (no `Default.sqlite` yet), creates a fresh empty
    /// default library too.
    static func defaultStorePath() throws -> String {

        try AppPaths.createFolders()

        let path =
            AppPaths.defaultLibraryFile.path

        if !FileManager.default.fileExists(
            atPath:
                path
        ) {

            try createEmptyLibrary(
                at:
                    path
            )
        }

        return path
    }


    // MARK: - Startup Path

    /// Path to open at application launch.
    ///
    /// Prefers the TrackLibrary the user had open when the app last
    /// quit (or last explicitly switched to) — `AppPaths.
    /// currentLibraryName`, set by `TandaComposerApp.init()` from
    /// `AppSettings.json` before this runs. Falls back to the default
    /// internal library when there is no remembered library, or its
    /// folder no longer exists on disk.
    static func startupStorePath() throws -> String {

        try AppPaths.createFolders()

        let path =
            AppPaths.libraryFile(
                named: AppPaths.currentLibraryName
            ).path

        if FileManager.default.fileExists(
            atPath: path
        ) {
            return path
        }

        // Remembered TrackLibrary's folder is gone — fall back to
        // Default, and make sure AppPaths agrees, so every other
        // store (Setlists/Tandas/Smartlists) resolves against the
        // same fallback rather than a name whose folder doesn't
        // exist.
        AppPaths.currentLibraryName =
            AppPaths.defaultLibraryName

        return try defaultStorePath()
    }
}

// MARK: - Errors

public enum DatabaseManagerError:
    LocalizedError {

    case fileNotFound(String)

    case invalidLibrary

    case destinationAlreadyExists(String)


    public var errorDescription:
        String? {

        switch self {

        case .fileNotFound(let path):

            return
                "The selected library could not be found:\n\(path)"


        case .invalidLibrary:

            return
                "The selected file is not a valid TandaComposer library."


        case .destinationAlreadyExists(let path):

            return
                "A library already exists at this location:\n\(path)"
        }
    }
}
