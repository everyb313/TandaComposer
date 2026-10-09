//
//  TrackLibraryTableView.swift
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

    // Optional row highlighting supplied by callers that need to compare
    // this table's songs with another set of track references. Defaults
    // to empty so existing Library/Smartlist tables are unchanged.
    var highlightedSongKeys:
        Set<LibraryReferenceResolver.TrackIdentity> = []


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
                settings,
            highlightedSongKeys:
                highlightedSongKeys
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


        LibraryTableColumns.install(
            on:
                table,
            allowsSorting:
                allowsSorting,
            settings:
                settings
        )


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

        let highlightedKeysChanged =
            context.coordinator.highlightedSongKeys !=
            highlightedSongKeys

        context.coordinator.highlightedSongKeys =
            highlightedSongKeys


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

        } else if highlightedKeysChanged || tagSourceChanged {

            // Orchestra/Singer source changed in Settings — update
            // the two column headers' "(Artist)"/"(AlbumArtist)"/
            // "(Grouping)" suffix, repaint (cell text depends on it
            // too), and re-sort in case the table is currently
            // sorted by the Orchestra/Singer column.
            LibraryTableColumns.refreshHeaderTitles(
                in:
                    table,
                settings:
                    settings
            )

            context.coordinator.applySort()

            table.reloadData()
        }
    }


    typealias Coordinator =
        LibraryTableCoordinator
}
