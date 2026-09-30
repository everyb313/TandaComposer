//
//  SmartListFilter.swift
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

/// Applies a SmartListRuleSet to an array of Song, live (no persistence — this is a read-only filter).
///
/// Adjust the field accessors in `value(for:in:)` if your Song model's property names differ
/// (assumed here: title, artist, albumArtist, genre, year).
enum SmartListFilter {

    static func apply(_ ruleSet: SmartListRuleSet, to songs: [Song]) -> [Song] {
        guard !ruleSet.conditions.isEmpty else { return songs }
        return songs.filter { song in
            let results = ruleSet.conditions.map { evaluate($0, song: song) }
            return ruleSet.matchMode == .all ? results.allSatisfy { $0 } : results.contains(true)
        }
    }

    private static func evaluate(_ condition: SmartlistCondition, song: Song) -> Bool {
        switch condition.field {
        case .year:
            return evaluateYear(condition, year: song.year)
        case .songName:
            return evaluateText(condition, text: song.title)
        case .artist:
            return evaluateText(condition, text: song.artist)
        case .albumArtist:
            return evaluateText(condition, text: song.albumArtist)
        case .genre:
            return evaluateText(condition, text: song.genre)
        case .grouping:
            return evaluateText(condition, text: song.grouping)
        }
    }

    private static func evaluateText(_ condition: SmartlistCondition, text: String?) -> Bool {
        // .lowercased() alone only folds case, not diacritics — "Rodríguez"
        // stayed "rodríguez" and never matched a plain-ASCII "rodriguez"
        // needle, even though the same query minus the accented substring
        // ("Rod") matched fine by luck. .folding() with
        // .diacriticInsensitive strips accents too, so "Rodriguez" now
        // matches "Rodríguez" the same way a human typing without special
        // characters would expect.
        let foldingOptions: String.CompareOptions = [.diacriticInsensitive, .caseInsensitive]
        let haystack = (text ?? "").folding(options: foldingOptions, locale: nil)
        let needle = condition.value.folding(options: foldingOptions, locale: nil)
        switch condition.op {
        case .isEqual:      return haystack == needle
        case .isNotEqual:   return haystack != needle
        case .contains:     return needle.isEmpty || haystack.contains(needle)
        case .containsNot:  return !(needle.isEmpty || haystack.contains(needle))
        case .isBetween, .isNotBetween:
            return false // not valid for text fields; UI should prevent this combination
        }
    }

    private static func evaluateYear(_ condition: SmartlistCondition, year: Int?) -> Bool {
        guard let year else { return false }
        switch condition.op {
        case .isEqual:
            guard let target = Int(condition.value) else { return false }
            return year == target
        case .isNotEqual:
            guard let target = Int(condition.value) else { return false }
            return year != target
        case .contains, .containsNot:
            return false // not valid for numeric fields; UI should prevent this combination
        case .isBetween, .isNotBetween:
            guard let lower = Int(condition.value),
                  let upperString = condition.secondValue,
                  let upper = Int(upperString) else { return false }
            let inRange = (lower...upper).contains(year)
            return condition.op == .isBetween ? inRange : !inRange
        }
    }
}
