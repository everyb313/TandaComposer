//
//  LibraryCommands.swift
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

struct LibraryCommands: Commands {

    @ObservedObject var libraryStore:
        LibraryStore

    @ObservedObject var switchConfirmationCenter:
        SwitchConfirmationCenter

    @ObservedObject var playlistStore:
        PlaylistStore

    @ObservedObject var smartlistStore:
        SmartlistStore

    @ObservedObject var settings:
        AppSettings

    @Environment(\.openWindow)
    private var openWindow


    var body: some Commands {

        CommandMenu("Library") {

            // =====================================================
            // NEW LIBRARY
            // =====================================================

            Button {

                LibraryActions.newLibrary(
                    libraryStore:
                        libraryStore,
                    playlistStore:
                        playlistStore,
                    smartlistStore:
                        smartlistStore,
                    settings:
                        settings
                )

            } label: {

                lockableLabel(
                    "New TrackLibrary…",
                    locked:
                        libraryStore.isLocked
                )
            }
            .keyboardShortcut(
                "n",
                modifiers:
                    [.command]
            )
            .disabled(
                libraryStore.isLocked
            )


            // =====================================================
            // OPEN LIBRARY
            // =====================================================

            Menu {

                // Fixed: this list must read the published property,
                // not call listInternalLibraries() fresh — a plain
                // disk scan doesn't trigger a Commands rebuild, so
                // newly imported/created libraries wouldn't show up
                // until something unrelated happened to republish.
                let names =
                    libraryStore.internalLibraryNames

                if names.isEmpty {

                    Text(
                        "No Internal Libraries"
                    )

                } else {

                    ForEach(
                        names,
                        id: \.self
                    ) { name in

                        Button(name) {

                            LibraryActions.openLibrary(
                                named:
                                    name,
                                libraryStore:
                                    libraryStore,
                                switchConfirmationCenter:
                                    switchConfirmationCenter,
                                playlistStore:
                                    playlistStore,
                                smartlistStore:
                                    smartlistStore,
                                settings:
                                    settings
                            )
                        }
                        .disabled(
                            name ==
                            libraryStore.currentLibraryName
                        )
                    }
                }

            } label: {

                lockableLabel(
                    "Open TrackLibrary",
                    locked:
                        libraryStore.isLocked
                )
            }
            .disabled(
                libraryStore.isLocked
            )


            // =====================================================
            // DELETE LIBRARY
            // =====================================================

            Menu {

                let names =
                    libraryStore.internalLibraryNames
                        .filter {
                            $0 !=
                            libraryStore.currentLibraryName
                        }

                if names.isEmpty {

                    Text(
                        "No Other Internal Libraries"
                    )

                } else {

                    ForEach(
                        names,
                        id: \.self
                    ) { name in

                        Button(name) {

                            LibraryActions.deleteLibrary(
                                named:
                                    name,
                                libraryStore:
                                    libraryStore
                            )
                        }
                    }
                }

            } label: {

                lockableLabel(
                    "Delete TrackLibrary",
                    locked:
                        libraryStore.isLocked
                )
            }
            .disabled(
                libraryStore.isLocked
            )


            // =====================================================
            // CLEAR LIBRARY
            // =====================================================

            Button {

                LibraryActions.clearLibrary(
                    libraryStore:
                        libraryStore
                )

            } label: {

                lockableLabel(
                    "Clear Current TrackLibrary…",
                    locked:
                        libraryStore.isLocked
                )
            }
            .disabled(
                libraryStore.isLocked
            )


/*
            Divider()


            // =====================================================
            // RESET TO FACTORY STATE
            // =====================================================

            Button {

                LibraryActions.resetToFactoryState(
                    libraryStore: libraryStore,
                    playlistStore: playlistStore,
                    smartlistStore: smartlistStore,
                    settings: settings
                )

            } label: {

                lockableLabel(
                    "Reset to Factory State…",
                    locked: libraryStore.isLocked
                )
            }
            .disabled(libraryStore.isLocked)

            Divider()
*/

        }
    }


    // MARK: - Lock Icon Helper

    /// Shows a lock icon in front of the title when `locked` —
    /// makes it obvious at a glance why a menu item is greyed out,
    /// instead of a plain disabled item with no explanation.
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
