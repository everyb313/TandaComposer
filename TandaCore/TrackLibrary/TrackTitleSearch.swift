//
//  TrackTitleSearch.swift
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


// MARK: - Track Title Search
//
// The quick search of the TrackLibrary (search field above "Show All").
//
// It is a pure DISPLAY filter: `LibraryStore.songs` always holds the
// whole Library, so everything that looks tracks up in it (Setlist and
// Tanda resolving, Rescans, Duplicate Finder, imports, ...) is never
// affected by an active search. Views apply this on top of
// `LibraryStore.songs`, next to the Smartlist and the A/T/V/M/X filter.
//
// Rules (title only, for now):
//   - Empty / whitespace-only query: no filtering.
//   - ONE character: the title STARTS WITH it (quick jump to a letter).
//   - Two or more characters: the title CONTAINS the query.
//   - Case, diacritics and width are ignored ("a" finds "Ángel").
//   - Leading/trailing whitespace of query and title is ignored.
//   - A song without a title never matches an active search.

public enum TrackTitleSearch {

    public enum Mode: Equatable {
        case inactive
        case startsWith
        case contains
    }

    /// How `query` will be matched. Counts what the user typed
    /// (Characters), not the folded form: folding can change the length
    /// ("ß" -> "ss").
    public static func mode(for query: String) -> Mode {

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch trimmed.count {
        case 0:  return .inactive
        case 1:  return .startsWith
        default: return .contains
        }
    }

    public static func matches(
        title: String?,
        query: String
    ) -> Bool {

        let mode = mode(for: query)

        guard mode != .inactive else {
            return true
        }

        guard let title else {
            return false
        }

        let needle = fold(query)
        let hay = fold(title)

        switch mode {
        case .inactive:   return true
        case .startsWith: return hay.hasPrefix(needle)
        case .contains:   return hay.contains(needle)
        }
    }

    public static func filter(
        _ songs: [Song],
        query: String
    ) -> [Song] {

        guard mode(for: query) != .inactive else {
            return songs
        }

        return songs.filter {
            matches(title: $0.title, query: query)
        }
    }

    private static func fold(_ text: String) -> String {

        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: nil
            )
    }
}
