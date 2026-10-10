//
//  SetlistTableCoordinator.swift
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


import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Coordinator
//
// NSTableView data source / delegate for SetlistTableView (the Setlist
// table). Split across files by responsibility:
//   SetlistTableCoordinator+Cells.swift      cells, row view, Tanda type, Cortina detection
//   SetlistTableCoordinator+DragDrop.swift   drag source, drop validation, drop, context menu

final class SetlistTableCoordinator:
    NSObject,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSDraggingSource {

    static let internalDragType =
        SetlistDragMarker.pasteboardType

    var entries: [SetlistEntry]

    var selection: Binding<Set<UUID>>

    var duplicateSongIDs: Set<Int64?> = []

    var isTandaColoringEnabled = true

    var lastStatuses:
        [SetlistEntryStatus] = []

    var pendingScrollToEnd = false

    weak var setlistStore:
        SetlistStore?

    weak var libraryStore:
        LibraryStore?

    var settings:
        AppSettings

    weak var tableView:
        NSTableView?

    init(
        entries: [SetlistEntry],
        selection: Binding<Set<UUID>>,
        setlistStore: SetlistStore,
        libraryStore: LibraryStore,
        settings: AppSettings
    ) {

        self.entries = entries
        self.selection = selection
        self.setlistStore = setlistStore
        self.libraryStore = libraryStore
        self.settings = settings
        self.isTandaColoringEnabled =
            setlistStore.isTandaColoringEnabled

        super.init()
    }

    deinit {

        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Data Source

    func numberOfRows(
        in tableView: NSTableView
    ) -> Int {

        entries.count
    }

    // MARK: - Column Reordering

    func tableView(
        _ tableView: NSTableView,
        shouldReorderColumn columnIndex: Int,
        toColumn newColumnIndex: Int
    ) -> Bool {

        columnIndex >= 3 &&
        newColumnIndex >= 3
    }

    // MARK: - Column Width

    @objc func columnDidResize(
        _ notification: Notification
    ) {

        guard
            let table =
                notification.object as? NSTableView
        else {
            return
        }

        for column in table.tableColumns
        where column.identifier.rawValue != "#"
           && column.identifier.rawValue != "Status"
           && column.identifier.rawValue != "Sum" {

            UserDefaults.standard.set(
                column.width,
                forKey:
                    "LibraryTable_ColumnWidth_\(column.identifier.rawValue)"
            )
        }
    }

    // MARK: - Column Order

    @objc func columnDidMove(
        _ notification: Notification
    ) {

        guard
            let table =
                notification.object as? NSTableView
        else {
            return
        }

        let order =
            table.tableColumns
                .map {
                    $0.identifier.rawValue
                }
                .filter {
                    $0 != "#" &&
                    $0 != "Status" &&
                    $0 != "Sum"
                }

        UserDefaults.standard.set(
            order,
            forKey:
                "LibraryTable_ColumnOrder"
        )
    }

    // MARK: - Selection

    func tableViewSelectionDidChange(
        _ notification: Notification
    ) {

        guard
            let table = tableView
        else {
            return
        }

        let indexes =
            table.selectedRowIndexes

        var newSelection =
            Set<UUID>()

        for row in indexes {

            guard
                row >= 0,
                row < entries.count
            else {
                continue
            }

            newSelection.insert(
                entries[row].id
            )
        }

        if selection.wrappedValue !=
            newSelection {

            DispatchQueue.main.async {
                [weak self] in

                guard
                    let self
                else {
                    return
                }

                self.selection.wrappedValue =
                    newSelection

                self.setlistStore?
                    .updateSelectedRowIndexes(
                        indexes
                    )
            }

        } else {

            DispatchQueue.main.async {
                [weak self] in

                self?.setlistStore?
                    .updateSelectedRowIndexes(
                        indexes
                    )
            }
        }

        let previewRow =
            table.selectedRow

        guard
            previewRow >= 0,
            previewRow < entries.count
        else {
            return
        }

        let song =
            entries[previewRow].song

        NotificationCenter.default.post(
            name:
                AppNotification.tandaPreviewSongSelected,
            object:
                song
        )
    }

    // MARK: - Double Click

    @objc func doubleClick(
        _ sender: Any?
    ) {

        guard
            let table = tableView
        else {
            return
        }

        let row =
            table.clickedRow

        guard
            row >= 0,
            row < entries.count
        else {
            return
        }

        let song =
            entries[row].song

        NotificationCenter.default.post(
            name:
                AppNotification.tandaPreviewSongDoubleClicked,
            object:
                song
        )
    }

    // MARK: - Restore Selection

    func restoreSelection() {

        guard
            let table = tableView
        else {
            return
        }

        var rows = IndexSet()

        for (
            index,
            entry
        ) in entries.enumerated() {

            if selection.wrappedValue.contains(
                entry.id
            ) {

                rows.insert(index)
            }
        }

        if table.selectedRowIndexes != rows {

            table.selectRowIndexes(
                rows,
                byExtendingSelection: false
            )
        }
    }
}
