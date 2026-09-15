//
//  DuplicateFinder.swift
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

/// The four comparison stages, from loosest to strictest.
enum DuplicateLevel: Int, CaseIterable, Identifiable {

    case songName = 1
    case songArtist = 2
    case songArtistAlbumArtist = 3
    case songArtistAlbumArtistAlbum = 4

    var id: Int { rawValue }

    var title: String {

        switch self {

        case .songName:
            return "Level 1 · Song Name"

        case .songArtist:
            return "Level 2 · Song Name + Artist"

        case .songArtistAlbumArtist:
            return "Level 3 · Song Name + Artist + Album Artist"

        case .songArtistAlbumArtistAlbum:
            return "Level 4 · Song Name + Artist + Album Artist + Album"
        }
    }
}


/// One group of songs that share the same comparison key at a given
/// level — a potential duplicate. Purely informational; nothing here
/// deletes or modifies anything.
struct DuplicateCluster: Identifiable {

    // Deterministic, content-based id (not a random UUID) — keeps
    // SwiftUI's List diffing stable across recomputations of the
    // same underlying data instead of treating every recompute as
    // entirely new rows.
    var id: String { key }

    let key: String

    let songs: [Song]
}


enum DuplicateFinder {

    /// Groups `songs` by the comparison key for `level` (see
    /// `comparisonKey`) and returns every group with more than one
    /// song — i.e. every potential duplicate. Linear in the number
    /// of songs (a single Dictionary(grouping:) pass), not quadratic
    /// — no song is ever compared against another individually.
    static func findClusters(
        in songs: [Song],
        level: DuplicateLevel
    ) -> [DuplicateCluster] {

        let grouped =
            Dictionary(grouping: songs) { song in
                comparisonKey(for: song, level: level)
            }

        return grouped
            .filter { _, songs in songs.count > 1 }
            .map { key, songs in
                DuplicateCluster(key: key, songs: songs)
            }
            .sorted { lhs, rhs in
                lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }
    }


    // MARK: - Comparison Key

    private static func comparisonKey(
        for song: Song,
        level: DuplicateLevel
    ) -> String {

        var parts =
            [normalize(song.title ?? song.filename)]

        if level.rawValue >= 2 {
            parts.append(normalizedOrNil(song.artist))
        }

        if level.rawValue >= 3 {
            parts.append(normalizedOrNil(song.albumArtist))
        }

        if level.rawValue >= 4 {
            parts.append(normalizedOrNil(song.album))
        }

        return parts.joined(separator: "␟")
    }

    /// `nil` and `nil` should match each other (both "not set") —
    /// represented as the same fixed placeholder, distinct from
    /// anything a real tag value could normalize to.
    private static func normalizedOrNil(
        _ value: String?
    ) -> String {

        guard let value else {
            return "␀"
        }

        return normalize(value)
    }

    private static func normalize(
        _ value: String
    ) -> String {

        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
