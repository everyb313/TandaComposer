//
//  SongSortComparator.swift
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

import SwiftUI
import AppKit

// MARK: - Library table sorting
//
// Pure comparator factory for the library table's columns — no
// AppKit, so it can be unit-tested on its own. Column keys are the
// NSTableColumn identifiers (`LibraryColumn.rawValue` / "Status").

enum SongSortComparator {

    static func make(
        forKey key: String,
        ascending: Bool,
        settings: AppSettings,
        missingSongIDs: Set<Int64>
    ) -> (Song, Song) -> Bool {

        func order<T: Comparable>(
            _ a: T,
            _ b: T
        ) -> Bool {

            ascending
            ? a < b
            : a > b
        }


        switch key {

        case "Title":

            return {
                order(
                    $0.title ?? "",
                    $1.title ?? ""
                )
            }

        case "Orchestra":

            return {
                order(
                    $0.resolvedOrchestra(using: settings) ?? "",
                    $1.resolvedOrchestra(using: settings) ?? ""
                )
            }

        case "Singer":

            return {
                order(
                    $0.resolvedSinger(using: settings) ?? "",
                    $1.resolvedSinger(using: settings) ?? ""
                )
            }

        case "Album":

            return {
                order(
                    $0.album ?? "",
                    $1.album ?? ""
                )
            }

        case "Genre":

            return {
                order(
                    $0.genre ?? "",
                    $1.genre ?? ""
                )
            }

        case "Year":

            return {
                order(
                    $0.year ?? 0,
                    $1.year ?? 0
                )
            }

        case "Type":

            return {
                order(
                    $0.fileType ?? "",
                    $1.fileType ?? ""
                )
            }

        case "SRate":

            return {
                order(
                    $0.sampleRate ?? 0,
                    $1.sampleRate ?? 0
                )
            }

        case "R128 Gain":

            return {
                order(
                    $0.replayGain ?? 0,
                    $1.replayGain ?? 0
                )
            }

        case "Duration":

            return {
                order(
                    $0.duration ?? 0,
                    $1.duration ?? 0
                )
            }

        case "Grouping":

            return {
                order(
                    $0.grouping ?? "",
                    $1.grouping ?? ""
                )
            }

        case "Comment":

            return {
                order(
                    $0.comment ?? "",
                    $1.comment ?? ""
                )
            }

        case "Status":

            // Missing (red) sorts first ascending — that's the
            // whole point of sorting by this column: group the
            // tracks a cleanup pass would care about together
            // instead of hunting for red dots one screen at a
            // time. Not-in-library isn't a state LibraryTableView
            // itself can produce (every row here BY DEFINITION
            // came from the Library), so this is effectively a
            // two-value sort: missing vs. not.
            return {

                order(
                    missingSongIDs.contains($0.id ?? -1) ? 0 : 1,
                    missingSongIDs.contains($1.id ?? -1) ? 0 : 1
                )
            }

        default:

            return { _, _ in
                false
            }
        }
    }
}
