//
//  MaintenanceCommands.swift
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

// MARK: - Maintenance (top-level menu, next to Tools)
//
// Everything here is housekeeping on the currently active
// TrackLibrary's own data (its database, plus its Setlists/Tandas/
// Smartlists — see the per-TrackLibrary folder scoping) rather than
// day-to-day editing, which is why it's split out from "Tools" into
// its own top-level menu instead of living alongside Find Duplicates/
// Export/Import Backup there.

struct MaintenanceCommands: Commands {

    @Environment(\.openWindow)
    private var openWindow


    var body: some Commands {

        CommandMenu("Maintenance") {

            // =====================================================
            // COMPACT TRACKLIBRARY
            //
            // Opens MaintenanceView — SQLite VACUUM, reclaims disk
            // space freed by deleted songs.
            // =====================================================

            Button(
                "Compact TrackLibrary…"
            ) {

                openWindow(
                    id: "maintenance"
                )
            }


            // =====================================================
            // MANAGE IMPORT SOURCES
            //
            // Opens ImportSourcesView — lets the user remove
            // "Add Files"/"Add Folder" bookkeeping entries that a full
            // Rescan would otherwise keep walking, once the Library no
            // longer has any track under that folder.
            // =====================================================

            Button(
                "Manage Import Sources…"
            ) {

                openWindow(
                    id: "import-sources"
                )
            }


            Divider()


            // =====================================================
            // LIBRARY RESCAN
            //
            // Opens RescanLibraryView (progress + grouped results +
            // HTML export) — the window itself triggers the actual
            // scan via its own "Start Rescan" button.
            // =====================================================

            Button {

                openWindow(
                    id: "rescan-library"
                )

            } label: {

                Text(
                    "Rescan TrackLibrary"
                )
            }


            // =====================================================
            // SETLIST RESCAN
            //
            // Opens RescanSetlistView — re-links the CURRENT Setlist's
            // entries whose Library reference moved, by matching on
            // the Library's stable Song ID instead of path. Short
            // status window, no progress bar needed (in-memory,
            // effectively instant).
            // =====================================================

            Button {

                openWindow(
                    id: "rescan-setlist"
                )

            } label: {

                Text(
                    "Rescan Setlist"
                )
            }


            // =====================================================
            // TANDA RESCAN
            //
            // Opens RescanTandaView — same idea as Setlist Rescan, but
            // for every SAVED Tanda file. Rewrites the affected Tanda
            // JSON files on disk when a reference is fixed.
            // =====================================================

            Button {

                openWindow(
                    id: "rescan-tandas"
                )

            } label: {

                Text(
                    "Rescan TandaLibrary"
                )
            }


            // =====================================================
            // SAVED SETLISTS RESCAN
            //
            // Opens RescanSavedSetlistsView — same idea as Tanda
            // Rescan, but for every SAVED Setlist file (not the
            // currently open Set, which "Rescan Setlist" above
            // already covers in memory). Rewrites the affected
            // Setlist JSON files on disk when a reference is fixed.
            // =====================================================

            Button {

                openWindow(
                    id: "rescan-saved-setlists"
                )

            } label: {

                Text(
                    "Rescan Saved Setlists"
                )
            }
        }
    }
}
