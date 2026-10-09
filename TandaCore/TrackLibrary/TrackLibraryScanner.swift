//
//  TrackLibraryScanner.swift
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
//import AudioTagKit
//import TandaKit
import Combine

public final class LibraryScanner: ObservableObject {
    @Published public private(set) var isScanning = false
    @Published public private(set) var processedCount = 0
    @Published public private(set) var totalCount = 0
    @Published public private(set) var currentPhase: RescanPhase?

    private let db: DatabaseManager

    public init(db: DatabaseManager) {
        self.db = db
    }

    /// Recursively imports every supported audio file under `folderURL`.
    /// Tag reads run concurrently (bounded — see TandaKit.BoundedConcurrency);
    /// the actual database write happens once, afterward, on GRDB's own
    /// serialized writer, since that part is already fast and GRDB expects
    /// writes serialized anyway.
    public func importFolder(_ folderURL: URL) async throws {
        isScanning = true
        processedCount = 0
        defer { isScanning = false }

        let files = try FileCollector.collect(from: [folderURL.path], recursive: true)
        totalCount = files.count

        guard !files.isEmpty else { return }

        let results = await BoundedConcurrency.run(
            items: files,
            maxConcurrent: 6,
            onProgress: { [weak self] completed, _ in
                guard let self else { return }
                Task { @MainActor in
                    self.processedCount = completed
                }
            }
        ) { url -> Swift.Result<Song, Error> in
            do {
                let song = try await Self.readSong(at: url)
                return .success(song)
            } catch {
                return .failure(error)
            }
        }

        var imported: [Song] = []
        var failed: [(url: URL, error: Error)] = []

        for (url, result) in zip(files, results) {
            switch result {
            case .success(let song):
                imported.append(song)
            case .failure(let error):
                failed.append((url, error))
            }
        }

        // Immutable copy taken *before* the closure below — the closure is
        // @Sendable, and capturing the outer 'var imported' directly (even
        // read-only) is flagged as a concurrency hazard; capturing this
        // 'let' instead sidesteps that entirely.
        let songsToInsert = imported

        try await db.dbQueue.write { db in
            for song in songsToInsert {

                // Manual upsert-by-path: path is the file's real identity;
                // `id` is just the row's own key. Re-importing an
                // already-known file (rescanning a folder you already
                // added) updates its tags/duration instead of duplicating
                // the row.
                if var existing = try Song.filter(Column("path") == song.path).fetchOne(db) {

                    existing.normalizedPath = song.normalizedPath
                    existing.filename = song.filename
                    existing.title = song.title
                    existing.artist = song.artist
                    existing.album = song.album
                    existing.genre = song.genre
                    existing.bpm = song.bpm
                    existing.key = song.key
                    existing.year = song.year
                    existing.albumArtist = song.albumArtist
                    existing.duration = song.duration
                    existing.fileSize = song.fileSize
                    existing.lastModified = song.lastModified
                    existing.fileType = song.fileType
                    existing.sampleRate = song.sampleRate
                    existing.replayGain = song.replayGain
                    existing.grouping = song.grouping
                    existing.comment = song.comment

                    // IMPORTANT:
                    // Step 1 only introduces the hash.
                    //
                    // Existing tracks keep their existing fileHash.
                    // We do NOT calculate or replace it here yet.
                    //
                    // The rescan logic that compares
                    // fileModificationDateAtScan and decides when the
                    // metadata/hash must be refreshed will come later.

                    try existing.update(db)

                } else {

                    // New track:
                    //
                    // `song` already contains its SHA-256 hash because
                    // readSong(at:) calculates it before this database
                    // transaction.
                    let newSong = song

                    try newSong.insert(db)
                }
            }

            // Record where this import came from — see ImportSource's
            // doc comment. Best-effort: a folder that isn't on any
            // resolvable volume (shouldn't normally happen) just
            // stores a nil volumeUUID rather than failing the import.
            if !songsToInsert.isEmpty {

                let volumeInfo =
                    try? folderURL.resourceValues(
                        forKeys: [
                            .volumeUUIDStringKey,
                            .volumeNameKey
                        ]
                    )

                let source =
                    ImportSource(
                        path:
                            folderURL.path,
                        volumeUUID:
                            volumeInfo?.volumeUUIDString,
                        volumeName:
                            volumeInfo?.volumeName
                    )

                try source.insert(db)
            }
        }

        if !failed.isEmpty {
            throw ImportError.partialFailure(failed)
        }
    }


    // MARK: - Rescan

    /// Re-checks the library (or, if `scope` is given, just the
    /// subtree under that `ImportSource`'s folder) against what's
    /// actually on disk right now:
    ///
    /// 1. Existing tracks: gone → counted as missing (this run only,
    ///    nothing persisted); still there & unchanged (mod-date/size
    ///    match what was recorded at the last scan) → just bump
    ///    `lastLibraryScan`; still there & changed → re-read tags/hash
    ///    and update the row (`addedToLibrary` is preserved).
    /// 2. Any file found on disk that isn't a known path is a
    ///    candidate for either a genuinely new import, or a *move* of
    ///    a track that went missing in step 1 — decided by comparing
    ///    its SHA-256 against those missing tracks' stored hashes.
    ///    A hash match against a track whose OLD path still exists is
    ///    NOT treated as a move (that's a real duplicate — left alone
    ///    for the Duplicate Finder, not silently merged).
    ///
    /// Read-only towards the Library itself: this only diffs the known
    /// Songs and the folders on disk and returns a summary describing
    /// what changed — it does NOT write anything to the database. Call
    /// `applyRescan(_:)` with the returned summary once the user has
    /// reviewed it and approved applying the fixes.
    public func rescanLibrary(
        scope: ImportSource? = nil
    ) async throws -> RescanSummary {

        isScanning = true
        processedCount = 0
        currentPhase = .checkingKnownFiles
        defer {
            isScanning = false
            currentPhase = nil
        }

        var summary = RescanSummary()

        let fileManager = FileManager.default


        // =====================================================
        // STEP 1 — EXISTING TRACKS
        // =====================================================

        let allSongs: [Song] =
            try await db.dbQueue.read { db in
                try Song.fetchAll(db)
            }

        let songsToCheck: [Song] =
            if let scope {
                allSongs.filter {
                    $0.path.hasPrefix(scope.path)
                }
            } else {
                allSongs
            }

        totalCount = songsToCheck.count

        var missingInThisRun: [Song] = []
        var songsNeedingFullReread: [Song] = []
        var unchangedUpdates: [Song] = []

        for (index, song) in songsToCheck.enumerated() {

            processedCount = index + 1

            guard
                fileManager.fileExists(atPath: song.path)
            else {
                missingInThisRun.append(song)
                summary.missingSongs.append(song)
                continue
            }

            guard
                let attributes =
                    try? fileManager.attributesOfItem(
                        atPath: song.path
                    ),
                let modificationDate =
                    attributes[.modificationDate] as? Date,
                let size =
                    attributes[.size] as? Int64
            else {
                // Existed a moment ago (fileExists) but couldn't be
                // stat'd now — a race or permissions issue. Treat
                // conservatively as "needs a full re-read" rather than
                // silently leaving it unexamined.
                songsNeedingFullReread.append(song)
                continue
            }

            // Compared with a 1-second tolerance rather than exact
            // equality — fileModificationDateAtScan round-trips
            // through a GRDB .datetime column, which stores Date with
            // millisecond precision, while a freshly-stat'd Date can
            // carry sub-millisecond precision. Exact `==` almost never
            // matched even for a genuinely untouched file, so every
            // rescan fell through to a full re-read (new hash + tags)
            // for practically every song — "unchanged" was reachable
            // in theory but essentially never hit in practice.
            if abs(
                modificationDate.timeIntervalSince(
                    song.fileModificationDateAtScan
                )
            ) < 1.0,
               size == song.fileSizeAtScan {

                var updated = song
                updated.lastLibraryScan = Date()
                unchangedUpdates.append(updated)
                summary.unchangedSongsToRefresh.append(updated)
                summary.unchangedCount += 1

            } else {

                songsNeedingFullReread.append(song)
            }
        }


        // Re-read every changed file concurrently — same bounded-
        // concurrency pattern as importFolder, since this is exactly
        // as I/O-heavy per file (tags + hash).
        let rereadURLs =
            songsNeedingFullReread.map {
                URL(fileURLWithPath: $0.path)
            }

        // Immutable snapshot taken *before* the closure below — same
        // reasoning as importFolder's own `songsToInsert` copy: the
        // onProgress closure is @Sendable, and capturing the outer
        // 'var unchangedUpdates' directly (even just reading .count)
        // is flagged as a concurrency hazard.
        let unchangedCount =
            unchangedUpdates.count

        let rereadResults =
            await BoundedConcurrency.run(
                items: rereadURLs,
                maxConcurrent: 6,
                onProgress: { [weak self] completed, _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.processedCount =
                            unchangedCount + completed
                    }
                }
            ) { url -> Swift.Result<Song, Error> in
                do {
                    let song = try await Self.readSong(at: url)
                    return .success(song)
                } catch {
                    return .failure(error)
                }
            }

        var updatedSongs: [Song] = []

        for (original, result) in zip(songsNeedingFullReread, rereadResults) {

            switch result {

            case .success(let fresh):

                // Preserve the row's identity and original import
                // date; every other field comes from the fresh read.
                var merged = fresh
                merged.id = original.id
                merged.addedToLibrary = original.addedToLibrary

                updatedSongs.append(merged)
                summary.updatedSongs.append(merged)

            case .failure(let error):

                summary.failedReads.append(
                    (
                        url: URL(fileURLWithPath: original.path),
                        error: error
                    )
                )
            }
        }


        // NOTE: no DB write here anymore — unchangedUpdates and
        // updatedSongs are staged on `summary` (unchangedSongsToRefresh
        // / updatedSongs) and only committed by applyRescan(_:), once
        // the user has reviewed and approved the results.


        // =====================================================
        // STEP 2 — NEW FILES ON DISK (IMPORT OR RELOCATE)
        // =====================================================

        currentPhase = .checkingForNewFiles

        let foldersToWalk: [String]

        if let scope {

            foldersToWalk = [scope.path]

        } else {

            let allSources: [ImportSource] =
                try await db.dbQueue.read { db in
                    try ImportSource.fetchAll(db)
                }

            foldersToWalk =
                allSources.map { $0.path }
        }

        guard
            !foldersToWalk.isEmpty
        else {
            return summary
        }

        let filesOnDisk =
            try FileCollector.collect(
                from: foldersToWalk,
                recursive: true
            )

        let knownPaths =
            Set(
                songsToCheck.map { $0.path }
            )

        let candidateURLs =
            filesOnDisk.filter {
                !knownPaths.contains($0.path)
            }

        let missingByHash: [String: Song] =
            Dictionary(
                missingInThisRun.compactMap { song -> (String, Song)? in
                    guard let hash = song.fileHash else {
                        return nil
                    }
                    return (hash, song)
                },
                uniquingKeysWith: { first, _ in first }
            )

        var relocations: [Song] = []
        var trulyNewURLs: [URL] = []

        totalCount = candidateURLs.count
        processedCount = 0

        for (index, url) in candidateURLs.enumerated() {

            processedCount = index + 1

            guard
                let hash = try? await FileHasher.sha256(fileURL: url)
            else {
                // Couldn't hash it — fall through to a normal import
                // attempt below, which will surface the real read error.
                trulyNewURLs.append(url)
                continue
            }

            if let matched = missingByHash[hash] {

                var relocated = matched
                relocated.path = url.path
                relocated.normalizedPath = PathNormalizer.normalize(url)
                // addedToLibrary/id preserved as-is from `matched`.
                // fileModificationDateAtScan/fileSizeAtScan/
                // lastLibraryScan are left as they were — this file
                // will naturally be picked up as "changed" on the
                // NEXT rescan's Step 1 and get refreshed properly then,
                // rather than re-statting it a second time here.

                relocations.append(relocated)
                summary.relocatedTracks.append(
                    RelocatedTrack(
                        oldPath: matched.path,
                        song: relocated
                    )
                )

            } else {

                trulyNewURLs.append(url)
            }
        }


        // NOTE: relocations are staged on summary.relocatedTracks and
        // committed by applyRescan(_:), same as above — not written here.

        let baseProcessedCount = candidateURLs.count

        totalCount = candidateURLs.count + trulyNewURLs.count

        let newResults =
            await BoundedConcurrency.run(
                items: trulyNewURLs,
                maxConcurrent: 6,
                onProgress: { [weak self] completed, _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.processedCount =
                            baseProcessedCount + completed
                    }
                }
            ) { url -> Swift.Result<Song, Error> in
                do {
                    let song = try await Self.readSong(at: url)
                    return .success(song)
                } catch {
                    return .failure(error)
                }
            }

        var songsToInsert: [Song] = []

        for (url, result) in zip(trulyNewURLs, newResults) {

            switch result {

            case .success(let song):

                songsToInsert.append(song)
                summary.newlyImportedSongs.append(song)

            case .failure(let error):

                summary.failedReads.append(
                    (url: url, error: error)
                )
            }
        }


        // NOTE: new files are staged on summary.newlyImportedSongs and
        // committed by applyRescan(_:), same as above — not written here.

        return summary
    }


    // MARK: - Apply Rescan
    //
    // Commits a previously-computed RescanSummary (from rescanLibrary
    // above) to the database. Split out from rescanLibrary so the
    // scan itself stays read-only and the caller can show the results
    // to the user and get explicit confirmation before anything is
    // actually written — previously rescanLibrary wrote directly to
    // the database as it scanned, so as soon as "Start Rescan" was
    // clicked (whenever the Library happened to be unlocked) every fix
    // was already applied with no chance to review or decline it.
    public func applyRescan(_ summary: RescanSummary) async throws {

        try await db.dbQueue.write { db in

            for song in summary.unchangedSongsToRefresh {
                try song.update(db)
            }

            for song in summary.updatedSongs {
                try song.update(db)
            }

            for track in summary.relocatedTracks {
                try track.song.update(db)
            }

            for song in summary.newlyImportedSongs {
                try song.insert(db)
            }
        }
    }

    // Was `private` — opened up so SetlistView's external-file drop
    // handler (dragging audio files in from Finder) can reuse the exact
    // same tag-reading logic used during a real Library import, instead
    // of a second, drift-prone copy of it.
    static func readSong(at url: URL) async throws -> Song {
        try await SongMetadataReader.readSong(at: url)
    }
}
