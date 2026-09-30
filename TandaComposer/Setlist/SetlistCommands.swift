//
//  SetlistCommands.swift
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

struct SetlistCommands: Commands {

@ObservedObject var setlistStore:
    SetlistStore

@ObservedObject var libraryStore:
    LibraryStore

@ObservedObject var switchConfirmationCenter:
    SwitchConfirmationCenter


var body: some Commands {

    CommandMenu("Setlist") {

        // =====================================================
        // NEW SETLIST
        // =====================================================

        Button("New Setlist…") {

            SetlistActions.newPlaylist(
                setlistStore:
                    setlistStore
            )
        }
        .keyboardShortcut(
            "n",
            modifiers: [
                .command,
                .shift
            ]
        )


        // =====================================================
        // OPEN SETLIST
        // =====================================================

        Menu("Open Setlist") {

            let names =
                setlistStore.savedPlaylistNamesList

            if names.isEmpty {

                Text("No Saved Setlists")

            } else {

                ForEach(
                    names,
                    id: \.self
                ) { name in

                    Button(name) {

                        SetlistActions.openPlaylist(
                            named:
                                name,
                            setlistStore:
                                setlistStore,
                            switchConfirmationCenter:
                                switchConfirmationCenter
                        )
                    }
                    .disabled(
                        name ==
                        setlistStore.name
                    )
                }
            }
        }


        // =====================================================
        // DELETE SETLIST
        // =====================================================

        Menu("Delete Setlist") {

            let names =
                setlistStore.savedPlaylistNamesList

            if names.isEmpty {

                Text("No Saved Setlists")

            } else {

                ForEach(
                    names,
                    id: \.self
                ) { name in

                    Button(name) {

                        SetlistActions.deletePlaylist(
                            named:
                                name,
                            setlistStore:
                                setlistStore
                        )
                    }
                    .disabled(
                        name ==
                        setlistStore.name
                    )
                }
            }
        }


        Divider()


        // =====================================================
        // EXPORT SETLIST
        // =====================================================

        Button("Export Setlist…") {

            SetlistActions.exportSetlist(
                setlistStore:
                    setlistStore
            )
        }


        Button("Import Setlist (M3U8)…") {

            SetlistActions.importSetlist(
                setlistStore:
                    setlistStore,
                libraryStore:
                    libraryStore,
                switchConfirmationCenter:
                    switchConfirmationCenter
            )
        }
    }
}

}
