//
//  SetlistTableCoordinator+DragDrop.swift
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

// MARK: - Coordinator: drag & drop, context menu

extension SetlistTableCoordinator {

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
                let setlistStore
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

                setlistStore.add(newSongs)

            case .insert:

                let insertIndex =
                    max(
                        0,
                        min(
                            row,
                            setlistStore.songs.count
                        )
                    )

                setlistStore.insert(
                    newSongs,
                    at: insertIndex
                )
            }

            // Same fix as the Tanda-drop and file-drop handlers
            // below/above — without this, newly-dropped Library
            // tracks sit at the `.resolved` default with no dot,
            // even if the source row was showing red in
            // LibraryTableView.
            setlistStore.resolveAgainstLibrary(
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
                let setlistStore,
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

                setlistStore.add(newSongs)

            case .insert:

                let insertIndex =
                    max(
                        0,
                        min(
                            row,
                            setlistStore.songs.count
                        )
                    )

                setlistStore.insert(
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
            setlistStore.resolveAgainstLibrary(
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
                let setlistStore
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

            setlistStore.move(
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
                let setlistStore
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

                setlistStore.importProgress = (
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

                    setlistStore.importProgress = (
                        current: index + 1,
                        total: audioURLs.count
                    )
                }

                setlistStore.importProgress = nil

                guard !newSongs.isEmpty else {
                    return
                }

                setlistStore.add(newSongs)

                setlistStore.resolveAgainstLibrary(
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

    func tandaPayloadFromPasteboard(
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
            let setlistStore
        else {
            return
        }

        setlistStore.remove(
            atOffsets:
                setlistStore.selectedRowIndexes
        )

        selection.wrappedValue = []
    }
}
