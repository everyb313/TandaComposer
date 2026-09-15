//
//  LibraryScanner.swift
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
import CryptoKit

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
                let hash = try? await Self.sha256(fileURL: url)
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

    // Was `private` — opened up so PlaylistView's external-file drop
    // handler (dragging audio files in from Finder) can reuse the exact
    // same tag-reading logic used during a real Library import, instead
    // of a second, drift-prone copy of it.
    static func readSong(at url: URL) async throws -> Song {
        let metadata = try await AudioMetadataKit.read(url: url)
        let tags = CanonicalTags.extract(from: metadata)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

        // Duration: FLAC/AIFF previously never surfaced this (their
        // readers parsed sample rate/channels but skipped the
        // total-sample-count field needed for duration) — fixed upstream
        // in AudioTagKit's FLACReader/AIFFReader, so "durationSeconds" now
        // arrives here consistently across all four formats. Update your
        // AudioTagKit copy for this to actually take effect.
        let duration =
            (metadata["durationSeconds"] as? Double)
                .map {
                    Int(
                        $0.rounded()
                    )
                }

        // SHA-256 of the complete file contents.
        //
        // This is calculated when the file is read for import. For an
        // existing library track, the hash is deliberately retained by
        // the upsert logic above until the future rescan implementation
        // decides that the file has changed.
        let fileHash =
            try await sha256(
                fileURL:
                    url
            )

        // Filesystem attributes captured for the future rescan's
        // "did this file actually change?" fast check — must be the
        // REAL on-disk values, not the Song struct's own Date()/0
        // defaults (which previously slipped through here uncaught:
        // every freshly-read Song silently got fileModificationDate-
        // AtScan = "now" and fileSizeAtScan = 0, regardless of the
        // file's real modification date/size, since neither was ever
        // assigned in this initializer call below).
        let modificationDateAtScan =
            attributes[.modificationDate] as? Date
                ?? Date()

        let sizeAtScan =
            attributes[.size] as? Int64
                ?? 0

        let scannedAt =
            Date()

        return Song(
            id:
                nil,
            filename:
                url.lastPathComponent,
            path:
                url.path,
            normalizedPath:
                PathNormalizer.normalize(url),
            title:
                tags.title,
            artist:
                tags.artist,
            albumArtist:
                tags.albumArtist,
            genre:
                tags.genre,
            grouping:
                tags.grouping,
            year:
                Self.extractYear(
                    from:
                        tags.year
                ),
            comment:
                tags.comment,
            fileType:
                url.pathExtension.uppercased(),
            duration:
                duration,
            sampleRate:
                extractSampleRate(
                    from:
                        metadata
                ),
            replayGain:
                extractReplayGain(
                    from:
                        metadata
                ),
            album:
                tags.album,
            key:
                nil, // see doc comment on Song.key
            bpm:
                extractBPM(
                    from:
                        metadata
                ),
            fileSize:
                attributes[.size] as? Int64,
            lastModified:
                (attributes[.modificationDate] as? Date)
                    .map {
                        Int(
                            $0.timeIntervalSince1970
                        )
                    },
            addedToLibrary:
                scannedAt,
            lastLibraryScan:
                scannedAt,
            fileModificationDateAtScan:
                modificationDateAtScan,
            fileSizeAtScan:
                sizeAtScan,
            fileHash:
                fileHash
        )
    }


    // MARK: - SHA-256

    /// Calculates the SHA-256 hash of the complete file contents and
    /// returns it as a lowercase hexadecimal string.
    /// Hashes the file's full contents off the calling thread.
    ///
    /// Reading + hashing a large file (esp. over slow external/network
    /// media) can take seconds — running it inline on whatever actor
    /// called `readSong` (e.g. a drag-and-drop drop handler that hops
    /// straight back to @MainActor) used to freeze the UI for that
    /// whole duration. `Task.detached` guarantees this always runs on
    /// a background thread, no matter the caller's isolation.
    private static func sha256(
        fileURL:
            URL
    ) async throws -> String {

        try await Task.detached(
            priority:
                .utility
        ) {

            try sha256Sync(
                fileURL:
                    fileURL
            )

        }.value
    }


    nonisolated private static func sha256Sync(
        fileURL:
            URL
    ) throws -> String {

        let handle =
            try FileHandle(
                forReadingFrom:
                    fileURL
            )

        defer {
            try? handle.close()
        }


        var hasher =
            SHA256()


        while true {

            let data =
                try handle.read(
                    upToCount:
                        1_048_576
                )


            guard
                let data
            else {
                break
            }


            if data.isEmpty {
                break
            }


            hasher.update(
                data:
                    data
            )
        }


        let digest =
            hasher.finalize()


        return digest
            .map {
                String(
                    format:
                        "%02x",
                    $0
                )
            }
            .joined()
    }


    /// Best-effort BPM lookup across whichever field happens to carry it —
    /// CanonicalTags doesn't cover BPM, so this reaches into the raw
    /// metadata dictionary AudioMetadataKit.read already returns.
    private static func extractBPM(
        from metadata:
            [String: Any]
    ) -> Double? {

        if let vorbis =
            metadata["vorbisComments"]
                as? [String: String],
           let raw =
            vorbis["BPM"] {

            return Double(
                raw
            )
        }


        if let formatSpecific =
            metadata["formatSpecific"]
                as? [String: [String: Any]] {

            for (_, fields) in formatSpecific {

                if let raw =
                    fields["TBPM"]
                        as? String,
                   let value =
                    Double(
                        raw
                    ) {

                    return value
                }
            }
        }


        return nil
    }


    /// Sample rate lookup. Confirmed against AudioTagKit's actual FLACReader source: it's
    /// nested under "streamInfo" (a dict FLACReader.parseStreamInfo builds from the FLAC
    /// STREAMINFO block), not top-level as originally guessed. Other format readers
    /// (MP3/M4A/AIFF) haven't been checked yet — the top-level and formatSpecific fallbacks
    /// below are kept in case one of them surfaces it differently; tighten this once verified
    /// against each reader's actual source, the way FLAC now is.
    private static func extractSampleRate(
        from metadata:
            [String: Any]
    ) -> Int? {

        if let streamInfo =
            metadata["streamInfo"]
                as? [String: Any] {

            if let rate =
                streamInfo["sampleRate"]
                    as? Int {

                return rate
            }

            if let rate =
                streamInfo["sampleRate"]
                    as? Double {

                return Int(
                    rate.rounded()
                )
            }
        }


        if let rate =
            metadata["sampleRate"]
                as? Int {

            return rate
        }


        if let rate =
            metadata["sampleRate"]
                as? Double {

            return Int(
                rate.rounded()
            )
        }


        if let formatSpecific =
            metadata["formatSpecific"]
                as? [String: [String: Any]] {

            for (_, fields) in formatSpecific {

                if let rate =
                    fields["sampleRate"]
                        as? Int {

                    return rate
                }

                if let rate =
                    fields["sampleRate"]
                        as? Double {

                    return Int(
                        rate.rounded()
                    )
                }
            }
        }


        return nil
    }


    /// R128/ReplayGain track-gain lookup, in dB. Confirmed against AudioTagKit's actual
    /// AIFFReader source: ID3 TXXX user-text frames are surfaced as `"TXXX:<description>"`
    /// (e.g. `"TXXX:REPLAYGAIN_TRACK_GAIN"`) inside `formatSpecific["ID3"]`, not as a plain
    /// `"REPLAYGAIN_TRACK_GAIN"` key — the original exact-match version never found it
    /// because of that prefix. Matching by substring instead sidesteps the prefix (and
    /// MP3's AVFoundation-based reader too, in case it surfaces TXXX differently — not yet
    /// checked). FLAC's Vorbis comments still use a plain, unprefixed key, checked separately.
    private static func extractReplayGain(
        from metadata:
            [String: Any]
    ) -> Double? {

        let candidateNames = [
            "R128_TRACK_GAIN",
            "REPLAYGAIN_TRACK_GAIN"
        ]


        func parse(
            _ raw:
                String
        ) -> Double? {

            let trimmed =
                raw
                    .trimmingCharacters(
                        in:
                            .whitespaces
                    )
                    .replacingOccurrences(
                        of:
                            "dB",
                        with:
                            "",
                        options:
                            .caseInsensitive
                    )
                    .trimmingCharacters(
                        in:
                            .whitespaces
                    )

            return Double(
                trimmed
            )
        }


        if let vorbis =
            metadata["vorbisComments"]
                as? [String: String] {

            for name in candidateNames {

                if let raw =
                    vorbis[name],
                   let value =
                    parse(
                        raw
                    ) {

                    return value
                }
            }
        }


        if let formatSpecific =
            metadata["formatSpecific"]
                as? [String: [String: Any]] {

            for (_, fields) in formatSpecific {

                for (key, rawValue) in fields {

                    guard
                        let raw =
                            rawValue as? String
                    else {
                        continue
                    }


                    let upperKey =
                        key.uppercased()


                    if candidateNames.contains(
                        where: {
                            upperKey.contains(
                                $0
                            )
                        }
                    ),
                       let value =
                        parse(
                            raw
                        ) {

                        return value
                    }
                }
            }
        }


        return nil
    }


    /// Parses a plain year out of whatever CanonicalTags.year contains.
    /// That field can hold a bare year ("1956") or a full ID3v2.4/Vorbis
    /// DATE timestamp ("1956-03-15T00:00:00") depending on the tagger —
    /// only the leading 4 digits are used. Deliberately conservative:
    /// anything that isn't 4 plain digits, or falls outside a plausible
    /// recording-year range, parses to nil rather than storing a guess.
    /// (Not yet checked here: MP3 files using ID3's TDRC frame instead of
    /// TYER don't populate CanonicalTags.year at all today — a separate,
    /// known AudioTagKit gap, out of scope for now since MP3 isn't a
    /// current priority.)
    private static func extractYear(
        from rawYear:
            String?
    ) -> Int? {

        guard
            let rawYear,
            rawYear.count >= 4
        else {
            return nil
        }


        let prefix =
            rawYear.prefix(
                4
            )


        guard
            prefix.allSatisfy(
                \.isNumber
            ),
            let year =
                Int(
                    prefix
                )
        else {
            return nil
        }


        guard
            year > 1860 &&
            year <= 2100
        else {
            return nil
        }


        return year
    }
}
