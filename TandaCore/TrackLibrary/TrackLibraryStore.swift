//
//  LibraryStore.swift
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
import Combine

/// Holds the full imported library. `songs` is ALWAYS the whole Library:
/// display filters (Smartlist, A/T/V/M/X, same-title, title search) are
/// applied by the views on top of it, never here — everything that looks
/// tracks up in `songs` / `songsByID` / `songsByNormalizedPath` relies on
/// that.
@MainActor
public final class LibraryStore: ObservableObject {

    @Published public private(set) var songs: [Song] = [] {
        didSet {
            rebuildLookupCaches()
        }
    }

    /// Library songs keyed by id — built once here whenever `songs`
    /// changes, instead of every consumer (Setlist/Tanda rescans, the
    /// saved-Setlist viewer, etc.) rebuilding the same O(n) Dictionary
    /// from `songs` on every call. Consumers should read this instead
    /// of building their own.
    @Published public private(set) var songsByID: [Int64: Song] = [:]

    /// Library songs keyed by `normalizedPath` — the fallback lookup
    /// for legacy entries saved without an id. Same caching rationale
    /// as `songsByID`.
    @Published public private(set) var songsByNormalizedPath: [String: Song] = [:]

    private func rebuildLookupCaches() {

        var byID: [Int64: Song] = [:]
        var byPath: [String: Song] = [:]

        for song in songs {

            if let id = song.id {
                byID[id] = song
            }

            byPath[song.normalizedPath] = song
        }

        songsByID = byID
        songsByNormalizedPath = byPath
    }

    @Published public private(set) var currentLibraryName: String = "Library"

    public private(set) var currentLibraryPath: String = ""

    @Published public private(set) var internalLibraryNames: [String] = []

    @Published public private(set) var missingSongIDs: Set<Int64> = []

    @Published public var isLocked: Bool = true

    /// Set by `AppEnvironment.init()` when the TrackLibrary that was
    /// active at last quit could not be opened at startup (missing or
    /// corrupted `.sqlite` file) — holds that library's name so the
    /// app can tell the user, then offer to open a different Library
    /// or create a new one, instead of silently claiming to still be
    /// "on" a Library that doesn't actually load. `nil` once handled.
    /// The app is running on a throwaway in-memory database for as
    /// long as this is non-nil.
    @Published public var startupLibraryError: String?

    private let db: DatabaseManager
    private var allSongs: [Song] = []

    // MARK: - Init

    public init(db: DatabaseManager) {
        self.db = db
    }

    // MARK: - Reload

    public func reload() throws {

        allSongs = try db.dbQueue.read { db in
            try Song.order(Column("artist")).fetchAll(db)
        }

        songs = allSongs
        refreshInternalLibraryNames()
        refreshMissingSongIDs()
    }

    // MARK: - Delete Songs
    //
    // Used by "Clean Up Missing Links…" (Library view bottom bar) to
    // actually remove Library rows for tracks confirmed missing on
    // disk. Does NOT touch anything on disk itself — only this
    // Library's own record of the song. Existing Setlist entries and
    // Tanda references that used these ids aren't deleted; they'll
    // just resolve to `.notInLibrary` afterward (see
    // SetlistStore.resolveAgainstLibrary / TandaBlock.status(for:)).
    // MARK: - Compact (Reclaim Disk Space)

    /// Result of `compactCurrentLibrary()` — the `.sqlite` file's size
    /// (bytes) immediately before and after `VACUUM`, so the calling
    /// UI can show how much was actually reclaimed.
    public nonisolated struct CompactResult: Sendable {
        public let sizeBefore: Int64
        public let sizeAfter: Int64
    }

    /// Runs `VACUUM` on the currently active TrackLibrary's database
    /// — see `DatabaseManager.vacuum()` for why this is ever needed
    /// (deleting songs doesn't shrink the file on its own). Reports
    /// the file size before and after so the UI can show something
    /// concrete rather than just "Done".
    ///
    /// Runs the `VACUUM` itself off the main actor (it can take a
    /// moment on a big Library); the little state it needs from this
    /// MainActor store is read up front.
    public func compactCurrentLibrary() async throws -> CompactResult {

        let queue = db.dbQueue
        let path = currentLibraryPath

        return try await Task.detached(
            priority: .userInitiated
        ) {
            try Self.compact(queue: queue, path: path)
        }.value
    }

    nonisolated private static func compact(
        queue: DatabaseQueue,
        path: String
    ) throws -> CompactResult {

        let fm = FileManager.default

        func fileSize() -> Int64 {

            guard
                let attrs =
                    try? fm.attributesOfItem(
                        atPath: path
                    )
            else {
                return 0
            }

            return (attrs[.size] as? Int64) ?? 0
        }

        let before = fileSize()

        try DatabaseManager.vacuum(on: queue)

        let after = fileSize()

        return CompactResult(
            sizeBefore: before,
            sizeAfter: after
        )
    }

    public func deleteSongs(ids: Set<Int64>) throws {

        guard !ids.isEmpty else {
            return
        }

        try db.dbQueue.write { db in

            _ = try Song
                .filter(ids: ids)
                .deleteAll(db)
        }

        try reload()
    }

    // MARK: - Tag Editing
    //
    // Applies already-written-to-disk tag values to the matching
    // cached rows — call this AFTER TagEditingActions has
    // successfully written the SAME values to the actual audio files
    // via AudioTagKit, never instead of it. Deliberately takes plain
    // optional values rather than AudioTagKit's own TagChanges, so
    // LibraryStore (part of TandaCore) stays free of any dependency
    // on AudioTagKit — that translation is TagEditingActions' job.
    //
    // Reuses the exact same "write to DB, then reload()" shape
    // deleteSongs(ids:) above already uses, rather than surgically
    // patching `songs` in memory.
    //
    // A nil parameter leaves that field untouched on every song (same
    // meaning as a nil TagChanges field) — there's no way to
    // explicitly blank out a tag through this method; leaving a field
    // empty in the UI is indistinguishable from never having touched
    // it. Wiping a tag entirely, if ever needed, is a separate
    // concern (see AudioTagKit's TagWriter.strip).
    public func updateSongTags(
        ids: Set<Int64>,
        title: String?,
        artist: String?,
        albumArtist: String?,
        genre: String?,
        year: Int?,
        comment: String?
    ) throws {

        guard
            !ids.isEmpty,
            title != nil || artist != nil || albumArtist != nil
                || genre != nil || year != nil || comment != nil
        else {
            return
        }

        try db.dbQueue.write { db in

            var songsToUpdate =
                try Song.filter(ids: ids).fetchAll(db)

            for index in songsToUpdate.indices {

                if let v = title { songsToUpdate[index].title = v }
                if let v = artist { songsToUpdate[index].artist = v }
                if let v = albumArtist { songsToUpdate[index].albumArtist = v }
                if let v = genre { songsToUpdate[index].genre = v }
                if let v = year { songsToUpdate[index].year = v }
                if let v = comment { songsToUpdate[index].comment = v }

                try songsToUpdate[index].update(db)
            }
        }

        try reload()
    }

    // MARK: - Import Sources
    //
    // "Add Files"/"Add Folder" records one `ImportSource` row per
    // import (folder path + volume info) so a full Rescan knows which
    // folders to walk for new/relocated files. Over time these can
    // accumulate dead entries — a folder that was renamed, moved, or
    // whose contents were all later removed from the Library — and
    // every one of them still gets walked on every Rescan. Used by the
    // "Manage Import Sources…" window (Tools menu).

    public func fetchImportSources() throws -> [ImportSource] {

        try db.dbQueue.read { db in
            try ImportSource
                .order(Column("importedAt").desc)
                .fetchAll(db)
        }
    }

    /// How many of the Library's CURRENT songs live under this import
    /// source's folder (recursively) — the only thing that decides
    /// whether deleting it is safe. Checked against `allSongs`, not
    /// the search-filtered `songs`, so an active search filter can
    /// never hide a still-in-use folder from this check.
    public func songCount(underImportSourcePath path: String) -> Int {

        let prefix =
            path.hasSuffix("/")
            ? path
            : path + "/"

        return allSongs.filter {
            $0.path == path || $0.path.hasPrefix(prefix)
        }.count
    }

    /// Deletes ONE `ImportSource` row — bookkeeping only, never
    /// touches any Song row or any file on disk. Refuses (throws) if
    /// the Library still has any song under that folder, even if the
    /// caller's own UI check somehow got out of sync with the current
    /// Library state — this is the one hard rule for this feature and
    /// it's enforced here, not just in the confirmation UI.
    public func deleteImportSource(
        id: Int64,
        path: String
    ) throws {

        guard songCount(underImportSourcePath: path) == 0 else {

            throw LibraryStoreError.importSourceStillInUse
        }

        try db.dbQueue.write { db in

            _ = try ImportSource
                .filter(id: id)
                .deleteAll(db)
        }
    }

    // MARK: - Current Library

    public func setCurrentLibraryName(from path: String) {

        currentLibraryPath = path

        currentLibraryName = URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent

        AppPaths.currentLibraryName = currentLibraryName
    }

    // MARK: - Switch Library

    public func loadLibrary(from path: String) throws {

        try db.switchDatabase(to: path)

        currentLibraryPath = path

        currentLibraryName = URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent

        // Path resolution for every other store (Setlists, Tandas,
        // Smartlists) follows this immediately — they all read
        // AppPaths.libraryRoot, which is keyed off this. Persisting
        // the choice to AppSettings.json (so it survives a relaunch)
        // is the caller's job — see LibraryActions.openLibrary.
        AppPaths.currentLibraryName = currentLibraryName

        try reloadAfterSwitch()
    }

    // MARK: - Clear Library

    public func clearLibrary() throws {

        _ = try db.dbQueue.write { db in
            try Song.deleteAll(db)
        }

        allSongs = []
        songs = []
        missingSongIDs = []
    }

    // MARK: - Internal Libraries

    public func listInternalLibraries() throws -> [String] {
        try AppPaths.internalLibraryNames()
    }

    public func loadInternalLibrary(named name: String) throws {

        try loadLibrary(
            from: AppPaths.libraryFile(named: name).path
        )
    }


    /// Replaces only the value of `"savedAgainstLibraryName"` in the raw
    /// JSON text and returns the new bytes; nil if the key or text could
    /// not be handled (caller then falls back to re-serializing).
    private static func replacingLibraryReference(in data: Data, to newName: String) -> Data? {

        guard let text = String(data: data, encoding: .utf8),
              let encoded = try? JSONSerialization.data(
                withJSONObject: [newName],
                options: [.withoutEscapingSlashes]
              ),
              var literal = String(data: encoded, encoding: .utf8),
              literal.count >= 2 else {
            return nil
        }

        // ["name"] -> "name" (a properly escaped JSON string literal)
        literal.removeFirst()
        literal.removeLast()

        let pattern = "(\"savedAgainstLibraryName\"\\s*:\\s*)\"(?:[^\"\\\\]|\\\\.)*\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let whole = Range(match.range, in: text),
              let prefix = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let result = text.replacingCharacters(
            in: whole,
            with: String(text[prefix]) + literal
        )
        return result.data(using: .utf8)
    }


    /// Renames the currently active TrackLibrary as a complete subtree.
    /// The database connection is detached before moving the directory,
    /// and JSON library-identity fields are updated with rollback support.
    public func renameCurrentLibrary(to requestedName: String) throws {

        let newName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldName = currentLibraryName

        guard !newName.isEmpty,
              newName != ".",
              newName != "..",
              !newName.contains("/"),
              !newName.contains("\\"),
              !newName.contains(":"),
              !newName.contains("\0") else {
            throw LibraryStoreError.invalidLibraryName
        }

        guard newName != oldName else { return }

        let fm = FileManager.default
        let oldFolder = AppPaths.root.appendingPathComponent(oldName, isDirectory: true)
        let newFolder = AppPaths.root.appendingPathComponent(newName, isDirectory: true)

        guard fm.fileExists(atPath: oldFolder.path) else {
            throw DatabaseManagerError.fileNotFound(oldFolder.path)
        }
        guard !fm.fileExists(atPath: newFolder.path) else {
            throw LibraryStoreError.destinationAlreadyExists
        }

        // Capture the original bytes so any JSON write failure can be rolled back exactly.
        let jsonFiles = Self.jsonFiles(in: oldFolder)
        var originalJSON: [String: Data] = [:]
        for url in jsonFiles {
            originalJSON[url.path] = try Data(contentsOf: url)
        }

        // Detach SQLite from the file before moving its containing directory.
        try db.switchToInMemory()
        var folderMoved = false
        var databaseFileRenamed = false

        do {
            try fm.moveItem(at: oldFolder, to: newFolder)
            folderMoved = true

            // The database filename mirrors the folder/library name.
            let oldDatabaseInNewFolder = newFolder.appendingPathComponent(oldName).appendingPathExtension("sqlite")
            let newDatabaseInNewFolder = newFolder.appendingPathComponent(newName).appendingPathExtension("sqlite")
            guard fm.fileExists(atPath: oldDatabaseInNewFolder.path) else {
                throw DatabaseManagerError.fileNotFound(oldDatabaseInNewFolder.path)
            }
            try fm.moveItem(at: oldDatabaseInNewFolder, to: newDatabaseInNewFolder)
            databaseFileRenamed = true

            // Only update the explicit library identity field. The file is
            // edited as text, in place, so everything else stays byte-for-
            // byte as it was: readable paths (no "\/" escaping), key order,
            // indentation. Re-serializing the whole object would change all
            // of that.
            for oldURL in Self.jsonFiles(in: newFolder) {
                let data = try Data(contentsOf: oldURL)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let reference = object["savedAgainstLibraryName"] as? String,
                      reference == oldName else {
                    continue
                }

                var updated = Self.replacingLibraryReference(in: data, to: newName)

                // Verify the in-place edit; otherwise fall back to a full
                // re-serialization that at least keeps slashes readable.
                if let candidate = updated,
                   let check = try? JSONSerialization.jsonObject(with: candidate) as? [String: Any],
                   check["savedAgainstLibraryName"] as? String == newName {
                    // ok
                } else {
                    var fallback = object
                    fallback["savedAgainstLibraryName"] = newName
                    updated = try JSONSerialization.data(
                        withJSONObject: fallback,
                        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    )
                }

                try updated?.write(to: oldURL, options: .atomic)
            }

            let newDatabasePath = AppPaths.libraryFile(named: newName).path
            try db.switchDatabase(to: newDatabasePath)

            currentLibraryPath = newDatabasePath
            currentLibraryName = newName
            AppPaths.currentLibraryName = newName
            try reloadAfterSwitch()

        } catch {
            // Close any connection opened against the renamed path before moving it back.
            try? db.switchToInMemory()

            // Restore JSON bytes in whichever location currently owns the folder.
            let recoveryFolder = folderMoved ? newFolder : oldFolder
            for (originalPath, data) in originalJSON {
                let relativePath = String(originalPath.dropFirst(oldFolder.path.count))
                let recoveryURL = URL(fileURLWithPath: recoveryFolder.path + relativePath)
                if fm.fileExists(atPath: recoveryURL.path) {
                    try? data.write(to: recoveryURL, options: .atomic)
                }
            }

            if folderMoved {
                if databaseFileRenamed {
                    let renamedDatabase = newFolder.appendingPathComponent(newName).appendingPathExtension("sqlite")
                    let originalDatabase = newFolder.appendingPathComponent(oldName).appendingPathExtension("sqlite")
                    if fm.fileExists(atPath: renamedDatabase.path),
                       !fm.fileExists(atPath: originalDatabase.path) {
                        try? fm.moveItem(at: renamedDatabase, to: originalDatabase)
                    }
                }
                if !fm.fileExists(atPath: oldFolder.path) {
                    try? fm.moveItem(at: newFolder, to: oldFolder)
                }
            }

            // Best effort to restore the original active database and paths.
            if fm.fileExists(atPath: AppPaths.libraryFile(named: oldName).path) {
                try? db.switchDatabase(to: AppPaths.libraryFile(named: oldName).path)
            }
            currentLibraryPath = AppPaths.libraryFile(named: oldName).path
            currentLibraryName = oldName
            AppPaths.currentLibraryName = oldName
            try? reloadAfterSwitch()
            throw error
        }
    }

    private static func jsonFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { $0 as? URL }.filter {
            $0.pathExtension.lowercased() == "json"
        }
    }

    public func deleteInternalLibrary(named name: String) throws {

        // The whole <root>/<name>/ subtree now — its Setlists,
        // Smartlists, and Tandas are bundled with it, not shared
        // globally, so deleting "just the .sqlite" would leave those
        // behind as orphans. Deleting a TrackLibrary deletes
        // everything that belongs to it.
        let folder =
            AppPaths.root.appendingPathComponent(
                name,
                isDirectory: true
            )

        guard !isSamePath(folder.path, AppPaths.libraryRoot.path) else {
            throw LibraryStoreError.cannotDeleteActiveLibrary
        }

        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw DatabaseManagerError.fileNotFound(folder.path)
        }

        try FileManager.default.removeItem(at: folder)

        refreshInternalLibraryNames()
    }

    public func newLibrary(named name: String) throws {

        // The folder has to exist before the database file can be
        // created inside it — unlike the old shared `Libraries/`
        // folder (already guaranteed to exist), each TrackLibrary now
        // gets its own fresh subtree.
        try FileManager.default.createDirectory(
            at: AppPaths.root.appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: true
        )

        let path = AppPaths.libraryFile(named: name).path

        try db.createAndSwitchToEmptyLibrary(at: path)

        currentLibraryPath = path
        currentLibraryName = name

        AppPaths.currentLibraryName = name

        // Also create this new TrackLibrary's Setlists/Smartlists/
        // Tandas subfolders — a brand-new name has none yet.
        try AppPaths.createFolders()

        try reloadAfterSwitch()
    }

    // MARK: - Export / Import

    public func exportLibrary(to path: String) throws {

        guard !isSamePath(path, currentLibraryPath) else {
            return
        }

        let destinationURL = URL(fileURLWithPath: path)

        let destinationDirectory =
            destinationURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let destinationDB =
            try DatabaseQueue(path: destinationURL.path)

        try db.dbQueue.backup(to: destinationDB)

        refreshInternalLibraryNames()
    }

    // MARK: - Reset to Factory State

    public func resetToFactoryState() throws {

        try db.switchToInMemory()

        let fm = FileManager.default

        // Every TrackLibrary is its own top-level subfolder now (see
        // AppPaths.libraryRoot), each bundling its own Setlists/
        // Smartlists/Tandas — so wiping "all libraries" the way this
        // used to (removing the old shared Libraries/ folder, which
        // held only the .sqlite files) now also removes every
        // library's Setlists/Tandas/Smartlists along with it, not
        // just their databases. That's a real behavior change from
        // before, and a deliberate one: it's what "factory state"
        // should mean once Setlists/Tandas are scoped per library.
        if let names = try? AppPaths.internalLibraryNames() {

            for name in names {

                let folder =
                    AppPaths.root.appendingPathComponent(
                        name,
                        isDirectory: true
                    )

                try? fm.removeItem(at: folder)
            }
        }

        AppPaths.currentLibraryName =
            AppPaths.defaultLibraryName

        try AppPaths.createFolders()

        try db.createAndSwitchToEmptyLibrary(
            at: AppPaths.defaultLibraryFile.path
        )

        currentLibraryPath =
            AppPaths.defaultLibraryFile.path

        currentLibraryName =
            AppPaths.defaultLibraryName

        UserDefaults.standard.removeObject(
            forKey: "LastPlaylist"
        )

        UserDefaults.standard.removeObject(
            forKey: "LastPlaylistLibraryPath"
        )

        // Leftover from the removed Internal/External Location
        // feature — cleared here too so a factory reset fully
        // clears any pre-existing installation's state.
        UserDefaults.standard.removeObject(
            forKey: "LastPlaylist.Internal"
        )

        UserDefaults.standard.removeObject(
            forKey: "LastPlaylist.External"
        )

        UserDefaults.standard.removeObject(
            forKey: "ExternalLibraryLocation"
        )

        UserDefaults.standard.removeObject(
            forKey: "ExternalLibraryBookmark"
        )

        // Superseded by AppSettings.json (AppPaths.currentLibraryName
        // above) — cleared here too so a stale value can't linger
        // from before this migration.
        UserDefaults.standard.removeObject(
            forKey: "LastLibraryPath"
        )

        try reloadAfterSwitch()
    }

    // MARK: - Shared Post-Switch Reload

    private func reloadAfterSwitch() throws {

        allSongs = try db.dbQueue.read { db in
            try Song.order(Column("artist")).fetchAll(db)
        }

        songs = allSongs
        refreshInternalLibraryNames()
        refreshMissingSongIDs()
    }

    // MARK: - Internal Library List

    private func refreshInternalLibraryNames() {

        internalLibraryNames =
            (try? AppPaths.internalLibraryNames()) ?? []
    }

    // MARK: - Missing Files

    private func refreshMissingSongIDs() {

        let currentSongs = allSongs

        Task.detached(priority: .utility) {

            let fm = FileManager.default

            var missing = Set<Int64>()

            for song in currentSongs {

                guard let id = song.id else {
                    continue
                }

                if !fm.fileExists(atPath: song.path) {
                    missing.insert(id)
                }
            }

            let sweptMissing = missing

            await MainActor.run { [weak self] in

                guard let self,
                      self.allSongs.map(\.id) == currentSongs.map(\.id)
                else {
                    return
                }

                self.missingSongIDs = sweptMissing
            }
        }
    }

    // MARK: - Path Comparison

    private func isSamePath(_ lhs: String, _ rhs: String) -> Bool {

        guard !lhs.isEmpty, !rhs.isEmpty else {
            return false
        }

        return URL(fileURLWithPath: lhs)
            .standardizedFileURL
            .path
            ==
            URL(fileURLWithPath: rhs)
                .standardizedFileURL
                .path
    }
}

// MARK: - Errors

public enum LibraryStoreError: LocalizedError {

    case destinationAlreadyExists
    case cannotWriteOntoActiveLibrary
    case cannotDeleteActiveLibrary
    case importSourceStillInUse
    case invalidLibraryName

    public var errorDescription: String? {

        switch self {

        case .destinationAlreadyExists:
            return "A library with this name already exists. Please choose another filename."

        case .cannotWriteOntoActiveLibrary:
            return "This is already the active Library, so it's saved. Choose a different name to keep a separate copy."

        case .cannotDeleteActiveLibrary:
            return "This is the currently active Library and can't be deleted. Switch to a different Library first."

        case .importSourceStillInUse:
            return "This folder still has tracks in the Library — it can only be removed once no track references it anymore."

        case .invalidLibraryName:
            return "The library name is invalid. Use a non-empty name without path separators or filesystem-reserved characters."
        }
    }
}

