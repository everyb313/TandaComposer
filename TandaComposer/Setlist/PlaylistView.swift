//
//  PlaylistView.swift
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
import UniformTypeIdentifiers
import AppKit

struct PlaylistView: View {

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var selection = Set<UUID>()
    @State private var saveErrorMessage: String?
    @State private var saveErrorTitle = "Couldn't Save Set"
    @State private var showSavedConfirmation = false

    // MARK: - Status Counts
    //
    // Drives the "N missing" / "N not in library" summary in the
    // bottom bar — same red/blue meaning as each row's Status dot
    // (see PlaylistTableView), just aggregated so it's visible without
    // hovering over individual rows.
    private var missingCount: Int {
        playlistStore.entries.filter { $0.status == .fileMissing }.count
    }

    private var notInLibraryCount: Int {
        playlistStore.entries.filter { $0.status == .notInLibrary }.count
    }

    // MARK: - Total Playtime
    //
    // Song.duration is in seconds and is optional — it's currently
    // nil for FLAC/AIFF (see LibraryScanner) — so unknown-duration
    // tracks are skipped rather than counted as 0, and their count is
    // surfaced via a tooltip so the total doesn't look complete when
    // it isn't.
    private var totalPlaytimeSeconds: Int {
        playlistStore.songs
            .compactMap { $0.duration }
            .reduce(0, +)
    }

    private var unknownDurationCount: Int {
        playlistStore.songs
            .filter { $0.duration == nil }
            .count
    }

    private var totalPlaytimeString: String {
        String(
            format: "%02d:%02d",
            totalPlaytimeSeconds / 3600,
            (totalPlaytimeSeconds % 3600) / 60
        )
    }

    var body: some View {

        VStack(spacing: 0) {

            PlaylistTableView(
                entries: playlistStore.entries,
                selection: $selection
            )
            .environmentObject(libraryStore)
            .environmentObject(playlistStore)

            Divider()

            HStack {

                Text("\(playlistStore.songs.count) song(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !playlistStore.songs.isEmpty {

                    Text(
                        "· \(totalPlaytimeString)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(
                        unknownDurationCount > 0
                        ? "Total playtime (hh:mm). \(unknownDurationCount) track(s) have no known duration — common for FLAC/AIFF — and aren't included in this total."
                        : "Total playtime (hh:mm)"
                    )
                }

                if !playlistStore.duplicateSongIDs.isEmpty {

                    Text(
                        "\(playlistStore.duplicateSongIDs.count) duplicates"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if missingCount > 0 {

                    Label(
                        "\(missingCount) missing",
                        systemImage: "octagon.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help(
                        "File not found on disk at last TrackLibrary rescan. If the file moved, run \"Rescan TrackLibrary\", then \"Rescan Setlist\" to re-link it here."
                    )
                }

                if notInLibraryCount > 0 {

                    Label(
                        "\(notInLibraryCount) not in library",
                        systemImage: "questionmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .help(
                        "This track's Library entry no longer exists (removed or never imported)."
                    )
                }

                Spacer()

                Button(role: .destructive) {

                    removeSelected()

                } label: {

                    Label(
                        "Remove",
                        systemImage: "trash"
                    )
                }
                .disabled(selection.isEmpty)

                Button {

                    save()

                } label: {

                    Label(
                        "Save Set",
                        systemImage: "square.and.arrow.down"
                    )
                }
                .disabled(playlistStore.songs.isEmpty)

                if showSavedConfirmation {

                    Label(
                        "Saved",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
                }

                if let progress = playlistStore.importProgress {

                    HStack(spacing: 6) {

                        ProgressView()
                            .controlSize(.small)

                        Text(
                            "Importing \(progress.current) of \(progress.total)…"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(8)
        }

        .alert(
            saveErrorTitle,
            isPresented: .constant(
                saveErrorMessage != nil
            ),
            presenting: saveErrorMessage
        ) { _ in

            Button("OK") {

                saveErrorMessage = nil
            }

        } message: { message in

            Text(message)
        }

        .onAppear {

            playlistStore.resolveAgainstLibrary(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: libraryStore.missingSongIDs
            )
        }

        .onChange(of: libraryStore.songs) { _, _ in

            playlistStore.resolveAgainstLibrary(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: libraryStore.missingSongIDs
            )
        }

        .onChange(of: libraryStore.missingSongIDs) { _, newMissing in

            playlistStore.resolveAgainstLibrary(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: newMissing
            )
        }

        .onChange(of: playlistStore.name) { _, _ in

            playlistStore.resolveAgainstLibrary(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: libraryStore.missingSongIDs
            )
        }
    }

    // MARK: - Selection

    private func removeSelected() {

        playlistStore.remove(
            atOffsets: playlistStore.selectedRowIndexes
        )

        selection.removeAll()
    }

    // MARK: - Save Set

    private func save() {

        do {

            try playlistStore.save()

            withAnimation {

                showSavedConfirmation = true
            }

            Task {

                try? await Task.sleep(
                    nanoseconds: 1_500_000_000
                )

                withAnimation {

                    showSavedConfirmation = false
                }
            }

        } catch {

            saveErrorTitle = "Couldn't Save Set"
            saveErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Save Tanda
    //
    // Removed: the "Save Tanda" button is gone — saving a Tanda now
    // happens exclusively via drag-and-drop onto TandaLibraryView
    // (see its onDrop handler, which reads the current Setlist
    // selection at drop time via PlaylistView's
    // pasteboardWriterForRow, same as this used to).
}

// MARK: - Playlist Table

private struct PlaylistTableView: NSViewRepresentable {

    let entries: [SetlistEntry]

    @Binding var selection: Set<UUID>

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var settings: AppSettings

    func makeCoordinator() -> Coordinator {

        Coordinator(
            entries: entries,
            selection: $selection,
            playlistStore: playlistStore,
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

        context.coordinator.playlistStore =
            playlistStore

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
            playlistStore.duplicateSongIDs

        context.coordinator.duplicateSongIDs =
            playlistStore.duplicateSongIDs

        let tandaColoringChanged =
            context.coordinator.isTandaColoringEnabled !=
            playlistStore.isTandaColoringEnabled

        context.coordinator.isTandaColoringEnabled =
            playlistStore.isTandaColoringEnabled

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

    // MARK: - Coordinator

    final class Coordinator:
        NSObject,
        NSTableViewDataSource,
        NSTableViewDelegate,
        NSDraggingSource {

        static let internalDragType =
            NSPasteboard.PasteboardType(
                "com.tandacomposer.playlist-song"
            )

        var entries: [SetlistEntry]

        var selection: Binding<Set<UUID>>

        var duplicateSongIDs: Set<Int64?> = []

        var isTandaColoringEnabled = true

        var lastStatuses:
            [SetlistEntryStatus] = []

        var pendingScrollToEnd = false

        weak var playlistStore:
            PlaylistStore?

        weak var libraryStore:
            LibraryStore?

        var settings:
            AppSettings

        weak var tableView:
            NSTableView?

        init(
            entries: [SetlistEntry],
            selection: Binding<Set<UUID>>,
            playlistStore: PlaylistStore,
            libraryStore: LibraryStore,
            settings: AppSettings
        ) {

            self.entries = entries
            self.selection = selection
            self.playlistStore = playlistStore
            self.libraryStore = libraryStore
            self.settings = settings
            self.isTandaColoringEnabled =
                playlistStore.isTandaColoringEnabled

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

        // MARK: - Cell

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {

            guard
                let column = tableColumn,
                row >= 0,
                row < entries.count
            else {
                return nil
            }

            let entry = entries[row]
            let song = entry.song

            if column.identifier.rawValue == "#" {

                let field =
                    NSTextField(
                        labelWithString:
                            "\(row + 1)"
                    )

                field.font =
                    LibraryColumnDefaults.rowFont

                field.textColor =
                    .secondaryLabelColor

                field.alignment = .right

                return field
            }

            if column.identifier.rawValue == "Status" {

                let imageView = NSImageView()

                imageView.imageScaling =
                    .scaleProportionallyDown

                let symbolConfiguration =
                    NSImage.SymbolConfiguration(
                        pointSize: 8,
                        weight: .regular
                    )

                if entry.status == .fileMissing {

                    imageView.image =
                        NSImage(
                            systemSymbolName:
                                "octagon.fill",
                            accessibilityDescription:
                                "File not found"
                        )?
                        .withSymbolConfiguration(
                            symbolConfiguration
                        )

                    imageView.contentTintColor =
                        .systemRed

                    imageView.toolTip =
                        "File not found on disk"

                } else if entry.status == .notInLibrary {

                    imageView.image =
                        NSImage(
                            systemSymbolName:
                                "questionmark.circle.fill",
                            accessibilityDescription:
                                "Not in current Library"
                        )?
                        .withSymbolConfiguration(
                            symbolConfiguration
                        )

                    imageView.contentTintColor =
                        .systemBlue

                    imageView.toolTip =
                        "Not found in the current Library — showing saved info"

                } else if entry.status == .staleReference {

                    // Not currently produced by resolveAgainstLibrary
                    // below (it always re-links to the live Library
                    // song on a path match, so a Setlist entry can't
                    // end up "known but stale" the way a Tanda's saved
                    // snapshot can — see TandaBlock.status(for:) in
                    // TandaLibraryView.swift). Handled here anyway so
                    // this stays correct if that ever changes.
                    imageView.image =
                        NSImage(
                            systemSymbolName:
                                "exclamationmark.triangle.fill",
                            accessibilityDescription:
                                "Outdated reference"
                        )?
                        .withSymbolConfiguration(
                            symbolConfiguration
                        )

                    imageView.contentTintColor =
                        .systemOrange

                    imageView.toolTip =
                        "The TrackLibrary already found this file at a new location, but this reference hasn't been re-linked to it yet."

                } else {

                    imageView.image = nil
                }

                return imageView
            }

            if column.identifier.rawValue == "Sum" {

                let totalSeconds =
                    entries[0...row].reduce(0) {
                        $0 + ($1.song.duration ?? 0)
                    }

                let totalMinutes =
                    (totalSeconds + 30) / 60

                let hours =
                    totalMinutes / 60

                let minutes =
                    totalMinutes % 60

                let field =
                    NSTextField(
                        labelWithString:
                            "\(hours):\(String(format: "%02d", minutes))"
                    )

                field.font =
                    LibraryColumnDefaults.rowFont

                field.textColor =
                    .secondaryLabelColor

                field.alignment = .center

                return field
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

        // MARK: - Row View

        func tableView(
            _ tableView: NSTableView,
            rowViewForRow row: Int
        ) -> NSTableRowView? {

            let rowView =
                PlaylistRowView()

            guard
                row >= 0,
                row < entries.count
            else {
                return rowView
            }

            rowView.isDuplicateHighlighted =
                duplicateSongIDs.contains(
                    entries[row].song.id
                )

            rowView.tandaType =
                tandaType(
                    forRow: row
                )
            return rowView
        }

        // MARK: - Tanda Type

        private func tandaType(
            forRow row: Int
        ) -> PlaylistRowView.TandaType {

            guard isTandaColoringEnabled else {
                return .none
            }

            guard entries.indices.contains(row) else {
                return .none
            }

            if isCortinaRow(row) {
                return .none
            }

            let genre =
                entries[row].song.genre ?? ""

            let normalized =
                genre
                    .folding(
                        options: [
                            .diacriticInsensitive,
                            .caseInsensitive
                        ],
                        locale: .current
                    )
                    .lowercased()
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            if normalized.contains("milonga") ||
               normalized.contains("candombe") ||
               normalized.contains("otra") ||
               normalized.contains("foxtrot") {

                return .milonga
            }

            if normalized.contains("vals") {
                return .vals
            }

            if normalized.contains("tango") {
                return .tango
            }

            return .none
        }

        // MARK: - Cortina Detection

        private func isCortinaRow(
            _ row: Int
        ) -> Bool {

            guard
                entries.indices.contains(row)
            else {
                return false
            }

            let genre =
                entries[row].song.genre ?? ""

            return genre.localizedCaseInsensitiveContains(
                "cortina"
            )
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

                    self.playlistStore?
                        .updateSelectedRowIndexes(
                            indexes
                        )
                }

            } else {

                DispatchQueue.main.async {
                    [weak self] in

                    self?.playlistStore?
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
                    .tandaPreviewSongSelected,
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
                    .tandaPreviewSongDoubleClicked,
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

        // MARK: - Drag Source

        func tableView(
            _ tableView: NSTableView,
            pasteboardWriterForRow row: Int
        ) -> NSPasteboardWriting? {

            guard
                row >= 0,
                row < entries.count
            else {
                return nil
            }

            let entry =
                entries[row]

            let item =
                NSPasteboardItem()

            item.setString(
                entry.id.uuidString,
                forType:
                    Self.internalDragType
            )

            item.setString(
                "setlist-to-tanda",
                forType:
                    .string
            )

            let fileURL =
                URL(
                    fileURLWithPath:
                        entry.song.path
                )

            item.setString(
                fileURL.absoluteString,
                forType:
                    .fileURL
            )

            return item
        }

        // MARK: - Drag Session

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {

            switch context {

            case .withinApplication:
                return .move

            case .outsideApplication:
                return .copy

            @unknown default:
                return .copy
            }
        }

        // MARK: - Drop Validation

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation operation:
                NSTableView.DropOperation
        ) -> NSDragOperation {

            let pasteboard =
                info.draggingPasteboard

            if pasteboard.types?.contains(
                SetInsertionMode.pasteboardType
            ) == true {

                let mode =
                    pasteboard.string(
                        forType:
                            SetInsertionMode.pasteboardType
                    )
                    .flatMap {
                        SetInsertionMode(
                            pasteboardValue:
                                $0
                        )
                    } ?? .add

                switch mode {

                case .add:

                    tableView.setDropRow(
                        entries.count,
                        dropOperation: .above
                    )

                    return .copy

                case .insert:

                    let destination =
                        max(
                            0,
                            min(
                                row,
                                entries.count
                            )
                        )

                    tableView.setDropRow(
                        destination,
                        dropOperation: .above
                    )

                    return .copy
                }
            }

            if let tandaPayload =
                tandaPayloadFromPasteboard(
                    pasteboard
                ) {

                switch tandaPayload.mode {

                case .add:

                    tableView.setDropRow(
                        entries.count,
                        dropOperation: .above
                    )

                    return .copy

                case .insert:

                    let destination =
                        max(
                            0,
                            min(
                                row,
                                entries.count
                            )
                        )

                    tableView.setDropRow(
                        destination,
                        dropOperation: .above
                    )

                    return .copy
                }
            }

            if pasteboard.types?.contains(
                Self.internalDragType
            ) == true {

                tableView.setDropRow(
                    max(
                        0,
                        min(
                            row,
                            entries.count
                        )
                    ),
                    dropOperation: .above
                )

                return .move
            }

            if pasteboard.canReadObject(
                forClasses:
                    [NSURL.self],
                options:
                    [
                        .urlReadingFileURLsOnly: true
                    ]
            ) {

                tableView.setDropRow(
                    entries.count,
                    dropOperation: .above
                )

                return .copy
            }

            return []
        }

        // MARK: - Drop

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation:
                NSTableView.DropOperation
        ) -> Bool {

            let pasteboard =
                info.draggingPasteboard

            if pasteboard.types?.contains(
                SetInsertionMode.pasteboardType
            ) == true {

                guard
                    let playlistStore
                else {
                    return false
                }

                let ids =
                    pasteboard.pasteboardItems?
                        .compactMap {
                            item -> Int64? in

                            guard
                                let value =
                                    item.string(
                                        forType:
                                            .string
                                    )
                            else {
                                return nil
                            }

                            return Int64(value)
                        } ?? []

                guard !ids.isEmpty else {
                    return false
                }

                var newSongs = [Song]()

                for id in ids {

                    if let song =
                        libraryStore?.songs.first(
                            where: {
                                $0.id == id
                            }
                        ) {

                        newSongs.append(song)
                    }
                }

                guard !newSongs.isEmpty else {
                    return false
                }

                let mode =
                    pasteboard.string(
                        forType:
                            SetInsertionMode.pasteboardType
                    )
                    .flatMap {
                        SetInsertionMode(
                            pasteboardValue:
                                $0
                        )
                    } ?? .add

                switch mode {

                case .add:

                    pendingScrollToEnd = true

                    playlistStore.add(newSongs)

                case .insert:

                    let insertIndex =
                        max(
                            0,
                            min(
                                row,
                                playlistStore.songs.count
                            )
                        )

                    playlistStore.insert(
                        newSongs,
                        at: insertIndex
                    )
                }

                // Same fix as the Tanda-drop and file-drop handlers
                // below/above — without this, newly-dropped Library
                // tracks sit at the `.resolved` default with no dot,
                // even if the source row was showing red in
                // LibraryTableView.
                playlistStore.resolveAgainstLibrary(
                    byID: libraryStore?.songsByID ?? [:],
                    byPath: libraryStore?.songsByNormalizedPath ?? [:],
                    missingSongIDs: libraryStore?.missingSongIDs ?? []
                )

                return true
            }

            if let tandaPayload =
                tandaPayloadFromPasteboard(
                    pasteboard
                ) {

                guard
                    let playlistStore,
                    let libraryStore
                else {
                    return false
                }

                var newSongs = [Song]()

                for id in tandaPayload.songIDs {

                    if let song =
                        libraryStore.songs.first(
                            where: {
                                $0.id == id
                            }
                        ) {

                        newSongs.append(song)
                    }
                }

                guard !newSongs.isEmpty else {
                    return false
                }

                switch tandaPayload.mode {

                case .add:

                    pendingScrollToEnd = true

                    playlistStore.add(newSongs)

                case .insert:

                    let insertIndex =
                        max(
                            0,
                            min(
                                row,
                                playlistStore.songs.count
                            )
                        )

                    playlistStore.insert(
                        newSongs,
                        at: insertIndex
                    )
                }

                // Without this, newly-added songs (and, before the
                // add()/insert() fix, every OTHER entry too) sit at
                // the `.resolved` default with no dot until something
                // else happens to trigger a resolve pass — the file
                // drop handler above already does this same call for
                // the same reason.
                playlistStore.resolveAgainstLibrary(
                    byID: libraryStore.songsByID,
                    byPath: libraryStore.songsByNormalizedPath,
                    missingSongIDs: libraryStore.missingSongIDs
                )

                return true
            }

            if pasteboard.types?.contains(
                Self.internalDragType
            ) == true {

                guard
                    let playlistStore
                else {
                    return false
                }

                let ids =
                    pasteboard.pasteboardItems?
                        .compactMap {
                            item -> UUID? in

                            guard
                                let value =
                                    item.string(
                                        forType:
                                            Self.internalDragType
                                    )
                            else {
                                return nil
                            }

                            return UUID(
                                uuidString: value
                            )
                        } ?? []

                guard !ids.isEmpty else {
                    return false
                }

                let sourceIndexes =
                    IndexSet(
                        entries.enumerated()
                            .compactMap {
                                index,
                                entry in

                                ids.contains(entry.id)
                                ? index
                                : nil
                            }
                    )

                guard !sourceIndexes.isEmpty else {
                    return false
                }

                let destination =
                    max(
                        0,
                        min(
                            row,
                            entries.count
                        )
                    )

                playlistStore.move(
                    fromOffsets:
                        sourceIndexes,
                    toOffset:
                        destination
                )

                return true
            }

            if let urls =
                pasteboard.readObjects(
                    forClasses:
                        [NSURL.self],
                    options:
                        [
                            .urlReadingFileURLsOnly: true
                        ]
                ) as? [URL],
                !urls.isEmpty {

                guard
                    let playlistStore
                else {
                    return false
                }

                let audioURLs =
                    urls.filter {
                        supportedExtensions.contains(
                            $0.pathExtension.lowercased()
                        )
                    }

                guard !audioURLs.isEmpty else {
                    return false
                }

                Task { @MainActor in

                    var newSongs: [Song] = []

                    playlistStore.importProgress = (
                        current: 0,
                        total: audioURLs.count
                    )

                    for (index, url) in audioURLs.enumerated() {

                        if let song =
                            try? await LibraryScanner.readSong(
                                at: url
                            ) {

                            newSongs.append(song)
                        }

                        playlistStore.importProgress = (
                            current: index + 1,
                            total: audioURLs.count
                        )
                    }

                    playlistStore.importProgress = nil

                    guard !newSongs.isEmpty else {
                        return
                    }

                    playlistStore.add(newSongs)

                    playlistStore.resolveAgainstLibrary(
                        byID:
                            libraryStore?.songsByID ?? [:],
                        byPath:
                            libraryStore?.songsByNormalizedPath ?? [:],
                        missingSongIDs:
                            libraryStore?.missingSongIDs ?? []
                    )
                }

                return true
            }

            return false
        }

        // MARK: - Tanda Detection

        private func tandaPayloadFromPasteboard(
            _ pasteboard: NSPasteboard
        ) -> TandaDragPayload.Decoded? {

            guard
                pasteboard.types?.contains(
                    SetInsertionMode.pasteboardType
                ) != true
            else {
                return nil
            }

            guard
                let items =
                    pasteboard.pasteboardItems
            else {
                return nil
            }

            for item in items {

                guard
                    let value =
                        item.string(
                            forType: .string
                        )
                else {
                    continue
                }

                if let decoded =
                    TandaDragPayload.decode(value) {

                    return decoded
                }
            }

            return nil
        }

        // MARK: - Context Menu

        @objc func removeSelected() {

            guard
                let playlistStore
            else {
                return
            }

            playlistStore.remove(
                atOffsets:
                    playlistStore.selectedRowIndexes
            )

            selection.wrappedValue = []
        }
    }
}

// MARK: - Playlist Row View

private final class PlaylistRowView: NSTableRowView {

    enum TandaType {

        case none
        case tango
        case milonga
        case vals
    }

    var isDuplicateHighlighted = false {

        didSet {
            needsDisplay = true
        }
    }

    var tandaType: TandaType = .none {

        didSet {
            needsDisplay = true
        }
    }

    override func drawBackground(
        in dirtyRect: NSRect
    ) {

        super.drawBackground(
            in: dirtyRect
        )

        let tandaColor: NSColor?

        switch tandaType {

        case .tango:

            tandaColor =
                NSColor.systemYellow
                    .withAlphaComponent(0.14)

        case .milonga:

            tandaColor =
                NSColor.systemRed
                    .withAlphaComponent(0.14)

        case .vals:

            tandaColor =
                NSColor.systemGreen
                    .withAlphaComponent(0.14)

        case .none:

            tandaColor = nil
        }

        if let tandaColor {

            tandaColor.setFill()

            dirtyRect.fill()
        }

        if isDuplicateHighlighted {

            NSColor.systemOrange
                .withAlphaComponent(0.25)
                .setFill()

            dirtyRect.fill()
        }
    }

    override func draw(
        _ dirtyRect: NSRect
    ) {

        super.draw(
            dirtyRect
        )
    }
}
