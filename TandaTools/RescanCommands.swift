//
//  RescanCommands.swift
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

struct RescanCommands: Commands {

    let db:
        DatabaseManager

    @ObservedObject var libraryStore:
        LibraryStore

    @ObservedObject var playlistStore:
        PlaylistStore

    @ObservedObject var smartlistStore:
        SmartlistStore

    @Environment(\.openWindow)
    private var openWindow


    var body: some Commands {

        CommandMenu("Tools") {

            // =====================================================
            // FIND DUPLICATES
            // =====================================================

            Button(
                "Find TrackLibrary Duplicates…"
            ) {

                openWindow(
                    id: "duplicate-finder"
                )
            }


            Divider()


            // =====================================================
            // EXPORT / IMPORT BACKUP (whole ~/.TandaComposer folder)
            // =====================================================

            Button(
                "Export Backup…"
            ) {

                LibraryActions.exportBackup()
            }


            Button {

                LibraryActions.importBackup(
                    db:
                        db,
                    libraryStore:
                        libraryStore,
                    playlistStore:
                        playlistStore,
                    smartlistStore:
                        smartlistStore
                )

            } label: {

                lockableLabel(
                    "Import Backup…",
                    locked:
                        libraryStore.isLocked
                )
            }
            .disabled(
                libraryStore.isLocked
            )
        }
    }


    // MARK: - Lock Icon Helper

    /// Shows a lock icon in front of the title when `locked` — same
    /// pattern as LibraryCommands' identically named helper.
    @ViewBuilder
    private func lockableLabel(
        _ title: String,
        locked: Bool
    ) -> some View {

        if locked {

            Label(
                title,
                systemImage:
                    "lock.fill"
            )

        } else {

            Text(
                title
            )
        }
    }
}
