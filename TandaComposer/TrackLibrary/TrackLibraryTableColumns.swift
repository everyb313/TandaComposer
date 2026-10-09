//
//  TrackLibraryTableColumns.swift
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

// MARK: - Column setup & persistence
//
// Everything about the library table's columns that isn't row
// rendering: creating them, restoring saved widths / order, header
// titles, and persisting user changes back to UserDefaults.

enum LibraryTableColumns {

    static let widthDefaultsKeyPrefix =
        "LibraryTable_ColumnWidth_"

    static let orderDefaultsKey =
        "LibraryTable_ColumnOrder"


    /// Creates all columns on `table` (leading "Status" + the
    /// configured ones) and restores the saved column order.
    static func install(
        on table:
            NSTableView,
        allowsSorting:
            Bool,
        settings:
            AppSettings
    ) {

        let columns:
            [(String, Double)] =
                [("Status", Double(LibraryColumnDefaults.statusColumnWidth))] +
                LibraryColumnDefaults.widths.map {
                    ($0.0, Double($0.1))
                }


        for (name, defaultWidth)
            in columns {

            let column =
                NSTableColumn(
                    identifier:
                        NSUserInterfaceItemIdentifier(
                            name
                        )
                )

            column.title =
                name == "Status" ? "" :
                LibraryColumnDefaults.headerTitle(
                    for: name,
                    settings: settings
                )

            // Status is fixed-width and fixed-position — see
            // `resizingMask` below and
            // `tableView(_:shouldReorderColumn:toColumn:)` in the
            // Coordinator, which blocks it (and anything else) from
            // moving into or out of the leading slot.
            column.minWidth =
                name == "Status" ? LibraryColumnDefaults.statusColumnWidth : 40

            column.maxWidth =
                name == "Status" ? LibraryColumnDefaults.statusColumnWidth : 600

            let key =
                "\(widthDefaultsKeyPrefix)\(name)"

            let saved =
                UserDefaults.standard.double(
                    forKey:
                        key
                )

            column.width =
                name == "Status"
                ? LibraryColumnDefaults.statusColumnWidth
                : (saved > 0 ? saved : defaultWidth)

            column.resizingMask =
                name == "Status"
                ? []
                : .userResizingMask

            if allowsSorting {

                column.sortDescriptorPrototype =
                    NSSortDescriptor(
                        key:
                            name,
                        ascending:
                            true
                    )
            }

            table.addTableColumn(
                column
            )
        }


        // MARK: Restore Column Order
        //
        // "Status" is excluded here — it's always forced to stay the
        // leading column (see `tableView(_:shouldReorderColumn:to-
        // Column:)`), so even an old saved order from before that rule
        // existed can't reposition it.

        if let savedOrder =
            UserDefaults.standard.array(
                forKey:
                    orderDefaultsKey
            ) as? [String] {

            for (
                targetIndex,
                identifier
            ) in savedOrder.enumerated()
                where identifier != "Status" {

                if let currentIndex =
                    table.tableColumns.firstIndex(
                        where: {
                            $0.identifier.rawValue ==
                            identifier
                        }
                    ) {

                    let safeTarget =
                        min(
                            targetIndex,
                            table.tableColumns.count - 1
                        )

                    if currentIndex != safeTarget,
                       currentIndex != 0,
                       safeTarget != 0 {

                        table.moveColumn(
                            currentIndex,
                            toColumn:
                                safeTarget
                        )
                    }
                }
            }
        }
    }


    /// Re-applies the Orchestra/Singer header titles, whose
    /// "(Artist)" / "(AlbumArtist)" / "(Grouping)" suffix depends on
    /// the tag-source settings.
    static func refreshHeaderTitles(
        in table:
            NSTableView,
        settings:
            AppSettings
    ) {

        for column in table.tableColumns {

            let name =
                column.identifier.rawValue

            guard
                name == "Orchestra" ||
                name == "Singer"
            else {
                continue
            }

            column.title =
                LibraryColumnDefaults.headerTitle(
                    for: name,
                    settings: settings
                )
        }
    }
}


// MARK: - Coordinator: column delegate & persistence

extension LibraryTableCoordinator {

    // MARK: Column Reordering
    //
    // "Status" is fixed to the leading position (see column setup
    // in makeNSView) — block any drag that would move it away from
    // index 0, or move another column into index 0.

    func tableView(
        _ tableView:
            NSTableView,
        shouldReorderColumn columnIndex:
            Int,
        toColumn newColumnIndex:
            Int
    ) -> Bool {

        columnIndex != 0 &&
        newColumnIndex != 0
    }


    // MARK: Column Width

    @objc func columnDidResize(
        _ notification:
            Notification
    ) {

        guard
            let table =
                notification.object
                as? NSTableView
        else {
            return
        }


        for column
            in table.tableColumns {

            UserDefaults.standard.set(
                column.width,
                forKey:
                    "\(LibraryTableColumns.widthDefaultsKeyPrefix)\(column.identifier.rawValue)"
            )
        }
    }


    // MARK: Column Order

    @objc func columnDidMove(
        _ notification:
            Notification
    ) {

        guard
            let table =
                notification.object
                as? NSTableView
        else {
            return
        }


        let order =
            table.tableColumns.map {
                $0.identifier.rawValue
            }


        UserDefaults.standard.set(
            order,
            forKey:
                LibraryTableColumns.orderDefaultsKey
        )
    }
}
