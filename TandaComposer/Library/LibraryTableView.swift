//
//  LibraryTableView.swift
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

// MARK: - Focusable Library NSTableView

private final class LibraryNSTableView:
    NSTableView {

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(
        with event: NSEvent
    ) {

        window?.makeFirstResponder(self)

        let coordinator =
            delegate as? LibraryTableView.Coordinator

        coordinator?.handleMouseClick(
            self,
            event: event
        )

        super.mouseDown(
            with: event
        )
    }
}


// MARK: - Library Table

struct LibraryTableView:
    NSViewRepresentable {

    let songs: [Song]

    let missingSongIDs: Set<Int64>

    @Binding var selection:
        Set<Int64?>

    let insertionMode:
        SetInsertionMode

    // "Orchestra"/"Singer" columns are resolved from whichever raw
    // tag field the user designated (see Song+TagResolution.swift) —
    // needed both to draw the right value and, if either setting
    // changes while sorted by that column, to re-sort correctly.
    @EnvironmentObject
    private var settings:
        AppSettings

    // When false, no column gets a sortDescriptorPrototype at all, so
    // clicking a header can't reorder rows — used by the read-only
    // "Setlist" library mode, which must always show a saved Setlist's
    // actual saved order. Defaults to true so every existing call site
    // (Track Library) is unaffected.
    var allowsSorting:
        Bool = true


    func makeCoordinator() -> Coordinator {

        Coordinator(
            songs:
                songs,
            missingSongIDs:
                missingSongIDs,
            selection:
                $selection,
            insertionMode:
                insertionMode,
            settings:
                settings
        )
    }


    func makeNSView(
        context:
            Context
    ) -> NSScrollView {

        let scrollView =
            NSScrollView()

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let table =
            LibraryNSTableView()

        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .regular
        table.focusRingType = .none

        // Fixed (non-automatic) style + explicit row height so the row
        // font doesn't get silently rescaled by AppKit's "automatic"
        // size-class behavior — this, plus the explicit `field.font`
        // set below, is what keeps this table's text visually matching
        // the SwiftUI-built Tandas table.
        table.style = .plain
        table.rowHeight = 22

        // NSTableView defaults to a 3pt horizontal gap between every
        // column (intercellSpacing). Tandas' SwiftUI HStack has no such
        // gap (spacing: 0), so left at the default this table's total
        // row width silently grows ~3pt per column beyond what Tandas
        // renders — enough, across a dozen columns, to make one fewer
        // column fit before the pane needs to scroll. Zeroing it here
        // is what keeps the two tables' total row width — and so which
        // columns are visible at a given pane width — identical.
        table.intercellSpacing =
            NSSize(
                width: 0,
                height: 0
            )


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
                "LibraryTable_ColumnWidth_\(name)"

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
                    "LibraryTable_ColumnOrder"
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


        table.delegate =
            context.coordinator

        table.dataSource =
            context.coordinator

        table.target =
            context.coordinator

        table.doubleAction =
            #selector(
                Coordinator.doubleClick
            )


        // MARK: Drag Source

        table.setDraggingSourceOperationMask(
            .copy,
            forLocal:
                false
        )


        // MARK: Context Menu

        let menu =
            NSMenu()

        let item =
            NSMenuItem(
                title:
                    "Add to Set",
                action:
                    #selector(
                        Coordinator.addToSet
                    ),
                keyEquivalent:
                    ""
            )

        item.target =
            context.coordinator

        menu.addItem(
            item
        )

        table.menu =
            menu


        // MARK: Notifications

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector:
                #selector(
                    Coordinator.columnDidResize(_:)
                ),
            name:
                NSTableView.columnDidResizeNotification,
            object:
                table
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector:
                #selector(
                    Coordinator.columnDidMove(_:)
                ),
            name:
                NSTableView.columnDidMoveNotification,
            object:
                table
        )


        scrollView.documentView =
            table

        context.coordinator.tableView =
            table

        table.reloadData()

        context.coordinator.restoreSelection()

        return scrollView
    }


    func updateNSView(
        _ nsView:
            NSScrollView,
        context:
            Context
    ) {

        guard
            let table =
                nsView.documentView
                as? NSTableView
        else {
            return
        }


        context.coordinator.insertionMode =
            insertionMode


        let tagSourceChanged =
            context.coordinator.settings.orchestraSource != settings.orchestraSource ||
            context.coordinator.settings.singerSource != settings.singerSource

        context.coordinator.settings =
            settings


        let missingChanged =
            context.coordinator.missingSongIDs !=
            missingSongIDs

        context.coordinator.missingSongIDs =
            missingSongIDs


        // Compares the FULL songs, not just ids/order — a rescan can
        // update a song's tags (e.g. title) while its id and position
        // stay exactly the same, and an id/order-only comparison would
        // miss that entirely: `libraryStore.songs` (and the DB) would
        // already have the fresh title, but this table's cached
        // `coordinator.songs` — and so what's actually drawn — would
        // silently keep showing the old one until something else (a
        // reorder, an add/remove) happened to trigger a reload.
        // `Song`'s synthesized `Equatable` covers every field, so this
        // catches metadata-only changes too, not just id/order ones.
        let songsChanged =
            songs != context.coordinator.songs


        context.coordinator.selection =
            $selection


        if songsChanged {

            context.coordinator.songs =
                songs

            context.coordinator.applySort()

            table.reloadData()

            context.coordinator.restoreSelection()

        } else if missingChanged {

            // Re-sort too, not just reload — if the table is currently
            // sorted by the Status column, a missing-set change (e.g.
            // after a rescan fixes some files) should move rows, not
            // just repaint their dots in place.
            context.coordinator.applySort()

            table.reloadData()

        } else if tagSourceChanged {

            // Orchestra/Singer source changed in Settings — update
            // the two column headers' "(Artist)"/"(AlbumArtist)"/
            // "(Grouping)" suffix, repaint (cell text depends on it
            // too), and re-sort in case the table is currently
            // sorted by the Orchestra/Singer column.
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

            context.coordinator.applySort()

            table.reloadData()
        }
    }


    // MARK: - Coordinator

    final class Coordinator:
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
                AppSettings
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

            super.init()
        }


        deinit {

            NotificationCenter.default.removeObserver(
                self
            )
        }


        // MARK: Rows

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

            currentSortDescriptors =
                tableView.sortDescriptors

            applySort()

            tableView.reloadData()

            restoreSelection()
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
                    comparator(
                        forKey:
                            key,
                        ascending:
                            descriptor.ascending
                    )
            )
        }


        private func comparator(
            forKey key: String,
            ascending: Bool
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
                        $0.resolvedOrchestra(using: self.settings) ?? "",
                        $1.resolvedOrchestra(using: self.settings) ?? ""
                    )
                }

            case "Singer":

                return {
                    order(
                        $0.resolvedSinger(using: self.settings) ?? "",
                        $1.resolvedSinger(using: self.settings) ?? ""
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
                        self.missingSongIDs.contains($0.id ?? -1) ? 0 : 1,
                        self.missingSongIDs.contains($1.id ?? -1) ? 0 : 1
                    )
                }

            default:

                return { _, _ in
                    false
                }
            }
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


            if column.identifier.rawValue ==
                "Status" {

                let imageView =
                    NSImageView()

                if let id = song.id,
                   missingSongIDs.contains(id) {

                    let configuration =
                        NSImage.SymbolConfiguration(
                            pointSize:
                                8,
                            weight:
                                .regular
                        )

                    imageView.image =
                        NSImage(
                            systemSymbolName:
                                "octagon.fill",
                            accessibilityDescription:
                                "File not found"
                        )?
                        .withSymbolConfiguration(
                            configuration
                        )

                    imageView.contentTintColor =
                        .systemRed

                    imageView.toolTip =
                        "File not found on disk"

                } else {

                    imageView.image =
                        nil
                }

                imageView.imageScaling =
                    .scaleProportionallyDown

                return imageView
            }


            let value =
                LibraryColumnDefaults.displayValue(
                    for:
                        column.identifier.rawValue,
                    song:
                        song,
                    settings:
                        self.settings
                )


            let field =
                NSTextField(
                    labelWithString:
                        value
                )

            field.lineBreakMode =
                .byTruncatingTail

            field.font =
                LibraryColumnDefaults.rowFont

            return field
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
                        .tandaPreviewSongSelected,
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
                        .tandaPreviewSongSelected,
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
                    .tandaPreviewSongDoubleClicked,
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
                        "LibraryTable_ColumnWidth_\(column.identifier.rawValue)"
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
                    "LibraryTable_ColumnOrder"
            )
        }
    }
}


// MARK: - Drag Mode Support

extension SetInsertionMode {

    static let pasteboardType =
        NSPasteboard.PasteboardType(
            "com.tandacomposer.set-insertion-mode"
        )


    var pasteboardValue:
        String {

        switch self {

        case .add:
            return "add"

        case .insert:
            return "insert"
        }
    }


    init?(
        pasteboardValue:
            String
    ) {

        switch pasteboardValue {

        case "add":
            self = .add

        case "insert":
            self = .insert

        default:
            return nil
        }
    }
}


// MARK: - Notification

extension Notification.Name {

    static let tandaLibraryAddSelectedToSet =
        Notification.Name(
            "tandaLibraryAddSelectedToSet"
        )
}
