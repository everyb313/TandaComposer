//
//  SmartListRuleSet.swift
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

/// A single field a Smartlist condition can filter on.
enum SmartlistField: String, Codable, CaseIterable, Identifiable {
    case songName
    case artist
    case albumArtist      // maps to Song.albumArtist (vocalist, in tango-tagging convention)
    case genre
    case year
    case grouping

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .songName:     return "Title"
        case .artist:       return "Orchestra"
        case .albumArtist:  return "Singer"
        case .genre:        return "Genre"
        case .year:         return "Year"
        case .grouping:     return "Grouping"
        }
    }

    /// Whether this field is numeric (enables isBetween/isNotBetween).
    var isNumeric: Bool { self == .year }
}

enum SmartlistOperator: String, Codable, CaseIterable, Identifiable {
    case isEqual
    case isNotEqual
    case isBetween
    case isNotBetween
    case contains
    case containsNot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .isEqual:      return "is"
        case .isNotEqual:   return "is not"
        case .isBetween:    return "is between"
        case .isNotBetween: return "is not between"
        case .contains:     return "contains"
        case .containsNot:  return "does not contain"
        }
    }

    /// Operators valid for a given field (isBetween/isNotBetween only for numeric fields).
    static func validOperators(for field: SmartlistField) -> [SmartlistOperator] {
        field.isNumeric
            ? [.isEqual, .isNotEqual, .isBetween, .isNotBetween]
            : [.isEqual, .isNotEqual, .contains, .containsNot]
    }
}

enum SmartlistMatchMode: String, Codable, CaseIterable, Identifiable {
    case all
    case any

    var id: String { rawValue }
    var displayName: String { self == .all ? "all" : "any" }
}

struct SmartlistCondition: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var field: SmartlistField
    var op: SmartlistOperator
    /// Primary value. For text fields: the match string. For isBetween/isNotBetween on year: the lower bound.
    var value: String
    /// Only used when op is isBetween/isNotBetween: the upper bound.
    var secondValue: String?
}

/// One rule set = one "smart playlist file" on disk.
struct SmartListRuleSet: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var matchMode: SmartlistMatchMode = .all
    var conditions: [SmartlistCondition] = []
}
