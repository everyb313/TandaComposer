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
                Section("Backup / Sharing") {
                    
                    Button(
                        "    Current Setlist (M3U8)…"
                    ) {
                        
                        SetlistActions.exportSetlist(
                            setlistStore:
                                setlistStore
                        )
                    }
                    
                    
                    Button(
                        "    Smartlists (ZIP)…"
                    ) {
                        
                        SmartlistActions.exportAll(
                            store:
                                smartlistStore
                        )
                    }
                    
                    
                    // Live: JSON ZIP only (one JSON file per Tanda).
                    // exportForSharing (text/M3U8) is temporarily dead code.
                    Button(
                        "    TandaLibrary (JSON-ZIP)…"
                    ) {
                        TandaLibraryExportActions.exportJSONZip()
                    }
                }
                
                Divider()
                
                
                // The whole ~/.TandaComposer folder.
                Section("Complete Backup") {
                    Button(
                        "    Backup All (Libraries, Setlists, Smartlists)…"
                    ) {
                        
                        LibraryActions.exportBackup()
                    }
                }
            }
            
            
            // =====================================================
            // IMPORT
            // =====================================================
            
            Menu(
                "Import"
            ) {
                
                // One entry: M3U8 or text. Exact path matches get a short
                // confirmation; anything else opens the Special Import window.
                // importSetlist (path-only) is temporarily dead code.
                Button(
                    "Setlist from List or M3U8…"
                ) {
                    
                    SetlistActions.specialImport(
                        session:
                            specialImportSession,
                        libraryStore:
                            libraryStore,
                        setlistStore:
                            setlistStore,
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
                
                
                Button {
                    
                    SmartlistActions.importAll(
                        store:
                            smartlistStore
                    )
                    
                } label: {
                    
                    lockableLabel(
                        "Smartlists (ZIP)…",
                        locked:
                            smartlistStore.isLocked
                    )
                }
                .disabled(
                    smartlistStore.isLocked
                )
                
                
                // Reads a ZIP made by Tools → Export → "TandaLibrary (JSON-ZIP)…";
                // one orchestra folder at a time. (Legacy text/M3U8 still parsed.)
                // Writes into the TandaLibrary → needs the Library unlocked.
                Button {
                    
                    if TandaImportActions.chooseZip(
                        session:
                            tandaImportSession
                    ) {
                        openWindow(
                            id:
                                "tanda-import"
                        )
                    }
                    
                } label: {
                    
                    lockableLabel(
                        "Tandas from ZIP…",
                        locked:
                            libraryStore.isLocked
                    )
                }
                .disabled(
                    libraryStore.isLocked
                )
                
                
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
                        "Restore All from Backup…",
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
