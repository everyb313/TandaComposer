//
//  TandaImportResolver.swift
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

// MARK: - Model

/// A Tanda that is already in the TandaLibrary (for the duplicate check).
struct ExistingTanda {

    let name: String
    let paths: Set<String>
}

enum TandaImportStatus: Equatable {

    /// Every track found; can be imported.
    case ready

    /// At least one track is missing or ambiguous (reason).
    case needsHelp(String)

    /// The same tracks already form a Tanda (its name).
    case exists(String)

    /// Cannot be a Tanda (reason).
    case notPossible(String)

    /// Saved by this import (where).
    case imported(String)

    /// Saving failed (reason).
    case failed(String)
}

/// One line of a Tanda file and what it was matched to.
struct TandaImportLine: Identifiable {

    let id = UUID()
    let number: Int

    /// The line as written in the file.
    let text: String

    /// The TrackLibrary track, nil when not resolved.
    var song: Song?

    /// How it was resolved, or why not.
    var note: String

    /// Library tracks with the same name, best first. The user can pick
    /// one by hand.
    let candidates: [Song]

    /// `song` was chosen by hand, not by the importer.
    var chosenByUser = false
}

struct TandaImportEntry: Identifiable {

    var id: UUID { shared.id }

    let shared: SharedTanda
    var lines: [TandaImportLine]

    /// The resolved tracks in order (complete only when `.ready`).
    var songs: [Song]

    var status: TandaImportStatus

    /// "Biagi/Acuna/Biagi_Tango_Acuna": where it would be saved.
    var location: String?
}

// MARK: - Resolver

/// Decides for every Tanda of a ZIP whether it can be imported.
///
/// A line counts as resolved when
/// - the path matches exactly (M3U8 with full paths), or
/// - "Auto-pick best file" found the best of several files of the same
///   recording, or
/// - there is exactly ONE candidate whose title, orchestra and singer
///   agree with the line.
/// Everything else needs the user.
enum TandaImportResolver {

    // MARK: Existing Tandas

    /// All Tandas currently on disk, read from the Tandas folder.
    static func loadExisting() -> [ExistingTanda] {

        let fm = FileManager.default
        let root = AppPaths.tandasFolder

        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(
                  at: root,
                  includingPropertiesForKeys: nil
              )
        else {
            return []
        }

        var result: [ExistingTanda] = []

        for case let url as URL in enumerator
        where url.pathExtension.lowercased() == "json" {

            guard let export =
                try? TandaMetadataExporter.load(from: url)
            else {
                continue
            }

            result.append(
                ExistingTanda(
                    name:
                        url.deletingPathExtension()
                            .lastPathComponent,
                    paths:
                        Set(export.songs.map { $0.normalizedPath })
                )
            )
        }

        return result
    }

    // MARK: Evaluate

    static func evaluate(
        _ tandas: [SharedTanda],
        library: [Song],
        orchestraSource: TagSource,
        singerSource: TagSource,
        autoPickBestFile: Bool,
        missingSongIDs: Set<Int64>,
        existing: [ExistingTanda]
    ) -> [TandaImportEntry] {

        // Match all tracks of the folder in one go: the matcher builds
        // its index over the whole Library once instead of per Tanda.
        let allTracks = tandas.flatMap { $0.tracks }

        let allRows =
            SpecialImportPlanner.makeRows(
                tracks: allTracks,
                songs: library,
                orchestraSource: orchestraSource,
                singerSource: singerSource,
                autoPickBestFile: autoPickBestFile
            )

        var offset = 0
        var entries: [TandaImportEntry] = []

        for tanda in tandas {

            let count = tanda.tracks.count

            let rows: [SpecialImportRow]

            if allRows.count == allTracks.count {

                rows = Array(allRows[offset ..< offset + count])

            } else {

                rows =
                    SpecialImportPlanner.makeRows(
                        tracks: tanda.tracks,
                        songs: library,
                        orchestraSource: orchestraSource,
                        singerSource: singerSource,
                        autoPickBestFile: autoPickBestFile
                    )
            }

            offset += count

            entries.append(
                entry(
                    for: tanda,
                    rows: rows,
                    orchestraSource: orchestraSource,
                    singerSource: singerSource,
                    missingSongIDs: missingSongIDs,
                    existing: existing
                )
            )
        }

        return entries
    }

    // MARK: One Tanda

    private static func entry(
        for tanda: SharedTanda,
        rows: [SpecialImportRow],
        orchestraSource: TagSource,
        singerSource: TagSource,
        missingSongIDs: Set<Int64>,
        existing: [ExistingTanda]
    ) -> TandaImportEntry {

        var lines: [TandaImportLine] = []

        for (index, row) in rows.enumerated() {

            let resolution = resolve(
                row,
                orchestraSource: orchestraSource,
                singerSource: singerSource
            )

            lines.append(
                TandaImportLine(
                    number: index + 1,
                    text: lineText(row.track),
                    song: resolution.song,
                    note: resolution.note,
                    candidates: row.candidates
                )
            )
        }

        let songs = lines.compactMap { $0.song }

        return TandaImportEntry(
            shared: tanda,
            lines: lines,
            songs: songs,
            status: status(
                for: tanda,
                lines: lines,
                songs: songs,
                missingSongIDs: missingSongIDs,
                existing: existing
            ),
            location: nil
        )
    }

    /// The entry again, with tracks and status recomputed after the user
    /// changed a line by hand.
    static func refreshed(
        _ entry: TandaImportEntry,
        missingSongIDs: Set<Int64>,
        existing: [ExistingTanda]
    ) -> TandaImportEntry {

        var result = entry

        result.songs = entry.lines.compactMap { $0.song }

        result.status = status(
            for: entry.shared,
            lines: entry.lines,
            songs: result.songs,
            missingSongIDs: missingSongIDs,
            existing: existing
        )

        result.location = nil

        return result
    }

    private static func status(
        for tanda: SharedTanda,
        lines: [TandaImportLine],
        songs: [Song],
        missingSongIDs: Set<Int64>,
        existing: [ExistingTanda]
    ) -> TandaImportStatus {

        let count = lines.count

        guard (3...8).contains(count) else {
            return .notPossible(
                "\(count) tracks — a Tanda has 3 to 8"
            )
        }

        let open = lines.filter { $0.song == nil }

        if let first = open.first {

            let more =
                open.count > 1
                    ? " (+\(open.count - 1) more)"
                    : ""

            return .needsHelp(
                "Track \(first.number): \(first.note)\(more)"
            )
        }

        for song in songs {

            if let id = song.id, missingSongIDs.contains(id) {
                return .notPossible(
                    "File missing on disk: \(song.title ?? song.filename)"
                )
            }
        }

        let paths = Set(songs.map { $0.normalizedPath })

        if let same = existing.first(where: { $0.paths == paths }) {
            return .exists(same.name)
        }

        return .ready
    }

    // MARK: One line

    private static func resolve(
        _ row: SpecialImportRow,
        orchestraSource: TagSource,
        singerSource: TagSource
    ) -> (song: Song?, note: String) {

        switch row.state {

        case .matched:
            if let song = row.chosenSong {
                return (song, "exact path")
            }

        case .autoPicked:
            if let song = row.chosenSong {
                return (song, "best of several files")
            }

        case .chosen, .skipped, .open:
            break
        }

        let candidates = row.candidates

        if candidates.isEmpty {
            return (nil, "not in your TrackLibrary")
        }

        if candidates.count == 1 {

            let song = candidates[0]

            if agrees(
                song,
                with: row.track,
                orchestraSource: orchestraSource,
                singerSource: singerSource
            ) {
                return (song, "only match")
            }

            return (
                nil,
                "the only match differs in title, orchestra or singer"
            )
        }

        return (nil, "\(candidates.count) different candidates")
    }

    /// Title, orchestra and singer of the library track agree with the
    /// line. The orchestra is required; the singer only when the line
    /// has one.
    private static func agrees(
        _ song: Song,
        with track: ImportedTrack,
        orchestraSource: TagSource,
        singerSource: TagSource
    ) -> Bool {

        guard let lineTitle =
                TrackTextNormalizer.normalize(track.title),
              let songTitle =
                TrackTextNormalizer.normalize(song.title),
              lineTitle == songTitle
        else {
            return false
        }

        guard let orchestra = track.artist,
              sameName(
                  orchestra,
                  song.rawTagValue(for: orchestraSource)
              )
        else {
            return false
        }

        if let singer = track.singer, !singer.isEmpty {

            let tagValue = song.rawTagValue(for: singerSource)

            if SpecialImportPlanner.singerKey(singer) == nil {

                // The line says "instrumental": the track must have no
                // singer either ("Instrumental", "instr." and empty
                // all count as none).
                guard SpecialImportPlanner.singerKey(tagValue) == nil
                else {
                    return false
                }

            } else {

                guard sameName(singer, tagValue) else {
                    return false
                }
            }
        }

        return true
    }

    /// "Biagi, Rodolfo" = "Rodolfo Biagi" = "Biagi": equal after
    /// normalizing, or all words of one are words of the other.
    private static func sameName(
        _ a: String,
        _ b: String?
    ) -> Bool {

        guard let b,
              let normalizedA = TrackTextNormalizer.normalize(a),
              let normalizedB = TrackTextNormalizer.normalize(b)
        else {
            return false
        }

        if normalizedA == normalizedB {
            return true
        }

        let wordsA = words(of: normalizedA)
        let wordsB = words(of: normalizedB)

        guard !wordsA.isEmpty, !wordsB.isEmpty else {
            return false
        }

        return wordsA.isSubset(of: wordsB)
            || wordsB.isSubset(of: wordsA)
    }

    private static func words(of text: String) -> Set<String> {

        Set(
            text
                .components(
                    separatedBy:
                        CharacterSet.alphanumerics.inverted
                )
                .filter { !$0.isEmpty }
        )
    }

    private static func lineText(_ track: ImportedTrack) -> String {

        if let source = track.sourceDisplayName, !source.isEmpty {
            return source
        }

        return [track.artist, track.title]
            .compactMap { $0 }
            .joined(separator: " - ")
    }
}
