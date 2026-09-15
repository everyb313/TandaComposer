//
//  SetlistStore.swift
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


//
//  SetlistStore.swift
//  TandaComposer
//

import Foundation
import GRDB
import Combine

public enum SetlistEntryStatus: Equatable {
    case resolved
    case fileMissing
    case notInLibrary

    /// The Library knows this song's id and doesn't consider it
    /// missing, but the path THIS entry/reference is holding doesn't
    /// match the Library's current path for that id anymore — i.e.
    /// the Library already found the file at a new location (via
    /// Rescan TrackLibrary), but this specific saved reference hasn't
    /// been re-linked to it yet, so using it as-is will fail (wrong
    /// path). Currently only detected for Tandas (TandaBlock.status
    /// in TandaLibraryView) — see the "no longer marked but still
    /// can't play" bug this was added for.
    case staleReference
}

public struct SetlistEntry: Identifiable {

    public let id = UUID()

    public var song: Song
    public var status: SetlistEntryStatus

    public init(song: Song, status: SetlistEntryStatus = .resolved) {
        self.song = song
        self.status = status
    }
}

@MainActor
public final class PlaylistStore: ObservableObject {

    @Published public private(set) var entries: [SetlistEntry] = []

    /// Read-only convenience — plain `[Song]`, no status/id. Mutating
    /// the Setlist always goes through `entries` directly now (see
    /// add/insert/move/remove below); this used to also be a settable
    /// property that every one of those methods routed through
    /// (`songs.append(...)`, `songs.remove(at:)`, etc.), which meant
    /// EVERY mutation rebuilt every entry from scratch via
    /// `SetlistEntry(song:)` — silently resetting every other entry's
    /// `.status` back to `.resolved` (losing its red/blue dot) and
    /// handing it a brand-new `id`, not just the ones actually being
    /// added/moved/removed. A `move()` alone was enough to wipe every
    /// dot in the Setlist.
    public var songs: [Song] {
        entries.map(\.song)
    }

    @Published public var name: String = "Untitled Set"

    @Published public private(set) var duplicateSongIDs: Set<Int64?> = []

    @Published public private(set) var selectedRowIndexes: IndexSet = []

    @Published public private(set) var savedPlaylistNamesList: [String] = []

    /// Which TrackLibrary the loaded Setlist's song ids were resolved
    /// against — mirrors `SetlistMetadataExport.savedAgainstLibraryName`.
    /// `resolveAgainstLibrary`/`previewRescan` compare this against
    /// `AppPaths.currentLibraryName` to decide whether `entries`' ids
    /// can be trusted at all (see `LibraryReferenceResolver`'s
    /// `trustID` parameter) — `nil`, or any other library's name,
    /// means no: match by path only until this Setlist is saved again
    /// under the currently active library.
    @Published public private(set) var savedAgainstLibraryName: String?

    private let db: DatabaseManager

    public weak var undoManager: UndoManager?

    public init(db: DatabaseManager) {

        self.db = db

        refreshSavedPlaylistNames()
    }

    // MARK: - External Data Change

    /// Call after something outside normal save()/load() flow has
    /// changed files on disk in the Setlists folder — currently only
    /// LibraryActions.importBackup(), which overwrites the whole
    /// ~/.TandaComposer folder from a zip.
    ///
    /// Refreshes the saved-names list, and if the currently open
    /// Setlist still exists on disk under its current name, reloads
    /// its content too (the import may have overwritten it with a
    /// different version). If it no longer exists, the in-memory copy
    /// is left as-is — unlike after a Location switch, there's no
    /// "regenerate a fresh Untitled Set" here, since the user's
    /// current unsaved work shouldn't just vanish because a backup
    /// import didn't happen to include a Setlist of the same name.
    public func refreshAfterExternalDataChange() {

        refreshSavedPlaylistNames()

        let url = fileURL(forName: name)

        guard FileManager.default.fileExists(atPath: url.path),
              let export = try? SetlistMetadataExporter.load(from: url)
        else {

            // The Setlist we had open doesn't exist under this name
            // in whatever data root is now active (most commonly:
            // switched to a different/brand-new TrackLibrary, which
            // has its own, separate Setlists folder) — leaving the
            // old name/entries on screen would silently show stale
            // data as if it were still current. Start fresh instead,
            // same as opening the app with nothing selected.
            newPlaylist()
            return
        }

        entries = export.songs.map {
            SetlistEntry(song: $0)
        }

        savedAgainstLibraryName = export.savedAgainstLibraryName

        duplicateSongIDs = []
        selectedRowIndexes = []
    }

    // MARK: - Selection

    public func updateSelectedRowIndexes(_ indexes: IndexSet) {
        selectedRowIndexes = indexes
    }

    // MARK: - Editing
    //
    // All four mutators below operate directly on `entries`, not the
    // read-only `songs` convenience above — see its doc comment for
    // why: routing through a rebuild-from-[Song] step is what used to
    // silently reset every other entry's status and id on every edit.
    // New entries (the ones actually being added/inserted) still get
    // the default `.resolved` status from `SetlistEntry.init` — that's
    // correct for them (nothing's known to be wrong yet; the next
    // `resolveAgainstLibrary` pass will re-derive the real status) —
    // but every entry NOT part of this edit keeps its existing id and
    // status untouched.

    public func add(_ newSongs: [Song]) {

        guard !newSongs.isEmpty else {
            return
        }

        let insertIndex = entries.count

        let newEntries = newSongs.map {
            SetlistEntry(song: $0)
        }

        registerUndo(actionName: "Add to Set") { store in
            store.entries.removeSubrange(
                insertIndex..<(insertIndex + newEntries.count)
            )
        }

        entries.append(contentsOf: newEntries)

        try? autosave()

        refreshDuplicatesIfActive()
    }

    public func insert(_ newSongs: [Song], at index: Int) {

        guard !newSongs.isEmpty else {
            return
        }

        let clampedIndex = min(max(0, index), entries.count)

        let newEntries = newSongs.map {
            SetlistEntry(song: $0)
        }

        registerUndo(actionName: "Insert into Set") { store in
            store.entries.removeSubrange(
                clampedIndex..<(clampedIndex + newEntries.count)
            )
        }

        entries.insert(contentsOf: newEntries, at: clampedIndex)

        try? autosave()

        refreshDuplicatesIfActive()
    }

    public func move(
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {

        let before = entries

        registerUndo(actionName: "Reorder Set") { store in
            store.entries = before
        }

        entries = Self.moved(
            entries,
            fromOffsets: source,
            toOffset: destination
        )

        try? autosave()
    }

    public func remove(atOffsets offsets: IndexSet) {

        guard !offsets.isEmpty else {
            return
        }

        let removed = offsets.map {
            (
                index: $0,
                entry: entries[$0]
            )
        }

        registerUndo(actionName: "Remove from Set") { store in

            for item in removed.sorted(by: { $0.index < $1.index }) {

                store.entries.insert(
                    item.entry,
                    at: min(
                        item.index,
                        store.entries.count
                    )
                )
            }
        }

        for index in offsets.sorted(by: >) {
            entries.remove(at: index)
        }

        selectedRowIndexes = []

        try? autosave()

        refreshDuplicatesIfActive()
    }

    private static func moved(
        _ array: [SetlistEntry],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [SetlistEntry] {

        var result = array

        let elementsToMove = source.map {
            array[$0]
        }

        let itemsBeforeDestination = source.filter {
            $0 < destination
        }.count

        for index in source.sorted(by: >) {
            result.remove(at: index)
        }

        let adjustedDestination =
            destination - itemsBeforeDestination

        result.insert(
            contentsOf: elementsToMove,
            at: adjustedDestination
        )

        return result
    }

    private func registerUndo(
        actionName: String,
        _ undo: @escaping (PlaylistStore) -> Void
    ) {

        guard let undoManager else {
            return
        }

        undoManager.setActionName(actionName)

        undoManager.registerUndo(withTarget: self) { target in
            undo(target)
        }
    }

    // MARK: - Resolve Against Library

    public func resolveAgainstLibrary(
        byID: [Int64: Song],
        byPath: [String: Song],
        missingSongIDs: Set<Int64>
    ) {

        let trustID =
            savedAgainstLibraryName == AppPaths.currentLibraryName

        entries = entries.map { entry in

            var updated = entry

            let resolution =
                LibraryReferenceResolver.resolve(
                    entry.song,
                    byID: byID,
                    byPath: byPath,
                    missingSongIDs: missingSongIDs,
                    trustID: trustID
                )

            if let live = resolution.live {

                updated.song = live

                updated.status =
                    resolution.isMissing
                    ? .fileMissing
                    : .resolved

            } else {

                updated.status = .notInLibrary
            }

            return updated
        }
    }

    // MARK: - Rescan References

    /// One entry whose Library reference could be re-linked by a
    /// rescan — the fixed song, the path it's currently pointing at,
    /// and the status it would move to. Purely a preview: nothing is
    /// changed until `applyRescan(_:)` is called with the fixes the
    /// user approved (mirrors `RelocatedTrack` in LibraryScanner.swift
    /// and the scan/apply split in `LibraryScanner.rescanLibrary`).
    public struct RescanFix {
        public let entryID: UUID
        public let song: Song
        public let oldPath: String
        public let newStatus: SetlistEntryStatus
    }

    /// Read-only: diffs the Setlist's entries against the Library and
    /// returns what a rescan WOULD fix. Doesn't touch `entries` or the
    /// saved file — call `applyRescan(_:)` with the result once the
    /// user has reviewed it and wants the fixes applied.
    ///
    /// Only entries where something would ACTUALLY change end up in
    /// the result — either the path re-links to a new Library location
    /// (`live.path != entry.song.path`) or the status itself would
    /// improve/correct (`newStatus != entry.status`, e.g. a stale
    /// `.notInLibrary` correcting to `.resolved` even without a path
    /// change). A song that's still genuinely missing on disk — same
    /// id, same (still-missing) path, status already `.fileMissing` —
    /// produces NO fix: previously this still counted as one, so
    /// "Apply Fixes" would report success and re-write the exact same
    /// `.fileMissing` status right back, leaving the dot red and no
    /// visible effect despite the "N fixed" message.
    public func previewRescan(
        byID: [Int64: Song],
        byPath: [String: Song],
        missingSongIDs: Set<Int64>
    ) -> [RescanFix] {

        let trustID =
            savedAgainstLibraryName == AppPaths.currentLibraryName

        var fixes: [RescanFix] = []

        for entry in entries {

            guard entry.status != .resolved else {
                continue
            }

            let resolution =
                LibraryReferenceResolver.resolve(
                    entry.song,
                    byID: byID,
                    byPath: byPath,
                    missingSongIDs: missingSongIDs,
                    trustID: trustID
                )

            guard let live = resolution.live else {
                continue
            }

            let newStatus: SetlistEntryStatus =
                resolution.isMissing
                ? .fileMissing
                : .resolved

            let statusWouldChange =
                newStatus != entry.status

            guard resolution.pathChanged || statusWouldChange else {
                continue
            }

            fixes.append(
                RescanFix(
                    entryID: entry.id,
                    song: live,
                    oldPath: entry.song.path,
                    newStatus: newStatus
                )
            )
        }

        return fixes
    }

    /// Commits a previously-computed set of `RescanFix`es (see
    /// `previewRescan(byID:byPath:missingSongIDs:)`) — applies each fix to
    /// its entry, then saves the Setlist to its real file (this is a
    /// deliberate, user-approved fix, not an ordinary edit, so unlike
    /// add/remove/move it writes straight to the saved file rather
    /// than only the "(autosaved)" backup). Returns false if the save
    /// itself failed (the fixes are still applied in memory and were
    /// written to the autosave backup as a fallback).
    @discardableResult
    public func applyRescan(_ fixes: [RescanFix]) -> Bool {

        guard !fixes.isEmpty else {
            return true
        }

        var byEntryID: [UUID: RescanFix] = [:]

        for fix in fixes {
            byEntryID[fix.entryID] = fix
        }

        entries = entries.map { entry in

            guard let fix = byEntryID[entry.id] else {
                return entry
            }

            var updated = entry
            updated.song = fix.song
            updated.status = fix.newStatus
            return updated
        }

        do {
            try save()
            return true
        } catch {
            try? autosave()
            return false
        }
    }

    // MARK: - Tanda Coloring

    @Published public var isTandaColoringEnabled = true

    public func toggleTandaColoring() {

        isTandaColoringEnabled.toggle()
    }

    // MARK: - Import Progress
    //
    // Set while dropped Finder files (drag-and-drop) are being read
    // one by one — see PlaylistView's acceptDrop. nil when no import
    // is in progress.

    @Published public var importProgress: (current: Int, total: Int)?

    // MARK: - Duplicates
    //
    // isDuplicateHighlightingEnabled is the actual toggle state —
    // kept separate from duplicateSongIDs.isEmpty, because "checking
    // is on but nothing duplicate was found" and "checking is off"
    // both leave duplicateSongIDs empty and used to be visually
    // (and logically, in refreshDuplicatesIfActive below)
    // indistinguishable.

    @Published public var isDuplicateHighlightingEnabled = false

    public func toggleDuplicateHighlighting() {

        isDuplicateHighlightingEnabled.toggle()

        if isDuplicateHighlightingEnabled {
            recomputeDuplicates()
        } else {
            duplicateSongIDs = []
        }
    }

    private func refreshDuplicatesIfActive() {

        guard isDuplicateHighlightingEnabled else {
            return
        }

        recomputeDuplicates()
    }

    private func recomputeDuplicates() {

        func key(_ song: Song) -> String {

            let title =
                (song.title ?? "")
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()

            let artist =
                (song.artist ?? "")
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()

            return "\(title)|\(artist)"
        }

        var grouped: [String: [Int64?]] = [:]

        for song in songs {
            grouped[key(song), default: []].append(song.id)
        }

        duplicateSongIDs = Set(
            grouped.values
                .filter { $0.count > 1 }
                .flatMap { $0 }
        )
    }

    // MARK: - Persistence

    /// Static because it depends only on `AppPaths`, not on any
    /// instance state — lets non-owning code (e.g.
    /// CleanUpMissingLinksView's cross-reference scan) resolve a saved
    /// Setlist's file location without needing a `PlaylistStore`
    /// instance of its own, which would risk disturbing whatever
    /// Setlist the user currently has open.
    public static func fileURLOnDisk(forName saveName: String) -> URL {

        AppPaths.playlistsFolder
            .appendingPathComponent(saveName)
            .appendingPathExtension("json")
    }

    private func fileURL(forName saveName: String) -> URL {
        Self.fileURLOnDisk(forName: saveName)
    }

    /// Saves the current Setlist under its current name.
    public func save() throws {

        try saveAs(
            name: self.name,
            deleteOldName: false
        )
    }

    /// Saves the current Setlist under a new name.
    ///
    /// If the name has changed, the previous saved Setlist is renamed:
    /// the new file is written first and the old file is deleted only
    /// after the new file was successfully written.
    ///
    /// The current Setlist entries remain unchanged.
    public func saveAs(
        name newName: String,
        deleteOldName: Bool = true
    ) throws {

        let trimmedName =
            newName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmedName.isEmpty else {
            throw PlaylistStoreError.invalidPlaylistName
        }

        try FileManager.default.createDirectory(
            at: AppPaths.playlistsFolder,
            withIntermediateDirectories: true
        )

        let oldName = self.name

        let newURL =
            fileURL(forName: trimmedName)

        try SetlistMetadataExporter.export(
            songs: self.songs,
            playlistName: trimmedName,
            to: newURL
        )

        if deleteOldName && oldName != trimmedName {

            let oldURL =
                fileURL(forName: oldName)

            if FileManager.default.fileExists(
                atPath: oldURL.path
            ) {

                try FileManager.default.removeItem(
                    at: oldURL
                )

                let oldAutosaveURL =
                    fileURL(
                        forName:
                            "\(oldName) (autosaved)"
                    )

                if FileManager.default.fileExists(
                    atPath: oldAutosaveURL.path
                ) {

                    try? FileManager.default.removeItem(
                        at: oldAutosaveURL
                    )
                }
            }
        }

        self.name = trimmedName

        UserDefaults.standard.set(
            self.name,
            forKey: AppPaths.lastPlaylistDefaultsKey
        )

        refreshSavedPlaylistNames()
    }

    // MARK: - Autosave

    private var autosaveName: String {
        "\(name) (autosaved)"
    }

    public func autosave() throws {

        try FileManager.default.createDirectory(
            at: AppPaths.playlistsFolder,
            withIntermediateDirectories: true
        )

        try SetlistMetadataExporter.export(
            songs: self.songs,
            playlistName: self.name,
            to: fileURL(forName: autosaveName)
        )
    }

    // MARK: - Load

    public func load(playlistName: String) throws {

        let url = fileURL(forName: playlistName)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PlaylistStoreError.playlistNotFound(playlistName)
        }

        let export = try SetlistMetadataExporter.load(from: url)

        name = export.playlistName

        entries = export.songs.map {
            SetlistEntry(song: $0)
        }

        savedAgainstLibraryName = export.savedAgainstLibraryName

        duplicateSongIDs = []
        selectedRowIndexes = []

        UserDefaults.standard.set(
            name,
            forKey: AppPaths.lastPlaylistDefaultsKey
        )

        refreshSavedPlaylistNames()
    }

    public func listPlaylistNames() throws -> [String] {
        try Self.listPlaylistNamesOnDisk()
    }

    /// Static counterpart to `listPlaylistNames()` — see
    /// `fileURLOnDisk(forName:)` for why.
    public static func listPlaylistNamesOnDisk() throws -> [String] {

        let fm = FileManager.default

        guard fm.fileExists(
            atPath: AppPaths.playlistsFolder.path
        ) else {
            return []
        }

        let contents = try fm.contentsOfDirectory(
            at: AppPaths.playlistsFolder,
            includingPropertiesForKeys: nil
        )

        return contents
            .filter {
                $0.pathExtension.lowercased() == "json"
            }
            .map {
                $0.deletingPathExtension().lastPathComponent
            }
            .filter {
                !$0.hasSuffix(" (autosaved)")
            }
            .sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
    }

    private func refreshSavedPlaylistNames() {

        savedPlaylistNamesList =
            (try? listPlaylistNames()) ?? []
    }

    // MARK: - New Setlist

    public func newPlaylist(named newName: String) {

        name = newName
        entries = []
        savedAgainstLibraryName = AppPaths.currentLibraryName
        duplicateSongIDs = []
        selectedRowIndexes = []

        refreshSavedPlaylistNames()

        UserDefaults.standard.set(
            name,
            forKey: AppPaths.lastPlaylistDefaultsKey
        )
    }

    public func newPlaylist() {
        newPlaylist(named: "Untitled Set")
    }

    // MARK: - Delete Saved Setlist

    public func delete(playlistName: String) throws {

        guard playlistName != name else {
            return
        }

        let url = fileURL(forName: playlistName)

        guard FileManager.default.fileExists(atPath: url.path) else {
            refreshSavedPlaylistNames()
            return
        }

        try FileManager.default.removeItem(at: url)

        let autosaveURL =
            fileURL(forName: "\(playlistName) (autosaved)")

        if FileManager.default.fileExists(atPath: autosaveURL.path) {
            try? FileManager.default.removeItem(at: autosaveURL)
        }

        refreshSavedPlaylistNames()
    }
}

// MARK: - Errors

public enum PlaylistStoreError: LocalizedError {

    case playlistNotFound(String)
    case invalidPlaylistName

    public var errorDescription: String? {

        switch self {

        case .playlistNotFound(let name):
            return "No saved Setlist named \"\(name)\" was found."

        case .invalidPlaylistName:
            return "The Setlist name must not be empty."
        }
    }
}

