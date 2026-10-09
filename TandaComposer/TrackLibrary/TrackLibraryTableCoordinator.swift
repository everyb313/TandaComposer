//
//  TrackLibraryTableCoordinator.swift
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

// MARK: - Coordinator
//
// NSTableView delegate/data source for LibraryTableView. Column
// handling lives in TrackLibraryTableColumns.swift, sorting in
// SongSortComparator.swift, cell creation in
// TrackLibraryTableCells.swift.

final class LibraryTableCoordinator:
    NSObject,
    NSTableViewDelegate,
    NSTableViewDataSource {

    var songs:
        [Song]

    var missingSongIDs:
        Set<Int64>

    var selection:
        Binding<Set<Int64?>>

    var insertionMode:
        SetInsertionMode

    var settings:
        AppSettings

    var highlightedSongKeys:
        Set<LibraryReferenceResolver.TrackIdentity>

    weak var tableView:
        NSTableView?

    private var currentSortDescriptors:
        [NSSortDescriptor] = []


    init(
        songs:
            [Song],
        missingSongIDs:
            Set<Int64>,
        selection:
            Binding<Set<Int64?>>,
        insertionMode:
            SetInsertionMode,
        settings:
            AppSettings,
        highlightedSongKeys:
            Set<LibraryReferenceResolver.TrackIdentity>
    ) {

        self.songs =
            songs

        self.missingSongIDs =
            missingSongIDs

        self.selection =
            selection

        self.insertionMode =
            insertionMode

        self.settings =
            settings

        self.highlightedSongKeys =
            highlightedSongKeys

        super.init()
    }


    deinit {

        NotificationCenter.default.removeObserver(
            self
        )
    }




    func numberOfRows(
        in tableView:
            NSTableView
    ) -> Int {

        songs.count
    }


    // MARK: Sorting

    func tableView(
        _ tableView:
            NSTableView,
        sortDescriptorsDidChange
            oldDescriptors:
                [NSSortDescriptor]
    ) {

        // Captured BEFORE re-sorting: how far down from the top of
        // the currently visible area the selected row currently
        // sits, in points. Restoring this exact offset afterward
        // (rather than just calling scrollRowToVisible, which only
        // scrolls the minimum distance needed and so almost always
        // lands the row right at the top or bottom edge) is what
        // keeps the row's ON-SCREEN position stable across a
        // re-sort instead of visibly jumping to an edge.
        var offsetFromViewportTop: CGFloat?

        if let scrollView = tableView.enclosingScrollView,
            let firstSelectedRow =
                tableView.selectedRowIndexes.first {

            let rowRect =
                tableView.rect(ofRow: firstSelectedRow)

            let visibleRect =
                scrollView.contentView.documentVisibleRect

            offsetFromViewportTop =
                rowRect.origin.y - visibleRect.origin.y
        }


        currentSortDescriptors =
            tableView.sortDescriptors

        applySort()

        tableView.reloadData()

        restoreSelection()

        // Deliberately only here, not inside restoreSelection()
        // itself — that's also called after ordinary data reloads
        // (e.g. a tag edit or rescan changing some song's fields),
        // where re-positioning the scroll on every such change
        // would be a surprising jump unrelated to what the user
        // actually just did.
        if let offsetFromViewportTop,
            let scrollView = tableView.enclosingScrollView,
            let firstSelectedRow =
                tableView.selectedRowIndexes.first {

            let newRowRect =
                tableView.rect(ofRow: firstSelectedRow)

            let targetY =
                newRowRect.origin.y - offsetFromViewportTop

            // Sorting reorders rows but never changes how many
            // there are, so the document's total height (and
            // therefore the valid scroll range) is unchanged —
            // still clamped defensively rather than assumed, in
            // case that ever stops being true.
            let visibleHeight =
                scrollView.contentView.documentVisibleRect.height

            let maxY =
                max(
                    0,
                    tableView.bounds.height - visibleHeight
                )

            let clampedY =
                min(
                    max(0, targetY),
                    maxY
                )

            scrollView.contentView.scroll(
                to: NSPoint(
                    x: scrollView.contentView.bounds.origin.x,
                    y: clampedY
                )
            )

            scrollView.reflectScrolledClipView(
                scrollView.contentView
            )
        }
    }


    func applySort() {

        guard
            let descriptor =
                currentSortDescriptors.first,
            let key =
                descriptor.key
        else {
            return
        }

        songs.sort(
            by:
                SongSortComparator.make(
                    forKey:
                        key,
                    ascending:
                        descriptor.ascending,
                    settings:
                        settings,
                    missingSongIDs:
                        missingSongIDs
                )
        )
    }


    // MARK: Drag Source

    func tableView(
        _ tableView:
            NSTableView,
        pasteboardWriterForRow row:
            Int
    ) -> NSPasteboardWriting? {

        guard
            row >= 0,
            row < songs.count,
            let id =
                songs[row].id
        else {
            return nil
        }


        let item =
            NSPasteboardItem()


        // Song ID

        item.setString(
            String(id),
            forType:
                .string
        )


        // Current insertion mode

        item.setString(
            insertionMode.pasteboardValue,
            forType:
                SetInsertionMode.pasteboardType
        )


        return item
    }


    // MARK: Row View

    func tableView(
        _ tableView: NSTableView,
        rowViewForRow row: Int
    ) -> NSTableRowView? {

        let rowView =
            LibraryTableRowView()

        guard songs.indices.contains(row) else {
            return rowView
        }

        rowView.isCrossSetlistDuplicate =
            LibraryReferenceResolver.identity(
                for: songs[row]
            ).map {
                highlightedSongKeys.contains($0)
            } ?? false

        return rowView
    }


    // MARK: Cell

    func tableView(
        _ tableView:
            NSTableView,
        viewFor tableColumn:
            NSTableColumn?,
        row:
            Int
    ) -> NSView? {

        guard
            let column =
                tableColumn,
            row >= 0,
            row < songs.count
        else {
            return nil
        }


        let song =
            songs[row]

        let isMissing =
            song.id.map {
                missingSongIDs.contains($0)
            } ?? false


        return LibraryTableCells.cell(
            forColumn:
                column.identifier.rawValue,
            song:
                song,
            isMissing:
                isMissing,
            settings:
                settings
        )
    }


    // MARK: Selection

    func tableViewSelectionDidChange(
        _ notification:
            Notification
    ) {

        guard
            let table =
                tableView
        else {
            return
        }


        updateSelectionFromTable(
            table
        )

        postPreviewForSelectedRow(
            table
        )
    }


    private func updateSelectionFromTable(
        _ table:
            NSTableView
    ) {

        var newSelection =
            Set<Int64?>()


        for row
            in table.selectedRowIndexes {

            guard
                row >= 0,
                row < songs.count
            else {
                continue
            }

            newSelection.insert(
                songs[row].id
            )
        }


        guard
            selection.wrappedValue !=
            newSelection
        else {
            return
        }


        let binding =
            selection


        DispatchQueue.main.async {

            binding.wrappedValue =
                newSelection
        }
    }


    private func postPreviewForSelectedRow(
        _ table:
            NSTableView
    ) {

        guard
            let row =
                table.selectedRowIndexes.last,
            row >= 0,
            row < songs.count
        else {
            return
        }


        let song =
            songs[row]


        DispatchQueue.main.async {

            NotificationCenter.default.post(
                name:
                    AppNotification.tandaPreviewSongSelected,
                object:
                    song
            )
        }
    }


    // MARK: Mouse Click

    func handleMouseClick(
        _ table:
            NSTableView,
        event:
            NSEvent
    ) {

        let point =
            table.convert(
                event.locationInWindow,
                from:
                    nil
            )

        let row =
            table.row(
                at:
                    point
            )


        guard
            row >= 0,
            row < songs.count
        else {
            return
        }


        let song =
            songs[row]


        DispatchQueue.main.async {

            NotificationCenter.default.post(
                name:
                    AppNotification.tandaPreviewSongSelected,
                object:
                    song
            )
        }
    }


    // MARK: Double Click

    @objc func doubleClick(
        _ sender:
            Any?
    ) {

        guard
            let table =
                tableView
        else {
            return
        }


        let row =
            table.clickedRow


        guard
            row >= 0,
            row < songs.count
        else {
            return
        }


        let song =
            songs[row]


        /* print(
            "LIBRARY DOUBLE CLICK:",
            song.title ?? "",
            "id:",
            song.id as Any
        ) */


        NotificationCenter.default.post(
            name:
                AppNotification.tandaPreviewSongDoubleClicked,
            object:
                song
        )
    }


    // MARK: Restore Selection

    func restoreSelection() {

        guard
            let table =
                tableView
        else {
            return
        }


        var rows =
            IndexSet()


        for (
            index,
            song
        ) in songs.enumerated() {

            if selection.wrappedValue.contains(
                song.id
            ) {

                rows.insert(
                    index
                )
            }
        }


        if table.selectedRowIndexes !=
            rows {

            table.selectRowIndexes(
                rows,
                byExtendingSelection:
                    false
            )
        }
    }


    // MARK: Context Menu Add

    @objc func addToSet() {

        // Context-menu compatibility is intentionally retained.
        // The actual drag operation now controls whether songs
        // are added or inserted.
        guard
            let table =
                tableView
        else {
            return
        }


        let selected =
            table.selectedRowIndexes.compactMap {
                row -> Song? in

                guard
                    row >= 0,
                    row < songs.count
                else {
                    return nil
                }

                return songs[row]
            }


        guard
            !selected.isEmpty
        else {
            return
        }


        NotificationCenter.default.post(
            name:
                .tandaLibraryAddSelectedToSet,
            object:
                selected
        )
    }
}
