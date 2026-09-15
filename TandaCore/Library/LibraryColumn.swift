//
//  LibraryColumn.swift
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
import AppKit


// MARK: - Library Column Defaults
//
// Single source of truth for the columns shared by BOTH library table
// presentations:
//
//   - LibraryTableView.swift  ("Tracks", AppKit NSTableView)
//   - TandaLibraryView.swift  ("Tandas", SwiftUI-built table)
//
// Previously each view kept its own hard-coded [(String, CGFloat)] array,
// which drifted apart over time (different widths for Album/AlbumArtist,
// different fonts). Both views now build their column list from
// `LibraryColumnDefaults.ordered`, so Title/Artist/AlbumArtist etc. can
// never silently diverge again.
//
// Columns that only exist in ONE of the two views (Tracks' leading
// "Status" icon column, Tandas' leading "#" row-number column) are NOT
// part of this shared list — each view still prepends its own.

enum LibraryColumn: String, CaseIterable {

    case title = "Title"
    case artist = "Orchestra"
    case albumArtist = "Singer"
    case album = "Album"
    case genre = "Genre"
    case year = "Year"
    case type = "Type"
    case sampleRate = "SRate"
    case replayGain = "R128 Gain"
    case duration = "Duration"
    case grouping = "Grouping"
    case comment = "Comment"


    /// Default column width, shared by both views. Tracks additionally
    /// persists user-resized widths per-column in UserDefaults on top
    /// of this default; Tandas has no per-column resizing, so this is
    /// also its permanent width.
    var defaultWidth: CGFloat {

        switch self {

        case .title: return 220
        case .artist: return 180
        case .albumArtist: return 160
        case .album: return 220
        case .genre: return 100
        case .year: return 60
        case .type: return 60
        case .sampleRate: return 90
        case .replayGain: return 90
        case .duration: return 80
        case .grouping: return 160
        case .comment: return 260
        }
    }
}


enum LibraryColumnDefaults {

    /// Canonical column order + default widths for both views.
    static let ordered: [LibraryColumn] =
        LibraryColumn.allCases

    /// Convenience form matching the `[(String, CGFloat)]` shape both
    /// views previously used locally.
    static let widths: [(String, CGFloat)] =
        ordered.map {
            ($0.rawValue, $0.defaultWidth)
        }

    /// Shared row-content font. Both views must set this explicitly —
    /// AppKit's `NSTextField(labelWithString:)` and SwiftUI's default
    /// `Text` font resolve to visibly different sizes if left implicit,
    /// which was the root cause of the Tracks/Tandas font mismatch.
    static let rowFontSize: CGFloat = 13

    static let rowFont: NSFont =
        .systemFont(ofSize: rowFontSize)


    /// Width of each view's non-shared LEADING column — Tracks' small
    /// "Status" icon column, Tandas' "#" row-number column. Kept equal
    /// so the shared columns after it line up at the same x-position in
    /// both views, and total row width (hence how many columns fit
    /// before needing to scroll) stays identical too.
    ///
    /// Currently unused: Tandas' "#" column is commented out (see
    /// TandaLibraryView.swift) in favor of `tandaLeadingSpacerWidth`
    /// below. Left in place in case the index column comes back.
    static let leadingColumnWidth: CGFloat = 32


    /// Blank leading spacer column for Tandas only — no header text, no
    /// content, purely there to visually offset the table's left edge
    /// from the surrounding block border/frame, to compensate for the
    /// gap between Tracks' own left edge and its "Status" dot column.
    /// Tuned by eye against Tracks' fixed 20pt Status column width.
    static let tandaLeadingSpacerWidth: CGFloat = 5


    /// Tracks' "Status" (dot) column — fixed width, fixed leading
    /// position: not user-resizable, not user-reorderable. See
    /// LibraryTableView.swift's column setup and
    /// `tableView(_:shouldReorderColumn:toColumn:)`.
    static let statusColumnWidth: CGFloat = 20


    // MARK: - Current (User-Customized) Order & Widths
    //
    // Tracks (LibraryTableView) lets the user drag columns to reorder
    // them and drag their edges to resize them, persisting both to
    // UserDefaults ("LibraryTable_ColumnOrder" / "LibraryTable_Column-
    // Width_<name>"). Tandas has no per-column drag/resize of its own —
    // instead it reads THESE SAME keys, so whatever order/width the
    // user has Tracks in right now is exactly what Tandas shows too.
    // This is what makes switching between the two tabs "deckungsgleich"
    // (congruent) rather than just "same defaults".

    private static let orderDefaultsKey =
        "LibraryTable_ColumnOrder"

    private static func widthDefaultsKey(
        _ name:
            String
    ) -> String {

        "LibraryTable_ColumnWidth_\(name)"
    }


    /// The width the user last resized this column to in Tracks, or
    /// its default if it was never resized.
    static func currentWidth(
        for column:
            LibraryColumn
    ) -> CGFloat {

        let saved =
            UserDefaults.standard.double(
                forKey:
                    widthDefaultsKey(
                        column.rawValue
                    )
            )

        return saved > 0
            ? CGFloat(saved)
            : column.defaultWidth
    }


    /// The order the user last dragged Tracks' columns into (with
    /// Tracks' own "Status" column, which Tandas doesn't have, filtered
    /// out), or the canonical default order if never reordered. Any
    /// column missing from a saved order — e.g. one added in a later
    /// app version, after the user last reordered — is appended at the
    /// end in canonical order rather than dropped.
    static func currentOrder() -> [LibraryColumn] {

        guard
            let savedOrder =
                UserDefaults.standard.array(
                    forKey:
                        orderDefaultsKey
                ) as? [String]
        else {

            return ordered
        }


        var result: [LibraryColumn] = []

        for name in savedOrder {

            if let column =
                LibraryColumn(
                    rawValue:
                        name
                ) {

                result.append(
                    column
                )
            }
        }

        for column in ordered
            where !result.contains(
                column
            ) {

            result.append(
                column
            )
        }

        return result
    }


    /// `(name, width)` pairs in the user's current order — the single
    /// source both Tracks and Tandas resolve their columns from, so
    /// switching between them always lines up exactly.
    static func currentColumns() -> [(String, CGFloat)] {

        currentOrder().map {
            (
                $0.rawValue,
                currentWidth(
                    for:
                        $0
                )
            )
        }
    }


    // MARK: - Display Value
    //
    // Shared cell-text formatting for one of the 12 columns above, given
    // a Song. Originally duplicated separately in LibraryTableView.swift
    // (Tracks) and PlaylistView.swift (Setlist) — pulled out here so a
    // formatting change (or a future field) only has to happen once,
    // instead of risking the two silently drifting apart again.

    /// The column header text actually shown in the UI. For the two
    /// user-configurable columns ("Orchestra"/"Singer"), this appends
    /// which raw tag field is currently the source, e.g.
    /// "Orchestra (Artist)" — so the header never lies about where
    /// the value in that column actually comes from. All other
    /// columns are shown as-is.
    static func headerTitle(
        for columnName:
            String,
        settings:
            AppSettings
    ) -> String {

        switch columnName {

        case "Orchestra":
            return "Orchestra (\(settings.orchestraSource.displayName))"

        case "Singer":
            return "Singer (\(settings.singerSource.displayName))"

        default:
            return columnName
        }
    }


    static func displayValue(
        for columnName:
            String,
        song:
            Song,
        settings:
            AppSettings
    ) -> String {

        switch columnName {

        case "Title":
            return song.title ?? ""

        case "Orchestra":
            return song.resolvedOrchestra(using: settings) ?? ""

        case "Singer":
            return song.resolvedSinger(using: settings) ?? ""

        case "Album":
            return song.album ?? ""

        case "Genre":
            return song.genre ?? ""

        case "Year":
            return song.year.map {
                String($0)
            } ?? ""

        case "Type":
            return song.fileType ?? ""

        case "SRate":
            return song.sampleRate.map {
                String(
                    format:
                        "%.1f kHz",
                    Double($0) / 1000
                )
            } ?? ""

        case "R128 Gain":
            return song.replayGain.map {
                String(
                    format:
                        "%.1f dB",
                    $0
                )
            } ?? ""

        case "Duration":
            guard
                let duration =
                    song.duration
            else {

                return ""
            }

            return String(
                format:
                    "%d:%02d",
                duration / 60,
                duration % 60
            )

        case "Grouping":
            return song.grouping ?? ""

        case "Comment":
            return song.comment ?? ""

        default:
            return ""
        }
    }
}
