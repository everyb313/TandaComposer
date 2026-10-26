//
//  SameTitleSelection.swift
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

import Foundation

/// The rows selected in the "Same Title" window: click, Command-click
/// (toggle) and Shift-click (range), like a Finder list. Rows are
/// identified by `Song.normalizedPath`.
public nonisolated struct SameTitleSelection: Equatable {

    public private(set) var keys: Set<String> = []

    /// The row a Shift-click extends from.
    private var anchor: String?

    public init() {}

    public var count: Int {
        keys.count
    }

    public var isEmpty: Bool {
        keys.isEmpty
    }

    public func contains(_ key: String) -> Bool {
        keys.contains(key)
    }

    public mutating func clear() {
        keys = []
        anchor = nil
    }

    /// - Parameters:
    ///   - key: the clicked row.
    ///   - order: every row of the window, top to bottom (Shift ranges
    ///     run through this list, across blocks).
    ///   - command: Command held: add to / remove from the selection.
    ///   - shift: Shift held: select the range from the last click.
    public mutating func click(
        _ key: String,
        in order: [String],
        command: Bool,
        shift: Bool
    ) {

        if shift,
           let anchor,
           let from = order.firstIndex(of: anchor),
           let to = order.firstIndex(of: key) {

            let range = Set(order[min(from, to)...max(from, to)])

            keys = command ? keys.union(range) : range
            return
        }

        if command {

            if keys.contains(key) {
                keys.remove(key)
            } else {
                keys.insert(key)
            }

            anchor = key
            return
        }

        keys = [key]
        anchor = key
    }
}
