//
//  SetlistTableView.swift
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

// MARK: - Setlist Table

/// Pasteboard marker carried by every drag that starts in the Setlist
/// table (rows being reordered or dragged out, e.g. onto the Tanda
/// Library). A Tanda drag from the Tanda Library does NOT carry it —
/// it is plain text only — which is how the Tanda Library's drop
/// targets tell the two apart while the drag is still hovering.
enum SetlistDragMarker {

    static let pasteboardType =
        NSPasteboard.PasteboardType(
            "com.tandacomposer.playlist-song"
        )
}

struct PlaylistTableView: NSViewRepresentable {

    let entries: [SetlistEntry]

    @Binding var selection: Set<UUID>

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var setlistStore: SetlistStore
    @EnvironmentObject private var settings: AppSettings

    func makeCoordinator() -> Coordinator {

        Coordinator(
            entries: entries,
            selection: $selection,
            setlistStore: setlistStore,
            libraryStore: libraryStore,
            settings: settings
        )
    }

    func makeNSView(
        context: Context
    ) -> NSScrollView {

        let scrollView = NSScrollView()

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let table = NSTableView()

        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .regular
        table.focusRingType = .none
        table.style = .plain
        table.rowHeight = 22

        table.intercellSpacing = NSSize(
            width: 0,
            height: 0
        )

        // MARK: Columns

        let indexColumn = NSTableColumn(
            identifier:
                NSUserInterfaceItemIdentifier("#")
        )

        indexColumn.title = "#"
        indexColumn.minWidth = 36
        indexColumn.maxWidth = 36
        indexColumn.width = 36
        indexColumn.resizingMask = []

        table.addTableColumn(indexColumn)

        let statusColumn = NSTableColumn(
            identifier:
                NSUserInterfaceItemIdentifier("Status")
        )

        statusColumn.title = ""

        statusColumn.minWidth =
            LibraryColumnDefaults.statusColumnWidth

        statusColumn.maxWidth =
            LibraryColumnDefaults.statusColumnWidth

        statusColumn.width =
            LibraryColumnDefaults.statusColumnWidth

        statusColumn.resizingMask = []

        table.addTableColumn(statusColumn)

        let sumColumn = NSTableColumn(
            identifier:
                NSUserInterfaceItemIdentifier("Sum")
        )

        sumColumn.title = "Sum"
        sumColumn.minWidth = 40
        sumColumn.maxWidth = 40
        sumColumn.width = 40
        sumColumn.resizingMask = []

        sumColumn.headerCell.alignment = .center

        table.addTableColumn(sumColumn)

        for (name, defaultWidth)
            in LibraryColumnDefaults.widths {

            let column = NSTableColumn(
                identifier:
                    NSUserInterfaceItemIdentifier(name)
            )

            column.title =
                LibraryColumnDefaults.headerTitle(
                    for: name,
                    settings: settings
                )
            column.minWidth = 40
            column.maxWidth = 600

            let key =
                "LibraryTable_ColumnWidth_\(name)"

            let saved =
                UserDefaults.standard.double(
                    forKey: key
                )

            column.width =
                saved > 0
                ? saved
                : Double(defaultWidth)

            column.resizingMask =
                .userResizingMask

            table.addTableColumn(column)
        }

        // MARK: Restore Column Order

        let leadingColumnCount = 3

        if let savedOrder =
            UserDefaults.standard.array(
                forKey:
                    "LibraryTable_ColumnOrder"
            ) as? [String] {

            let sharedOrder =
                savedOrder.filter {
                    $0 != "#" &&
                    $0 != "Status" &&
                    $0 != "Sum"
                }

            for (
                offsetIndex,
                identifier
            ) in sharedOrder.enumerated() {

                let targetIndex =
                    offsetIndex +
                    leadingColumnCount

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
                       currentIndex >= leadingColumnCount,
                       safeTarget >= leadingColumnCount {

                        table.moveColumn(
                            currentIndex,
                            toColumn: safeTarget
                        )
                    }
                }
            }
        }

        // MARK: Delegate / Data Source

        table.delegate = context.coordinator
        table.dataSource = context.coordinator

        context.coordinator.tableView = table

        // MARK: Double Click

        table.target = context.coordinator

        table.doubleAction =
            #selector(
                Coordinator.doubleClick
            )

        // MARK: Drag Source

        table.setDraggingSourceOperationMask(
            .move,
            forLocal: true
        )

        table.setDraggingSourceOperationMask(
            .copy,
            forLocal: false
        )

        table.registerForDraggedTypes([
            PlaylistTableView.Coordinator.internalDragType,
            .fileURL,
            .string,
            SetInsertionMode.pasteboardType
        ])

        // MARK: Context Menu

        let menu = NSMenu()

        let removeItem = NSMenuItem(
            title: "Remove Selected",
            action:
                #selector(
                    Coordinator.removeSelected
                ),
            keyEquivalent: ""
        )

        removeItem.target = context.coordinator

        menu.addItem(removeItem)

        table.menu = menu

        // MARK: Notifications

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector:
                #selector(
                    Coordinator.columnDidResize(_:)
                ),
            name:
                NSTableView.columnDidResizeNotification,
            object: table
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector:
                #selector(
                    Coordinator.columnDidMove(_:)
                ),
            name:
                NSTableView.columnDidMoveNotification,
            object: table
        )

        scrollView.documentView = table

        return scrollView
    }

    func updateNSView(
        _ nsView: NSScrollView,
        context: Context
    ) {

        guard
            let table =
                nsView.documentView as? NSTableView
        else {
            return
        }

        let oldIDs =
            context.coordinator.entries.map {
                $0.id
            }

        let newIDs =
            entries.map {
                $0.id
            }

        let songsChanged =
            oldIDs != newIDs

        context.coordinator.selection =
            $selection

        context.coordinator.setlistStore =
            setlistStore

        context.coordinator.libraryStore =
            libraryStore

        let tagSourceChanged =
            context.coordinator.settings.orchestraSource != settings.orchestraSource ||
            context.coordinator.settings.singerSource != settings.singerSource

        context.coordinator.settings =
            settings

        context.coordinator.entries =
            entries

        let duplicatesChanged =
            context.coordinator.duplicateSongIDs !=
            setlistStore.duplicateSongIDs

        context.coordinator.duplicateSongIDs =
            setlistStore.duplicateSongIDs

        let tandaColoringChanged =
            context.coordinator.isTandaColoringEnabled !=
            setlistStore.isTandaColoringEnabled

        context.coordinator.isTandaColoringEnabled =
            setlistStore.isTandaColoringEnabled

        let statusChanged =
            context.coordinator.lastStatuses !=
            entries.map(\.status)

        context.coordinator.lastStatuses =
            entries.map(\.status)

        if songsChanged {

            table.reloadData()

            context.coordinator.restoreSelection()

            if context.coordinator.pendingScrollToEnd {

                context.coordinator.pendingScrollToEnd = false

                let lastRow =
                    table.numberOfRows - 1

                if lastRow >= 0 {

                    table.scrollRowToVisible(lastRow)
                }
            }

        } else if duplicatesChanged ||
                  tandaColoringChanged ||
                  statusChanged ||
                  tagSourceChanged {

            if tagSourceChanged {

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

            table.reloadData()
        }
    }


    typealias Coordinator =
        PlaylistTableCoordinator
}
