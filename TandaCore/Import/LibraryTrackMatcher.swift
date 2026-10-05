//
//  LibraryTrackMatcher.swift
//
//  Copyright © 2026 Hagen Eckert.
//

import Foundation

/// Matches tracks described by an external playlist against the current
/// TrackLibrary.
///
/// The matcher never creates or mutates Song values. Every successful
/// candidate always points at an existing current-library Song.
public struct LibraryTrackMatcher {

    public enum MatchStatus: Equatable {
        case exact
        case confident
        case ambiguous
        case unmatched
    }

    public enum MatchedField: Equatable {
        case libraryID
        case fileHash
        case path
        case title
        case orchestra
        case singer
        case album
        case duration
        case bpm
        case key
        case filename
    }

    public struct Candidate: Equatable {

        public let song: Song
        public let score: Int
        public let matchedFields: [MatchedField]

        public init(
            song: Song,
            score: Int,
            matchedFields: [MatchedField]
        ) {
            self.song = song
            self.score = score
            self.matchedFields = matchedFields
        }
    }

    public struct Result: Equatable {

        public let importedTrack: ImportedTrack
        public let candidates: [Candidate]
        public let status: MatchStatus

        public var bestCandidate: Candidate? {
            candidates.first
        }

        public init(
            importedTrack: ImportedTrack,
            candidates: [Candidate],
            status: MatchStatus
        ) {
            self.importedTrack = importedTrack
            self.candidates = candidates
            self.status = status
        }
    }

    private let byID: [Int64: Song]
    private let byPath: [String: Song]
    private let byHash: [String: [Song]]
    private let byTitle: [String: [Song]]
    private let byFilename: [String: [Song]]

    private let orchestraSource: TagSource
    private let singerSource: TagSource
    private let trustLibraryID: Bool

    private let roleCache = RoleCache()

    /// - Parameter trustLibraryID: Whether `ImportedTrack.libraryID`
    ///   refers to THIS library. Song IDs are auto-incremented per
    ///   database, so an ID from another library is a coincidence, not
    ///   an identity, and would silently pick the wrong song. Leave it
    ///   `false` for anything that did not come from the active
    ///   TrackLibrary (see `LibraryReferenceResolver` / `trustID`).
    public init(
        songs: [Song],
        orchestraSource: TagSource = .artist,
        singerSource: TagSource = .albumArtist,
        trustLibraryID: Bool = false
    ) {
        self.orchestraSource = orchestraSource
        self.singerSource = singerSource
        self.trustLibraryID = trustLibraryID

        var byID: [Int64: Song] = [:]
        var byPath: [String: Song] = [:]
        var byHash: [String: [Song]] = [:]
        var byTitle: [String: [Song]] = [:]
        var byFilename: [String: [Song]] = [:]

        for song in songs {

            if let id = song.id {
                byID[id] = song
            }

            if !song.normalizedPath.isEmpty {
                byPath[song.normalizedPath] = song
            }

            if let hash = TrackTextNormalizer.normalize(
                song.fileHash
            ) {
                byHash[hash, default: []].append(song)
            }

            if let title = TrackTextNormalizer.normalize(
                song.title
            ) {
                byTitle[title, default: []].append(song)
            }

            if let filename =
                TrackTextNormalizer.normalizeFilename(
                    song.filename
                )
            {
                byFilename[filename, default: []].append(song)
            }
        }

        self.byID = byID
        self.byPath = byPath
        self.byHash = byHash
        self.byTitle = byTitle
        self.byFilename = byFilename
    }

    /// Matches every imported track while preserving source order.
    public func matchAll(
        _ importedTracks: [ImportedTrack]
    ) -> [Result] {
        importedTracks.map(match)
    }

    /// Matches one imported track.
    public func match(
        _ importedTrack: ImportedTrack
    ) -> Result {

        // 1. Library ID — only when the caller vouches that it belongs
        //    to this library.
        if trustLibraryID,
           let id = importedTrack.libraryID,
           let song = byID[id]
        {
            return Result(
                importedTrack: importedTrack,
                candidates: [
                    Candidate(
                        song: song,
                        score: 10_000,
                        matchedFields: [.libraryID]
                    )
                ],
                status: .exact
            )
        }

        // 2. File hash.
        if let hash = TrackTextNormalizer.normalize(
            importedTrack.fileHash
        ),
           let matches = byHash[hash],
           !matches.isEmpty
        {
            let candidates = matches.map {
                Candidate(
                    song: $0,
                    score: 9_000,
                    matchedFields: [.fileHash]
                )
            }

            return Result(
                importedTrack: importedTrack,
                candidates: candidates,
                status: matches.count == 1
                    ? .exact
                    : .ambiguous
            )
        }

        // 3. Exact normalized path.
        if let path = importedTrack.path {

            let normalized = PathNormalizer.normalize(path)

            if let song = byPath[normalized] {
                return Result(
                    importedTrack: importedTrack,
                    candidates: [
                        Candidate(
                            song: song,
                            score: 8_000,
                            matchedFields: [.path]
                        )
                    ],
                    status: .exact
                )
            }
        }

        // 4. Metadata matching.
        let profile = TrackMetadataProfile(
            importedTrack: importedTrack,
            orchestraSource: orchestraSource,
            singerSource: singerSource
        )

        var candidates: [Song] = []

        if let title = TrackTextNormalizer.normalize(
            profile.title
        ) {
            candidates = byTitle[title] ?? []
        }

        // If there is no title, filename can still produce candidates.
        if candidates.isEmpty,
           let filename =
            TrackTextNormalizer.normalizeFilename(
                profile.filename
            )
        {
            candidates = byFilename[filename] ?? []
        }

        // A recognized orchestra/singer is a hard constraint. It is not
        // merely a scoring hint: once the source identifies a known role,
        // candidates from another orchestra/singer must not be shown.
        candidates = filterByRecognizedRoles(
            candidates,
            profile: profile
        )

        guard !candidates.isEmpty else {
            return Result(
                importedTrack: importedTrack,
                candidates: [],
                status: .unmatched
            )
        }

        let scored = candidates
            .map {
                score(
                    profile: profile,
                    importedTrack: importedTrack,
                    song: $0
                )
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }

                return (
                    $0.song.id ?? Int64.max
                ) < (
                    $1.song.id ?? Int64.max
                )
            }

        guard let best = scored.first else {
            return Result(
                importedTrack: importedTrack,
                candidates: [],
                status: .unmatched
            )
        }

        let secondScore = scored.dropFirst().first?.score

        let status: MatchStatus

        if best.score >= 500 &&
            (
                secondScore == nil ||
                best.score - secondScore! >= 120
            )
        {
            status = .confident
        } else {
            status = .ambiguous
        }

        return Result(
            importedTrack: importedTrack,
            candidates: scored,
            status: status
        )
    }

    /// Filters candidates using only roles that were positively recognized
    /// from the Tracklib reference data. Unknown/free-form artist text is
    /// deliberately ignored, so we do not turn uncertain metadata into a
    /// false negative.
    public func filterCandidates(
        _ songs: [Song],
        for importedTrack: ImportedTrack
    ) -> [Song] {
        let profile = TrackMetadataProfile(
            importedTrack: importedTrack,
            orchestraSource: orchestraSource,
            singerSource: singerSource
        )

        return filterByRecognizedRoles(
            songs,
            profile: profile
        )
    }

    private func filterByRecognizedRoles(
        _ songs: [Song],
        profile: TrackMetadataProfile
    ) -> [Song] {
        let recognizedOrchestras = recognizedReferenceNames(
            values: profile.orchestraValues,
            kind: .orchestra
        )

        let recognizedSingers = recognizedReferenceNames(
            values: profile.singerValues,
            kind: .singer
        )

        // No recognized role -> keep the old broad title/filename search.
        if recognizedOrchestras.isEmpty && recognizedSingers.isEmpty {
            return songs
        }

        return songs.filter { song in
            let roles = recognizedRoles(of: song)

            if !recognizedOrchestras.isEmpty,
               recognizedOrchestras.isDisjoint(with: roles.orchestras) {
                return false
            }

            if !recognizedSingers.isEmpty,
               recognizedSingers.isDisjoint(with: roles.singers) {
                return false
            }

            return true
        }
    }

    private func recognizedReferenceNames(
        values: [String],
        kind: TracklibImportReferenceStore.Kind
    ) -> Set<String> {
        var result = Set<String>()

        for value in values {
            let matches = TracklibImportReferenceStore.matches(
                in: value.precomposedStringWithCanonicalMapping,
                kind: kind
            )

            for match in matches {
                if let normalized = TrackTextNormalizer.normalize(match.entry.name) {
                    result.insert(normalized)
                }
            }
        }

        return result
    }

    // MARK: - Per-song role cache

    private struct RecognizedRoles {
        let orchestras: Set<String>
        let singers: Set<String>
    }

    /// Library tags do not change while one matcher lives, and the same
    /// songs are filtered again for every imported line. Recognizing
    /// them once is what keeps a long import list fast.
    private final class RoleCache {

        private let lock = NSLock()
        private var storage: [Int64: RecognizedRoles] = [:]

        func roles(
            for id: Int64,
            compute: () -> RecognizedRoles
        ) -> RecognizedRoles {

            lock.lock()
            let cached = storage[id]
            lock.unlock()

            if let cached {
                return cached
            }

            let value = compute()

            lock.lock()
            storage[id] = value
            lock.unlock()

            return value
        }
    }

    private func recognizedRoles(of song: Song) -> RecognizedRoles {

        let compute = { () -> RecognizedRoles in
            let profile = TrackMetadataProfile(
                song: song,
                orchestraSource: orchestraSource,
                singerSource: singerSource
            )

            return RecognizedRoles(
                orchestras: recognizedReferenceNames(
                    values: profile.orchestraValues,
                    kind: .orchestra
                ),
                singers: recognizedReferenceNames(
                    values: profile.singerValues,
                    kind: .singer
                )
            )
        }

        guard let id = song.id else {
            return compute()
        }

        return roleCache.roles(for: id, compute: compute)
    }

    private func score(
        profile: TrackMetadataProfile,
        importedTrack: ImportedTrack,
        song: Song
    ) -> Candidate {

        var score = 0
        var fields: [MatchedField] = []

        // Title.
        if TrackTextNormalizer.equals(
            profile.title,
            song.title
        ) {
            score += 400
            fields.append(.title)
        }

        let libraryProfile = TrackMetadataProfile(
            song: song,
            orchestraSource: orchestraSource,
            singerSource: singerSource
        )

        // Orchestra.
        if roleMatch(
            importedValues: profile.orchestraValues,
            libraryValues: libraryProfile.orchestraValues
        ) {
            score += 260
            fields.append(.orchestra)
        }

        // Singer.
        if roleMatch(
            importedValues: profile.singerValues,
            libraryValues: libraryProfile.singerValues
        ) {
            score += 220
            fields.append(.singer)
        }

        // Album.
        if TrackTextNormalizer.equals(
            profile.album,
            song.album
        ) {
            score += 70
            fields.append(.album)
        }

        // Duration.
        if let importedDuration = profile.duration,
           let libraryDuration = song.duration
        {
            let delta = abs(
                importedDuration - libraryDuration
            )

            if delta == 0 {
                score += 90
                fields.append(.duration)
            } else if delta <= 1 {
                score += 65
                fields.append(.duration)
            } else if delta <= 3 {
                score += 30
                fields.append(.duration)
            }
        }

        // BPM.
        if let importedBPM = profile.bpm,
           let libraryBPM = song.bpm
        {
            let delta = abs(
                importedBPM - libraryBPM
            )

            if delta < 0.01 {
                score += 45
                fields.append(.bpm)
            } else if delta <= 1.0 {
                score += 25
                fields.append(.bpm)
            }
        }

        // Key.
        if TrackTextNormalizer.equals(
            profile.key,
            song.key
        ) {
            score += 25
            fields.append(.key)
        }

        // Filename.
        if TrackTextNormalizer.equals(
            profile.filename,
            song.filename
        ) {
            score += 35
            fields.append(.filename)
        }

        // Filename from imported path.
        if let importedPath = importedTrack.path,
           TrackTextNormalizer.equals(
                TrackTextNormalizer.normalizeFilename(
                    importedPath
                ),
                TrackTextNormalizer.normalizeFilename(
                    song.path
                )
           )
        {
            score += 20

            if !fields.contains(.filename) {
                fields.append(.filename)
            }
        }

        return Candidate(
            song: song,
            score: score,
            matchedFields: fields
        )
    }

    private func roleMatch(
        importedValues: [String],
        libraryValues: [String]
    ) -> Bool {

        importedValues.contains { imported in
            libraryValues.contains { library in
                TrackTextNormalizer.equals(
                    imported,
                    library
                )
            }
        }
    }
}
