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

    @ObservedObject var setlistStore:
        SetlistStore

    @ObservedObject var smartlistStore:
        SmartlistStore

    @ObservedObject var settings:
        AppSettings

    @ObservedObject var switchConfirmationCenter:
        SwitchConfirmationCenter

    let specialImportSession:
        SpecialImportSession

    let tandaImportSession:
        TandaImportSession

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
            // EXPORT
            //
            // Everything that writes data out, in one place. The
            // Setlist and Smartlists menus keep their own entries for
            // the same actions.
            // =====================================================

            Menu(
                "Export"
            ) {

                Button(
                    "Current Setlist (M3U8)…"
                ) {

                    SetlistActions.exportSetlist(
                        setlistStore:
                            setlistStore
                    )
                }


                Button(
                    "Smartlists…"
                ) {

                    SmartlistActions.exportAll(
                        store:
                            smartlistStore
                    )
                }


                // One text file (or M3U8) per Tanda, Tanda folders
                // kept, zipped. Read-only, so no Library lock.
                Button(
                    "TandaLibrary for Sharing (ZIP)…"
                ) {

                    TandaLibraryExportActions.exportForSharing(
                        libraryStore:
                            libraryStore,
                        settings:
                            settings
                    )
                }


                Divider()


                // The whole ~/.TandaComposer folder.
                Button(
                    "Backup of All Data…"
                ) {

                    LibraryActions.exportBackup()
                }
            }


            // =====================================================
            // IMPORT
            // =====================================================

            Menu(
                "Import"
            ) {

                Button(
                    "Setlist (Pick Tracks)…"
                ) {

                    SetlistActions.specialImport(
                        session:
                            specialImportSession,
                        libraryStore:
                            libraryStore,
                        settings:
                            settings,
                        openWindow: {
                            openWindow(
                                id:
                                    "special-import"
                            )
                        }
                    )
                }


                Button(
                    "Setlist (M3U8, experimental)…"
                ) {

                    SetlistActions.importSetlist(
                        setlistStore:
                            setlistStore,
                        libraryStore:
                            libraryStore,
                        switchConfirmationCenter:
                            switchConfirmationCenter
                    )
                }


                Button {

                    SmartlistActions.importAll(
                        store:
                            smartlistStore
                    )

                } label: {

                    lockableLabel(
                        "Smartlists…",
                        locked:
                            smartlistStore.isLocked
                    )
                }
                .disabled(
                    smartlistStore.isLocked
                )


                // Reads a ZIP made by "TandaLibrary for Sharing";
                // one orchestra folder at a time.
                Button(
                    "Tandas from ZIP…"
                ) {

                    if TandaImportActions.chooseZip(
                        session:
                            tandaImportSession
                    ) {
                        openWindow(
                            id:
                                "tanda-import"
                        )
                    }
                }


                Divider()


                // Overwrites files in ~/.TandaComposer: last, behind
                // a divider, and locked with the Library.
                Button {

                    LibraryActions.importBackup(
                        db:
                            db,
                        libraryStore:
                            libraryStore,
                        setlistStore:
                            setlistStore,
                        smartlistStore:
                            smartlistStore
                    )

                } label: {

                    lockableLabel(
                        "Restore Backup…",
                        locked:
                            libraryStore.isLocked
                    )
                }
                .disabled(
                    libraryStore.isLocked
                )
            }
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
