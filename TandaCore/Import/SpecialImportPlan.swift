//
//  SpecialImportPlan.swift
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

// MARK: - Special Import Row

/// One line of an M3U8 file in the manual "Special Import" stage.
///
/// - An exact path match is adopted automatically (`autoMatched`).
/// - Otherwise `candidates` holds the same-named Library tracks and the
///   user picks one by hand. Nothing is preselected, not even when there
///   is only a single candidate.
/// - One exception, only when "Auto-pick best file" is on: if all
///   candidates are the SAME recording in different files, the best file
///   is suggested (`autoPicked`). The user can always remove it.
///
/// Every song a row can end up with is a current-Library `Song`, never
/// a snapshot from the imported file.
public struct SpecialImportRow: Identifiable, Equatable {

    public enum State: Equatable {
        /// Exact path match, adopted automatically.
        case matched
        /// Picked manually from the candidates.
        case chosen
        /// Suggested because the same recording exists in several
        /// files; not yet confirmed by the user.
        case autoPicked
        /// No decision yet.
        case open
        /// Left out of the new Setlist.
        case skipped
    }

    public var id: UUID { track.id }

    public let track: ImportedTrack

    /// Same-named Library tracks, best match first. Empty for
    /// auto-matched rows.
    public let candidates: [Song]

    public let autoMatched: Bool

    public private(set) var chosenSong: Song?

    public private(set) var isSkipped: Bool

    /// `chosenSong` was suggested by "Auto-pick best file", not picked
    /// by the user.
    public private(set) var isAutoPicked: Bool

    public init(
        track: ImportedTrack,
        candidates: [Song],
        autoMatched: Bool,
        chosenSong: Song?,
        autoPicked: Bool = false
    ) {
        self.track = track
        self.candidates = candidates
        self.autoMatched = autoMatched
        self.chosenSong = chosenSong
        self.isSkipped = false
        self.isAutoPicked = autoPicked && chosenSong != nil
    }

    public var state: State {

        if isSkipped {
            return .skipped
        }

        if chosenSong != nil {

            if autoMatched {
                return .matched
            }

            return isAutoPicked ? .autoPicked : .chosen
        }

        return .open
    }

    /// The song this row contributes to the new Setlist, if any.
    public var adoptedSong: Song? {
        isSkipped ? nil : chosenSong
    }

    /// Short human-readable description of the source line.
    public var sourceTitle: String {

        if let title = track.title, !title.isEmpty {

            if let artist = track.artist, !artist.isEmpty {
                return "\(artist) – \(title)"
            }

            return title
        }

        return track.sourceDisplayName
            ?? track.filename
            ?? "(unnamed)"
    }

    // MARK: Decisions

    /// Picks `song` — only meaningful for rows with candidates.
    public mutating func choose(_ song: Song) {
        chosenSong = song
        isAutoPicked = false
        isSkipped = false
    }

    /// Undoes a manual choice. Auto-matched rows keep their match.
    public mutating func clearChoice() {

        guard !autoMatched else {
            return
        }

        chosenSong = nil
        isAutoPicked = false
    }

    public mutating func setSkipped(_ skipped: Bool) {
        isSkipped = skipped
    }
}


// MARK: - Planner

public enum SpecialImportPlanner {

    /// Builds one row per imported track, preserving source order.
    ///
    /// Stage 1: exact normalized path → adopted.
    /// Stage 2: same-named Library tracks as candidates. Besides the
    /// title, the file name without suffix is compared, and for lines
    /// like "Artist - Title" or "01 - Title" the pieces are tried as
    /// well. The scoring in `LibraryTrackMatcher` only sorts the
    /// candidates; it never decides anything here.
    public static func makeRows(
        tracks: [ImportedTrack],
        songs: [Song],
        orchestraSource: TagSource,
        singerSource: TagSource,
        autoPickBestFile: Bool = false
    ) -> [SpecialImportRow] {

        let matcher = LibraryTrackMatcher(
            songs: songs,
            orchestraSource: orchestraSource,
            singerSource: singerSource
        )

        let index = FilenameIndex(songs: songs)

        return tracks.map { track in

            let first = matcher.match(track)

            // Exact path match.
            if first.status == .exact,
               let best = first.bestCandidate
            {
                return SpecialImportRow(
                    track: track,
                    candidates: [],
                    autoMatched: true,
                    chosenSong: best.song
                )
            }

            var found: [ScoredSong] =
                first.candidates.map {
                    ScoredSong(song: $0.song, score: $0.score)
                }

            var shown = track

            if found.isEmpty {

                let fallback = fallbackCandidates(
                    for: track,
                    matcher: matcher,
                    index: index
                )

                found = fallback.songs

                // The line was "Title - Artist" although read the
                // other way round: show it the way it matched.
                if let variant = fallback.variant,
                   let artist = variant.artist
                {
                    shown = track.replacing(
                        title: variant.title,
                        artist: artist
                    )
                }
            }

            let ranked = rank(
                found,
                for: shown,
                singerSource: singerSource
            )

            let picked =
                autoPickBestFile
                    ? bestFile(
                        among: ranked,
                        orchestraSource: orchestraSource,
                        singerSource: singerSource
                    )
                    : nil

            return SpecialImportRow(
                track: shown,
                candidates: ranked,
                autoMatched: false,
                chosenSong: picked,
                autoPicked: picked != nil
            )
        }
    }

    // MARK: Auto-pick best file

    /// The one best file, when `candidates` are all the SAME recording
    /// stored in several files — nil otherwise.
    ///
    /// Same title is not enough ("Poema" exists in many versions), so
    /// the candidates must agree on title, orchestra and singer, have
    /// lengths within a few seconds of each other (copies of one
    /// recording differ slightly), and share the year where one is
    /// given. Several different recordings, a single candidate, or two
    /// equally good files all give nil: the user then decides, as
    /// before.
    ///
    /// Preference: FLAC (higher sample rate first), then AIFF at 96, 48
    /// and 44.1 kHz, then other AIFF, then everything else.
    /// Longest allowed difference, in seconds, between the shortest and
    /// the longest copy. Copies of one recording from different sources
    /// differ by a few seconds (2:18 / 2:16 / 2:15); other recordings of
    /// the same tango differ by far more.
    private static let maxLengthSpread = 5

    static func bestFile(
        among candidates: [Song],
        orchestraSource: TagSource,
        singerSource: TagSource
    ) -> Song? {

        guard candidates.count >= 2,
              let first = candidates.first
        else {
            return nil
        }

        for other in candidates.dropFirst() {

            guard isSameRecording(
                first,
                other,
                orchestraSource: orchestraSource,
                singerSource: singerSource
            ) else {
                return nil
            }
        }

        // Every copy needs a length, and the lengths must be close.
        let lengths = candidates.compactMap { $0.duration }

        guard lengths.count == candidates.count,
              let longest = lengths.max(),
              let shortest = lengths.min(),
              longest - shortest <= maxLengthSpread
        else {
            return nil
        }

        // Different years are different recordings. A missing year
        // says nothing.
        guard Set(candidates.compactMap { $0.year }).count <= 1 else {
            return nil
        }

        let ranked = candidates
            .map { (song: $0, key: filePreference($0)) }
            .sorted {
                $0.key.group != $1.key.group
                    ? $0.key.group < $1.key.group
                    : $0.key.rate < $1.key.rate
            }

        // An unambiguous winner only.
        if ranked[0].key.group == ranked[1].key.group,
           ranked[0].key.rate == ranked[1].key.rate
        {
            return nil
        }

        return ranked[0].song
    }

    private static func isSameRecording(
        _ a: Song,
        _ b: Song,
        orchestraSource: TagSource,
        singerSource: TagSource
    ) -> Bool {

        guard let titleA = TrackTextNormalizer.normalize(a.title),
              let titleB = TrackTextNormalizer.normalize(b.title),
              titleA == titleB
        else {
            return false
        }

        return TrackTextNormalizer.normalize(
                a.rawTagValue(for: orchestraSource)
            ) == TrackTextNormalizer.normalize(
                b.rawTagValue(for: orchestraSource)
            )
            && TrackTextNormalizer.normalize(
                a.rawTagValue(for: singerSource)
            ) == TrackTextNormalizer.normalize(
                b.rawTagValue(for: singerSource)
            )
    }

    /// Lower is better: group first, then `rate` (negated sample rate,
    /// so a higher sample rate sorts first).
    private static func filePreference(
        _ song: Song
    ) -> (group: Int, rate: Int) {

        let rate = song.sampleRate ?? 0

        switch (song.fileType ?? "").uppercased() {

        case "FLAC":
            return (0, -rate)

        case "AIFF", "AIF":

            switch rate {
            case 96_000: return (1, 0)
            case 48_000: return (2, 0)
            case 44_100: return (3, 0)
            default: return (4, -rate)
            }

        default:
            return (5, 0)
        }
    }

    /// Songs for the new Setlist, in source order. Skipped and still
    /// open rows contribute nothing.
    public static func adoptedSongs(
        from rows: [SpecialImportRow]
    ) -> [Song] {
        rows.compactMap(\.adoptedSong)
    }

    // MARK: Fallback search

    /// Tried only when the parsed title found nothing. The first name
    /// variant that yields any track wins; tracks whose file name
    /// (without suffix) equals the variant come first.
    private static func fallbackCandidates(
        for track: ImportedTrack,
        matcher: LibraryTrackMatcher,
        index: FilenameIndex
    ) -> (songs: [ScoredSong], variant: NameVariant?) {

        for variant in nameVariants(for: track) {

            // Same file name (without suffix): strongest evidence.
            var hits: [ScoredSong] =
                matcher.filterCandidates(
                    index.songs(forFilenameStem: variant.title),
                    for: track.replacing(
                        title: variant.title,
                        artist: variant.artist
                    )
                )
                .map { ScoredSong(song: $0, score: 1_000) }

            let retry = matcher.match(
                track.replacing(
                    title: variant.title,
                    artist: variant.artist
                )
            )

            hits.append(
                contentsOf: retry.candidates.map {
                    ScoredSong(song: $0.song, score: $0.score)
                }
            )

            let unique = uniqueScored(hits)

            if !unique.isEmpty {
                return (unique, variant)
            }
        }

        return ([], nil)
    }

    // MARK: Ordering

    private struct ScoredSong {
        let song: Song
        let score: Int
    }

    /// Orders candidates by the matcher's score plus small hints from
    /// the source line: recording year and singer. Ties keep the
    /// matcher's order. Only the order changes, never the content.
    private static func rank(
        _ scored: [ScoredSong],
        for track: ImportedTrack,
        singerSource: TagSource
    ) -> [Song] {

        let unique = uniqueScored(scored)

        let boosted: [(offset: Int, song: Song, score: Int)] =
            unique.enumerated().map { entry in
                (
                    offset: entry.offset,
                    song: entry.element.song,
                    score:
                        entry.element.score
                        + hintBoost(
                            entry.element.song,
                            track: track,
                            singerSource: singerSource
                        )
                )
            }

        return boosted
            .sorted {
                $0.score != $1.score
                    ? $0.score > $1.score
                    : $0.offset < $1.offset
            }
            .map { $0.song }
    }

    private static func hintBoost(
        _ song: Song,
        track: ImportedTrack,
        singerSource: TagSource
    ) -> Int {

        var boost = 0

        if let wanted = track.year,
           let actual = song.year
        {
            switch abs(wanted - actual) {

            case 0:
                boost += 90

            case 1:
                boost += 45

            default:
                break
            }
        }

        if let wanted =
            TrackTextNormalizer.normalize(track.singer),
           let actual =
            TrackTextNormalizer.normalize(
                song.rawTagValue(for: singerSource)
            ),
           actual.contains(wanted) || wanted.contains(actual)
        {
            boost += 220
        }

        return boost
    }

    private struct NameVariant {
        let title: String
        let artist: String?
    }

    /// Other readings of the same source line, most specific first:
    /// the whole text, the text without a leading track number
    /// ("01 - "), then "Artist - Title" splits.
    private static func nameVariants(
        for track: ImportedTrack
    ) -> [NameVariant] {

        var texts: [String] = []

        func addText(_ value: String?) {

            guard let value else {
                return
            }

            let stem =
                AudioFileSuffix.strip(value).stem
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            guard !stem.isEmpty,
                  !texts.contains(
                    where: { TrackTextNormalizer.equals($0, stem) }
                  )
            else {
                return
            }

            texts.append(stem)
        }

        addText(track.title)
        addText(track.sourceDisplayName)
        addText(track.filename)

        var variants: [NameVariant] = []

        func add(_ title: String, _ artist: String?) {

            let duplicate = variants.contains { existing in

                guard TrackTextNormalizer.equals(
                    existing.title,
                    title
                ) else {
                    return false
                }

                switch (existing.artist, artist) {

                case (nil, nil):
                    return true

                case let (lhs?, rhs?):
                    return TrackTextNormalizer.equals(lhs, rhs)

                default:
                    return false
                }
            }

            if !duplicate {
                variants.append(
                    NameVariant(title: title, artist: artist)
                )
            }
        }

        var allTexts: [String] = []

        for text in texts {

            add(text, nil)
            allTexts.append(text)

            if let stripped = withoutLeadingNumber(text) {
                add(stripped, nil)
                allTexts.append(stripped)
            }
        }

        // The same readings without trailing "(1936)" / "(Gesang: …)".
        for text in allTexts {

            if let stripped = withoutTrailingBrackets(text) {
                add(stripped, nil)
                allTexts.append(stripped)
            }
        }

        for text in allTexts {

            for split in artistTitleSplits(of: text) {
                add(split.title, split.artist)
            }
        }

        return variants
    }

    /// "01 - Poema" → "Poema". Nil when there is no leading number.
    private static func withoutLeadingNumber(
        _ text: String
    ) -> String? {

        let stripped =
            text.replacingOccurrences(
                of: #"^\s*\d{1,3}\s*[-.)]\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !stripped.isEmpty, stripped != text else {
            return nil
        }

        return stripped
    }

    /// "Poema (Gesang: X) (1935)" → "Poema". Nil when nothing changes.
    private static func withoutTrailingBrackets(
        _ text: String
    ) -> String? {

        var result = text

        while let range = result.range(
            of: #"\s*[(\[][^()\[\]]*[)\]]\s*$"#,
            options: .regularExpression
        ) {
            result.removeSubrange(range)
        }

        result =
            result.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty, result != text else {
            return nil
        }

        return result
    }

    /// "A - B" read both ways: (title B, artist A) first, then
    /// (title A, artist B). With more parts also the last two, as in
    /// "01 - A - B". Which way is right is decided by the Library
    /// finding something, not here.
    private static func artistTitleSplits(
        of text: String
    ) -> [(title: String, artist: String)] {

        let unified =
            text
                .replacingOccurrences(of: " \u{2013} ", with: " - ")
                .replacingOccurrences(of: " \u{2014} ", with: " - ")

        let parts =
            unified
                .components(separatedBy: " - ")
                .map {
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                }
                .filter { !$0.isEmpty }

        guard parts.count >= 2 else {
            return []
        }

        var result: [(title: String, artist: String)] = [
            (
                title: parts.dropFirst().joined(separator: " - "),
                artist: parts[0]
            )
        ]

        if parts.count >= 3 {

            result.append(
                (
                    title: parts[parts.count - 1],
                    artist: parts[parts.count - 2]
                )
            )
        }

        // Reversed: "Title - Artist".
        result.append(
            (
                title: parts.dropLast().joined(separator: " - "),
                artist: parts[parts.count - 1]
            )
        )

        return result
    }

    // MARK: Helpers

    private static func uniqueScored(
        _ items: [ScoredSong]
    ) -> [ScoredSong] {

        var seen = Set<Int64>()
        var result: [ScoredSong] = []

        for item in items {

            if let id = item.song.id {

                guard seen.insert(id).inserted else {
                    continue
                }
            }

            result.append(item)
        }

        return result
    }

    /// Library tracks by file name without a known audio suffix.
    private struct FilenameIndex {

        private let byStem: [String: [Song]]

        init(songs: [Song]) {

            var map: [String: [Song]] = [:]

            for song in songs {

                let stem = AudioFileSuffix.strip(song.filename).stem

                if let key = TrackTextNormalizer.normalize(stem) {
                    map[key, default: []].append(song)
                }
            }

            byStem = map
        }

        func songs(forFilenameStem name: String) -> [Song] {

            guard let key = TrackTextNormalizer.normalize(name) else {
                return []
            }

            return byStem[key] ?? []
        }
    }
}


private extension ImportedTrack {

    func replacing(
        title newTitle: String?,
        artist newArtist: String?
    ) -> ImportedTrack {

        ImportedTrack(
            id: id,
            sourceIndex: sourceIndex,
            path: path,
            filename: filename,
            title: newTitle,
            artist: newArtist ?? artist,
            albumArtist: albumArtist,
            grouping: grouping,
            album: album,
            duration: duration,
            bpm: bpm,
            key: key,
            fileHash: fileHash,
            libraryID: libraryID,
            sourceDisplayName: sourceDisplayName,
            year: year,
            singer: singer
        )
    }
}
