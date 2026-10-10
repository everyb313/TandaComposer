//
//  ContentView.swift
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


// MARK: - Content View

struct ContentView: View {

    @EnvironmentObject private var libraryStore:
        LibraryStore

    @EnvironmentObject private var setlistStore:
        SetlistStore

    @EnvironmentObject private var scanner:
        LibraryScanner

    @EnvironmentObject private var smartlistStore:
        SmartlistStore

    @EnvironmentObject private var settings:
        AppSettings

    @Environment(\.undoManager)
    private var undoManager


    // MARK: Preview Player

    @StateObject private var previewPlayer =
        PreviewPlayer()

    @State private var previewSong:
        Song?


    // MARK: State

    @State private var showingImporter =
        false

    @State private var importErrorMessage:
        String?

    @State private var smartSelection:
        SmartlistSelection = .showAll

    @State private var tandaFolderSelection:
        TandaFolderSelection = .showAll

    // Local Tanda dance-type filter.
    //
    // This is intentionally separate from `tandaFolderSelection`.
    // The folder selection remains the existing artist/folder
    // preselection mechanism; this filter only narrows the Tandas
    // already visible inside that selection.
    @State private var tandaDanceFilter:
        TandaDanceFilter = .all

    // Local TrackLibrary dance-type filter selection.
    //
    // TrackLibrary dance-type filter. This is active only while the
    // Smartlist selection is Show All; otherwise Smartlist filtering
    // is the sole active TrackLibrary filter.
    @State private var trackDanceFilter:
        TandaDanceFilter = .all

    @State private var libraryDisplayMode:
        LibraryDisplayMode = .tracks

    // Shared height applied to the Set / Library / Smartlists column
    // headers — see ColumnHeaderHeightKey above.
    @State private var columnHeaderHeight:
        CGFloat = 0

    // Drives the Orchestra Mix popover in the Set column's title bar
    // — see OrchestraBreakdownView.
    @State private var showingOrchestraBreakdown:
        Bool = false

    // Drives the "how these modes work" popover next to the
    // TrackLibrary/TandaLibrary/Setlist Picker — see
    // LibraryModeHelpView. Replaces what used to be a long, plain
    // .help() tooltip on the Picker itself.
    @State private var showingModeHelp:
        Bool = false

    // Owns the currently-viewed saved Setlist (Setlist mode) — entirely
    // separate from `setlistStore`, so viewing a saved Setlist here
    // never touches the actively-edited one in the Set column.
    /// Duplicate check of the middle view (saved Setlist vs. active
    /// Setlist). Owned here because its toggle lives in the column
    /// header, next to the Library lock.
    @State private var savedSetlistDuplicateCheckEnabled:
        Bool = false

    @StateObject private var savedSetlistViewer =
        SavedSetlistViewerStore()

    // Hoisted here (was previously owned by TandaLibraryView itself)
    // so switching `libraryDisplayMode` away from and back to `.tandas`
    // doesn't recreate it — a fresh TandaStore re-reads every single
    // Tanda JSON file from disk synchronously in `init()`, which on a
    // library with ~100 Tandas was the dominant cost behind a multi-
    // second stall on every switch. TandaFolderTreeView's sidebar tree
    // is now derived from this same instance's `tandas` too, instead
    // of separately re-scanning the `Tandas/` folder on disk itself.
    @StateObject private var tandaStore =
        TandaStore()


    var body: some View {

        GeometryReader { geometry in

            VStack(
                spacing:
                    0
            ) {

                // =====================================================
                // MAIN CONTENT
                // =====================================================

                HSplitView {

                    // =================================================
                    // SET / SETLIST
                    // =================================================

                    SetColumnView(
                        showingOrchestraBreakdown: $showingOrchestraBreakdown,
                        columnHeaderHeight: $columnHeaderHeight
                    ) {
                        SetlistView()
                    }
                    .modifier(BorderedColumn())
                    .frame(
                        minWidth:
                            100,
                        idealWidth:
                            settings.setPaneWidth.isFinite && settings.setPaneWidth > 1
                            ? settings.setPaneWidth
                            : 200
                    )


                    // =================================================
                    // LIBRARY
                    // =================================================

                    LibraryColumnView(
                        smartSelection: $smartSelection,
                        tandaFolderSelection: $tandaFolderSelection,
                        tandaDanceFilter: $tandaDanceFilter,
                        trackDanceFilter: $trackDanceFilter,
                        libraryDisplayMode: $libraryDisplayMode,
                        showingModeHelp: $showingModeHelp,
                        savedSetlistDuplicateCheckEnabled: $savedSetlistDuplicateCheckEnabled,
                        columnHeaderHeight: $columnHeaderHeight,
                        savedSetlistViewer: savedSetlistViewer,
                        tandaStore: tandaStore,
                        showingImporter: $showingImporter
                    ) {
                        switch libraryDisplayMode {
                        case .tracks:
                            SmartListFilteredLibraryView(
                                selection: smartSelection,
                                danceFilter: trackDanceFilter
                            ) { showingImporter = true }
                        case .tandas:
                            TandaLibraryView(
                                folderSelection: tandaFolderSelection,
                                danceFilter: $tandaDanceFilter,
                                store: tandaStore
                            )
                        case .savedsetlist:
                            SavedSetlistViewer(
                                viewerStore: savedSetlistViewer,
                                duplicateCheckEnabled: $savedSetlistDuplicateCheckEnabled
                            )
                        }
                    }
                    .modifier(BorderedColumn())
                    .frame(
                        minWidth:
                            400,
                        idealWidth:
                            settings.libraryPaneWidth.isFinite && settings.libraryPaneWidth > 1
                            ? settings.libraryPaneWidth
                            : 600
                    )


                    // =================================================
                    // SMARTLISTS
                    // =================================================

                    SmartlistsColumnView(
                        libraryDisplayMode: $libraryDisplayMode,
                        columnHeaderHeight: $columnHeaderHeight
                    ) {
                        switch libraryDisplayMode {
                        case .tracks:
                            SmartListTreeView(
                                store: smartlistStore,
                                selection: $smartSelection
                            )
                        case .tandas:
                            TandaFolderTreeView(
                                tandas: tandaStore.tandas,
                                selection: $tandaFolderSelection
                            )
                        case .savedsetlist:
                            SavedSetlistBrowserView(
                                viewerStore: savedSetlistViewer
                            )
                        }
                    }
                    .modifier(BorderedColumn())
                    .frame(
                        minWidth:
                            80,
                        idealWidth:
                            settings.smartlistsPaneWidth.isFinite && settings.smartlistsPaneWidth > 1
                            ? settings.smartlistsPaneWidth
                            : 100
                    )
                }
                .frame(
                    width:
                        geometry.size.width,
                    height:
                        max(
                            0,
                            geometry.size.height - 92
                        )
                )
                .onPreferenceChange(
                    ColumnHeaderHeightKey.self
                ) { height in

                    columnHeaderHeight =
                        height
                }


                // =====================================================
                // PREVIEW PLAYER
                // =====================================================

                PreviewPlayerView(
                    player:
                        previewPlayer,
                    selectedSong:
                        previewSong
                )
                .frame(
                    maxWidth:
                        .infinity
                )
                .frame(
                    height:
                        92
                )
                .padding(
                    .top,
                    1
                )
            }
            .frame(
                width:
                    geometry.size.width,
                height:
                    geometry.size.height
            )
        }
        // Makes previewPlayer available to child views for read access
        // (e.g. TandaLibraryView highlighting the currently-playing
        // row) — previously only ContentView itself held a direct
        // reference to it.
        .environmentObject(
            previewPlayer
        )


        // =============================================================
        // SPLIT VIEW PERSISTENCE
        // =============================================================

        .background {

            SplitViewWidthPersistence(
                settings:
                    settings,
                onWindowWillClose: {

                    previewPlayer.stop()
                }
            )
            .allowsHitTesting(
                false
            )
        }


        // =============================================================
        // PREVIEW SONG SELECTION
        // =============================================================

        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    AppNotification.tandaPreviewSongSelected
            )
        ) { notification in

            guard
                let song =
                    notification.object as? Song
            else {
                return
            }

            previewSong =
                song
        }


        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    AppNotification.tandaPreviewSongDoubleClicked
            )
        ) { notification in

            guard
                let song =
                    notification.object as? Song
            else {
                return
            }

            previewSong =
                song

            previewPlayer.play(
                song:
                    song
            )
        }


        // =============================================================
        // IMPORT
        // =============================================================

        .fileImporter(
            isPresented:
                $showingImporter,
            allowedContentTypes:
                [.folder]
        ) { result in

            switch result {

            case .success(
                let url
            ):

                Task {

                    guard
                        url.startAccessingSecurityScopedResource()
                    else {

                        await MainActor.run {

                            importErrorMessage =
                                "Couldn't access the selected folder."
                        }

                        return
                    }

                    defer {

                        url.stopAccessingSecurityScopedResource()
                    }

                    do {

                        try await scanner.importFolder(
                            url
                        )

                        try libraryStore.reload()

                    } catch ImportError.partialFailure(
                        let failures
                    ) {

                        try? libraryStore.reload()

                        await MainActor.run {

                            importErrorMessage =
                                "Imported with \(failures.count) " +
                                "file(s) skipped " +
                                "(unreadable or unsupported)."
                        }

                    } catch {

                        await MainActor.run {

                            importErrorMessage =
                                "Import failed: " +
                                error.localizedDescription
                        }
                    }
                }


            case .failure(
                let error
            ):

                importErrorMessage =
                    error.localizedDescription
            }
        }


        // =============================================================
        // IMPORT ERROR
        // =============================================================

        .alert(
            "Import",
            isPresented:
                Binding(
                    get: {
                        importErrorMessage != nil
                    },
                    set: { newValue in

                        if !newValue {

                            importErrorMessage =
                                nil
                        }
                    }
                ),
            presenting:
                importErrorMessage
        ) { _ in

            Button(
                "OK"
            ) {

                importErrorMessage =
                    nil
            }

        } message: { message in

            Text(
                message
            )
        }


        // =============================================================
        // IMPORT PROGRESS
        // =============================================================

        .overlay(
            alignment:
                .bottom
        ) {

            if scanner.isScanning {

                ImportProgressBar(
                    scanner:
                        scanner
                )
            }
        }


        // =============================================================
        // UNDO MANAGER
        // =============================================================

        .onAppear {

            setlistStore.undoManager =
                undoManager
        }


        // =============================================================
        // BACKUP IMPORTED
        //
        // tandaStore and savedSetlistViewer are ContentView-local (see
        // their declarations above), so they don't find out on their
        // own when LibraryActions.importBackup() overwrites the whole
        // ~/.TandaComposer folder underneath them. libraryStore/
        // smartlistStore/setlistStore reload themselves directly
        // inside importBackup(), since AppEnvironment already holds
        // references to those.
        // =============================================================

        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    AppNotification.tandaComposerBackupImported
            )
        ) { _ in

            tandaStore.reload()
            savedSetlistViewer.clear()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    AppNotification.tandaComposerLibrarySwitched
            )
        ) { _ in

            tandaStore.reload()
            savedSetlistViewer.clear()

            // Both of these identify a node by file path (see
            // SmartlistNode.id / TandaFolderNode's path-based id) —
            // whatever was selected almost certainly doesn't exist
            // under the newly-active TrackLibrary's own Smartlists/
            // Tandas subtree, so leaving the old selection in place
            // would filter against a folder that's gone, most likely
            // showing an empty list with no obvious explanation.
            smartSelection = .showAll
            tandaFolderSelection = .showAll
        }
    }


}



