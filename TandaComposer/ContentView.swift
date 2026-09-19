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


// MARK: - Column Header Height Sync
//
// Set / Library / Smartlists column headers have different content
// (segmented Picker vs plain Text vs Text + optional lock icon), so
// their natural heights differ — and the Smartlists header's own
// height even varies between its three modes (lock icon shown only
// in Tracks mode). Each header reports its intrinsic height via this
// preference key; ContentView keeps the max in `columnHeaderHeight`
// and applies it back to all three headers, so they always line up
// regardless of mode or font.

private struct ColumnHeaderHeightKey: PreferenceKey {

    static var defaultValue: CGFloat = 0

    static func reduce(
        value: inout CGFloat,
        nextValue: () -> CGFloat
    ) {

        value =
            max(
                value,
                nextValue()
            )
    }
}


// MARK: - Preview Selection Notifications

extension Notification.Name {

    static let tandaPreviewSongSelected =
        Notification.Name(
            "TandaComposer.PreviewSongSelected"
        )

    static let tandaPreviewSongDoubleClicked =
        Notification.Name(
            "TandaComposer.PreviewSongDoubleClicked"
        )

    /// Posted after a Tanda is successfully saved to disk (see
    /// PlaylistView.swift's saveTanda()). TandaLibraryView listens for
    /// this to reload TandaStore, so a newly-saved Tanda appears
    /// immediately instead of only on next launch/view recreation.
    static let tandaSaved =
        Notification.Name(
            "TandaComposer.TandaSaved"
        )

    /// Posted after one or more SAVED Setlist files were rewritten on
    /// disk by "Rescan Saved Setlists" (see
    /// SavedSetlistsRescanner.applyRescan) — mirrors `tandaSaved`.
    /// SavedSetlistBrowserView listens for this so a saved Setlist
    /// that's currently open for viewing reloads and reflects the
    /// just-fixed paths immediately, instead of only on next open.
    static let setlistSaved =
        Notification.Name(
            "TandaComposer.SetlistSaved"
        )

    /// Posted after a Backup is successfully imported (see
    /// LibraryActions.importBackup()) — the whole ~/.TandaComposer
    /// folder was just overwritten from a zip, out from under
    /// whatever's currently in memory. libraryStore/smartlistStore/
    /// playlistStore reload themselves directly inside importBackup()
    /// since AppEnvironment already has references to them; TandaStore
    /// and the read-only saved-Setlist viewer are ContentView-local
    /// (see their declarations there), so this notification is how
    /// they find out to reload/clear themselves too.
    static let tandaComposerBackupImported =
        Notification.Name(
            "TandaComposer.BackupImported"
        )

    /// Posted after the active TrackLibrary changed (switch, create,
    /// or factory reset — see LibraryActions.swift) — Setlists/
    /// Smartlists/Tandas are now scoped per TrackLibrary
    /// (AppPaths.libraryRoot), so all of them need to reload from the
    /// new subtree, the same way importBackup() needs everyone to
    /// reload after overwriting ~/.TandaComposer wholesale.
    /// libraryStore/smartlistStore/playlistStore are reloaded directly
    /// at the LibraryActions call site (which already has references
    /// to them); TandaStore and the read-only saved-Setlist viewer are
    /// ContentView-local, so this notification is how they find out.
    static let tandaComposerLibrarySwitched =
        Notification.Name(
            "TandaComposer.LibrarySwitched"
        )
}


// MARK: - Library Display Mode

private enum LibraryDisplayMode {

    case tracks
    case tandas
    case setlist
}


// MARK: - Content View

struct ContentView: View {

    @EnvironmentObject private var libraryStore:
        LibraryStore

    @EnvironmentObject private var playlistStore:
        PlaylistStore

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
    // separate from `playlistStore`, so viewing a saved Setlist here
    // never touches the actively-edited one in the Set column.
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
                    // SET / PLAYLIST
                    // =================================================

                    setColumn {

                        PlaylistView()
                    }
                    .borderedColumn()
                    .frame(
                        minWidth:
                            100,
                        idealWidth:
                            safeIdealWidth(
                                settings.setPaneWidth,
                                fallback:
                                    200
                            )
                    )


                    // =================================================
                    // LIBRARY
                    // =================================================

                    libraryColumn {

                        switch libraryDisplayMode {

                        case .tracks:

                            SmartListFilteredLibraryView(
                                selection:
                                    smartSelection,
                                danceFilter:
                                    trackDanceFilter
                            ) {

                                showingImporter =
                                    true
                            }


                        case .tandas:

                            TandaLibraryView(
                                folderSelection:
                                    tandaFolderSelection,
                                danceFilter:
                                    $tandaDanceFilter,
                                store:
                                    tandaStore
                            )


                        case .setlist:

                            SetlistLibraryView(
                                viewerStore:
                                    savedSetlistViewer
                            )
                        }
                    }
                    .borderedColumn()
                    .frame(
                        minWidth:
                            400,
                        idealWidth:
                            safeIdealWidth(
                                settings.libraryPaneWidth,
                                fallback:
                                    600
                            )
                    )


                    // =================================================
                    // SMARTLISTS
                    // =================================================

                    smartlistsColumn {

                        switch libraryDisplayMode {

                        case .tracks:

                            SmartListTreeView(
                                store:
                                    smartlistStore,
                                selection:
                                    $smartSelection
                            )


                        case .tandas:

                            TandaFolderTreeView(
                                tandas:
                                    tandaStore.tandas,
                                selection:
                                    $tandaFolderSelection
                            )


                        case .setlist:

                            SavedSetlistBrowserView(
                                viewerStore:
                                    savedSetlistViewer
                            )
                        }
                    }
                    .borderedColumn()
                    .frame(
                        minWidth:
                            80,
                        idealWidth:
                            safeIdealWidth(
                                settings.smartlistsPaneWidth,
                                fallback:
                                    100
                            )
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
                    .tandaPreviewSongSelected
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
                    .tandaPreviewSongDoubleClicked
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

            playlistStore.undoManager =
                undoManager
        }


        // =============================================================
        // BACKUP IMPORTED
        //
        // tandaStore and savedSetlistViewer are ContentView-local (see
        // their declarations above), so they don't find out on their
        // own when LibraryActions.importBackup() overwrites the whole
        // ~/.TandaComposer folder underneath them. libraryStore/
        // smartlistStore/playlistStore reload themselves directly
        // inside importBackup(), since AppEnvironment already holds
        // references to those.
        // =============================================================

        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    .tandaComposerBackupImported
            )
        ) { _ in

            tandaStore.reload()
            savedSetlistViewer.clear()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    .tandaComposerLibrarySwitched
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


    // MARK: - Active Library Filter Label
    //
    // Compact indicator shown in the libraryColumn header when a filter
    // is active — a Smartlist in Tracks mode, or a folder in Tandas
    // mode. Hidden entirely on "Show All" so the common case stays
    // uncluttered. (Replaces the old unused `libraryTitle`, which also
    // always prefixed the Library name — dropped here since the Library
    // name isn't otherwise shown persistently anywhere.)

    private var activeLibraryFilterLabel: String? {

        switch libraryDisplayMode {

        case .tracks:

            if case .node(let node) =
                smartSelection {

                return "Smartlist: \(node.name)"
            }

            return nil


        case .tandas:

            if case .folder(let path) =
                tandaFolderSelection {

                return "Folder: \(path)"
            }

            return nil


        case .setlist:

            if let name =
                savedSetlistViewer.setlistName {

                return "Setlist: \(name)"
            }

            return nil
        }
    }


    // MARK: - Track Dance Filter Buttons Visibility
    //
    // Show All → always show. A selected Smartlist → show only if its
    // name's genre component is NOT a single defined dance type.
    // Naming convention: ###_<genre>_<artist>_<albumartist>_<year>.
    // Genre component exactly "T"/"V"/"M" (case-insensitive) = defined
    // → hide the buttons. Anything else (explicitly "TVM"/"All"/"Mix",
    // or a name that doesn't match this pattern at all) = not defined
    // → show the buttons.

    private var trackDanceFilterButtonsShouldShow: Bool {

        guard case .node(let node) = smartSelection else {

            // .showAll
            return true
        }

        let components =
            node.name.components(
                separatedBy: "_"
            )

        guard components.count >= 2 else {
            return true
        }

        let genreToken =
            components[1]
                .trimmingCharacters(
                    in: .whitespaces
                )
                .lowercased()

        let definedGenreTokens:
            Set<String> = ["t", "v", "m"]

        return !definedGenreTokens.contains(
            genreToken
        )
    }


    // MARK: - Library Column

    @ViewBuilder
    private func libraryColumn<Content: View>(
        @ViewBuilder content:
            () -> Content
    ) -> some View {

        VStack(
            spacing:
                0
        ) {

            HStack(
                spacing:
                    6
            ) {

                // =====================================================
                // TRACKS / TANDAS SWITCH
                // =====================================================

                Picker(
                    "",
                    selection:
                        $libraryDisplayMode
                ) {

                    Text(
                        "TrackLibrary"
                    )
                    .tag(
                        LibraryDisplayMode.tracks
                    )


                    Text(
                        "TandaLibrary"
                    )
                    .tag(
                        LibraryDisplayMode.tandas
                    )


                    Text(
                        "Setlist"
                    )
                    .tag(
                        LibraryDisplayMode.setlist
                    )
                }
                .pickerStyle(
                    .segmented
                )
                .fixedSize()


                // =====================================================
                // MODE HELP
                //
                // Replaces the old plain-text .help() tooltip that used
                // to hang directly off the Picker above — same three
                // sections, now a popover so the titles can actually be
                // bold/larger instead of flat tooltip text.
                // =====================================================

                Button {

                    showingModeHelp.toggle()

                } label: {

                    Image(
                        systemName:
                            "questionmark.circle"
                    )
                    .foregroundStyle(
                        showingModeHelp
                        ? Color.accentColor
                        : Color.gray
                    )
                    .font(
                        .system(size: 18)
                    )
                }
                .buttonStyle(
                    .plain
                )
                .help(
                    "How These Modes Work"
                )
                .popover(
                    isPresented:
                        $showingModeHelp
                ) {

                    LibraryModeHelpView()
                }

                
                // =====================================================
                // ACTIVE LIBRARY NAME
                //
                // Only shown in TrackLibrary mode — TandaLibrary and
                // Setlist have their own name displays already
                // (see activeLibraryFilterLabel below: Folder for
                // .tandas, Setlist name for .setlist).
                // =====================================================

                if libraryDisplayMode == .tracks {

                    Text(
                        "Library: "
                        + libraryStore.currentLibraryName
                    )
                    .font(
                        .title3
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(
                        1
                    )
                }


                // =====================================================
                // ACTIVE FILTER INDICATOR
                //
                // Only shown when a Smartlist (Tracks) or folder
                // (Tandas) filter is actually applied — hidden on
                // "Show All". Placed right after the Library name,
                // left-aligned in the gap before the lock icon (the
                // Spacer below pushes the lock icon to the far right,
                // not this label).
                // =====================================================

                if let label =
                    activeLibraryFilterLabel {

                    Text(
                        label
                    )
                    .font(
                        .title3
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(
                        1
                    )
                }


                Spacer()


                // =====================================================
                // DANCE TYPE FILTER
                //
                // A = all
                // T = Tango
                // V = Vals
                // M = Milonga
                // X = VariousGenres
                //
                // TrackLibrary: the buttons are enabled while Smartlists
                // is on "Show All", OR while the selected Smartlist's
                // name doesn't encode a single defined dance type (see
                // trackDanceFilterButtonsShouldShow above). Only a
                // Smartlist whose name's genre component is exactly
                // T/V/M disables them.
                //
                // TandaLibrary: existing independent Tanda filter.
                // =====================================================

                if libraryDisplayMode == .tracks {

                    HStack(
                        spacing:
                            3
                    ) {

                        ForEach(
                            TandaDanceFilter.allCases
                        ) { filter in

                            Button {

                                trackDanceFilter =
                                    filter

                            } label: {

                                Text(
                                    filter.title
                                )
                                .font(
                                    .system(
                                        size:
                                            14,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    Color.white
                                )
                                .frame(
                                    width:
                                        22,
                                    height:
                                        22
                                )
                                .background(
                                    trackDanceFilter == filter
                                    ? Color.blue
                                    : Color.secondary.opacity(0.35)
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:
                                            4
                                    )
                                )
                                .opacity(
                                    trackDanceFilterButtonsShouldShow
                                    ? 1
                                    : 0.35
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                            .disabled(
                                !trackDanceFilterButtonsShouldShow
                            )
                            .help(
                                trackDanceFilterButtonsShouldShow
                                ? filter.helpText
                                : "Disabled while a Smartlist with a defined genre is active"
                            )
                        }
                    }
                }

                if libraryDisplayMode == .tandas {

                    HStack(
                        spacing:
                            3
                    ) {

                        ForEach(
                            TandaDanceFilter.allCases
                        ) { filter in

                            Button {

                                tandaDanceFilter =
                                    filter

                            } label: {

                                Text(
                                    filter.title
                                )
                                .font(
                                    .system(
                                        size:
                                            14,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    Color.white
                                )
                                .frame(
                                    width:
                                        22,
                                    height:
                                        22
                                )
                                .background(
                                    tandaDanceFilter == filter
                                    ? Color.blue
                                    : Color.secondary.opacity(0.35)
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:
                                            4
                                    )
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                            .help(
                                filter.helpText
                            )
                        }
                    }
                }


                // =====================================================
                // LIBRARY LOCK
                // =====================================================

                Button {

                    libraryStore.isLocked.toggle()

                } label: {

                    Image(
                        systemName:
                            libraryStore.isLocked
                            ? "lock.fill"
                            : "lock.open.fill"
                    )
                    .foregroundStyle(
                        libraryStore.isLocked
                        ? Color.gray
                        : Color.orange
                    )
                    .font(
                        .system(size: 18)
                    )
                }
                .buttonStyle(
                    .plain
                )
                .help(
                    libraryStore.isLocked
                    ? "Unlock Library"
                    : "Lock Library"
                )
            }
            .padding(
                .horizontal,
                10
            )
            .padding(
                .vertical,
                6
            )
            .background(
                GeometryReader { proxy in

                    Color.clear
                        .preference(
                            key:
                                ColumnHeaderHeightKey.self,
                            value:
                                proxy.size.height
                        )
                }
            )
            .frame(
                height:
                    columnHeaderHeight > 0
                    ? columnHeaderHeight
                    : nil
            )


            Divider()


            content()
        }
        .frame(
            maxWidth:
                .infinity,
            maxHeight:
                .infinity
        )
    }


    // MARK: - Set Column

    @ViewBuilder
    private func setColumn<Content: View>(
        @ViewBuilder content:
            () -> Content
    ) -> some View {

        VStack(
            spacing:
                0
        ) {

            HStack(
                spacing:
                    6
            ) {

                Text(
                    "Set:"
                )
                .font(
                    .headline
                )

                Text(
                    playlistStore.name
                )
                .font(
                    .headline
                )
                .lineLimit(
                    1
                )
                .truncationMode(
                    .tail
                )
                .frame(
                    maxWidth:
                        .infinity,
                    alignment:
                        .leading
                )


                // =====================================================
                // DUPLICATE HIGHLIGHTING TOGGLE
                // =====================================================

                Button {

                    playlistStore.toggleDuplicateHighlighting()

                } label: {

                    Image(
                        systemName:
                            playlistStore.isDuplicateHighlightingEnabled
                            ? "doc.on.doc.fill"
                            : "doc.on.doc"
                    )
                    .foregroundStyle(
                        !playlistStore.isDuplicateHighlightingEnabled
                        ? Color.gray
                        : playlistStore.duplicateSongIDs.isEmpty
                        ? Color.green
                        : Color.orange
                    )
                    .font(
                        .system(size: 18)
                    )
                }
                .buttonStyle(
                    .plain
                )
                .disabled(
                    playlistStore.songs.isEmpty
                )
                .help(
                    !playlistStore.isDuplicateHighlightingEnabled
                    ? "Highlight Duplicates"
                    : playlistStore.duplicateSongIDs.isEmpty
                    ? "No duplicates found"
                    : "Hide Duplicate Highlighting"
                )


                // =====================================================
                // TANDA COLORING TOGGLE
                // =====================================================

                Button {

                    playlistStore.toggleTandaColoring()

                } label: {

                    Image(
                        systemName:
                            playlistStore.isTandaColoringEnabled
                            ? "paintpalette.fill"
                            : "paintpalette"
                    )
                    .foregroundStyle(
                        playlistStore.isTandaColoringEnabled
                        ? Color.accentColor
                        : Color.gray
                    )
                    .font(
                        .system(size: 18)
                    )
                }
                .buttonStyle(
                    .plain
                )
                .help(
                    playlistStore.isTandaColoringEnabled
                    ? "Hide Tanda Coloring"
                    : "Show Tanda Coloring"
                )


                // =====================================================
                // ORCHESTRA MIX
                // =====================================================

                Button {

                    showingOrchestraBreakdown.toggle()

                } label: {

                    Image(
                        systemName:
                            "chart.bar"
                    )
                    .foregroundStyle(
                        showingOrchestraBreakdown
                        ? Color.accentColor
                        : Color.gray
                    )
                    .font(
                        .system(size: 18)
                    )
                }
                .buttonStyle(
                    .plain
                )
                .disabled(
                    playlistStore.songs.isEmpty
                )
                .help(
                    "Orchestra Mix"
                )
                .popover(
                    isPresented:
                        $showingOrchestraBreakdown
                ) {

                    OrchestraBreakdownView(
                        songs:
                            playlistStore.songs
                    )
                    .environmentObject(
                        settings
                    )
                }
            }
            .padding(
                .horizontal,
                8
            )
            .padding(
                .vertical,
                10 // war 5
            )
            .background(
                GeometryReader { proxy in

                    Color.clear
                        .preference(
                            key:
                                ColumnHeaderHeightKey.self,
                            value:
                                proxy.size.height
                        )
                }
            )
            .frame(
                height:
                    columnHeaderHeight > 0
                    ? columnHeaderHeight
                    : nil
            )


            Divider()


            content()
        }
        .frame(
            maxWidth:
                .infinity,
            maxHeight:
                .infinity
        )
    }


    // MARK: - Smartlists Column

    // Title for the smartlistsColumn header — reflects what's actually
    // shown below it, since that panel's content switches by mode
    // (SmartListTreeView / TandaFolderTreeView / SavedSetlist-
    // BrowserView) but the header itself previously always said
    // "Smartlists" regardless.
    private var smartlistsColumnTitle: String {

        switch libraryDisplayMode {

        case .tracks:
            return "Smartlists"

        case .tandas:
            return "Tanda Folders"

        case .setlist:
            return "Saved Setlists"
        }
    }


    @ViewBuilder
    private func smartlistsColumn<Content: View>(
        @ViewBuilder content:
            () -> Content
    ) -> some View {

        VStack(
            spacing:
                0
        ) {

            HStack {

                Text(
                    smartlistsColumnTitle
                )
                .font(
                    .headline
                )
                
                //spacing:
                //    0
                Spacer()


                // -----------------------------------------------------
                // Smartlist Lock
                //
                // Only meaningful for Tracks mode's actual Smartlists
                // (SmartlistStore.isLocked) — Tanda Folders and
                // Saved Setlists have no analogous lock, so this is
                // hidden rather than shown irrelevantly next to them.
                // -----------------------------------------------------

                if libraryDisplayMode == .tracks {

                    Button {

                        smartlistStore.isLocked.toggle()

                    } label: {

                        Image(
                            systemName:
                                smartlistStore.isLocked
                                ? "lock.fill"
                                : "lock.open.fill"
                        )
                        .foregroundStyle(
                            smartlistStore.isLocked
                            ? Color.gray
                            : Color.orange
                        )
                        .font(
                            .system(size: 18)
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                    .help(
                        smartlistStore.isLocked
                        ? "Unlock to edit, delete, or move smartlists"
                        : "Lock smartlists"
                    )
                }
            }
            .padding(
                .horizontal,
                10
            )
            .padding(
                .vertical,
                8 // war 6
            )
            .background(
                GeometryReader { proxy in

                    Color.clear
                        .preference(
                            key:
                                ColumnHeaderHeightKey.self,
                            value:
                                proxy.size.height
                        )
                }
            )
            .frame(
                height:
                    columnHeaderHeight > 0
                    ? columnHeaderHeight
                    : nil
            )


            Divider()


            content()
        }
        .frame(
            maxWidth:
                .infinity,
            maxHeight:
                .infinity
        )
    }


    // MARK: - Safe Ideal Width
    //
    // Guards against a corrupted/degenerate persisted pane width
    // (0, negative, NaN, or infinite — e.g. from an old AppSettings.json
    // written during an earlier, buggier session) ever reaching
    // `.frame(idealWidth:)` directly. This matters specifically at the
    // very FIRST window layout: NSSplitViewController computes its own
    // initial fitting size (systemLayoutSizeFittingSize) from these
    // idealWidth values BEFORE applySavedWidthsIfPossible() gets a
    // chance to run and correct anything — AppKit's constraint solver
    // can crash hard on a NaN/degenerate size at that point, which
    // applySavedWidthsIfPossible()'s own `isFinite && > 1` guard (later,
    // in Swift-land) is too late to prevent.

    private func safeIdealWidth(
        _ value:
            Double,
        fallback:
            Double
    ) -> Double {

        value.isFinite && value > 1
            ? value
            : fallback
    }
}


// MARK: - Split View Width Persistence

private struct SplitViewWidthPersistence:
    NSViewRepresentable {

    let settings:
        AppSettings

    var onWindowWillClose:
        (() -> Void)?
        = nil


    func makeNSView(
        context:
            Context
    ) -> NSView {

        let view =
            SplitViewObserverView()

        view.settings =
            settings

        view.onWindowWillClose =
            onWindowWillClose

        return view
    }


    func updateNSView(
        _ nsView:
            NSView,
        context:
            Context
    ) {

        guard
            let view =
                nsView as?
                SplitViewObserverView
        else {
            return
        }

        view.settings =
            settings

        view.onWindowWillClose =
            onWindowWillClose

        view.applySavedWidthsIfPossible()
    }
}


// MARK: - AppKit Split View Observer

private final class SplitViewObserverView:
    NSView {

    weak var splitView:
        NSSplitView?

    private var observerToken:
        NSObjectProtocol?

    private var windowWillCloseToken:
        NSObjectProtocol?

    var settings:
        AppSettings?

    var onWindowWillClose:
        (() -> Void)?


    private var didRestoreInitialWidths =
        false

    private var isApplyingSavedWidths =
        false

    private var ignoreNextResizeNotification =
        false

    // Coalesces disk writes — NSSplitView.didResizeSubviewsNotification
    // fires on every single frame during a live window/divider drag
    // (see splitViewDidResize below), so writing AppSettings.json on
    // every notification means dozens of disk writes per second, each
    // differing only by sub-pixel rounding. The in-memory widths still
    // update immediately; only the actual save to disk is debounced
    // until resizing has paused for a moment.
    private var pendingSettingsSaveWorkItem:
        DispatchWorkItem?


    override func viewDidMoveToWindow() {

        super.viewDidMoveToWindow()

        guard let window else {

            windowWillCloseToken =
                nil

            return
        }

        if windowWillCloseToken == nil {

            windowWillCloseToken =
                NotificationCenter.default.addObserver(
                    forName:
                        NSWindow.willCloseNotification,
                    object:
                        window,
                    queue:
                        .main
                ) { [weak self] _ in

                    Task { @MainActor [weak self] in

                        // Flush any pending (debounced) split-width
                        // save immediately — don't let a resize right
                        // before quitting get lost.
                        if let workItem =
                            self?.pendingSettingsSaveWorkItem {

                            workItem.cancel()

                            self?.settings?.save()
                        }

                        self?.onWindowWillClose?()
                    }
                }
        }

        DispatchQueue.main.async { [weak self] in

            self?.connectToSplitView()
        }
    }


    deinit {

        if let observerToken {

            NotificationCenter.default.removeObserver(
                observerToken
            )
        }

        if let windowWillCloseToken {

            NotificationCenter.default.removeObserver(
                windowWillCloseToken
            )
        }

        pendingSettingsSaveWorkItem?.cancel()
    }


    private func connectToSplitView() {

        guard let window else {
            return
        }

        if let splitView,
           splitView.window === window {

            return
        }

        guard
            let split =
                findSplitView(
                    in:
                        window.contentView
                )
        else {

            DispatchQueue.main.async { [weak self] in

                self?.connectToSplitView()
            }

            return
        }

        guard
            split.arrangedSubviews.count >= 3
        else {

            DispatchQueue.main.async { [weak self] in

                self?.connectToSplitView()
            }

            return
        }

        splitView =
            split

        observerToken =
            NotificationCenter.default.addObserver(
                forName:
                    NSSplitView.didResizeSubviewsNotification,
                object:
                    split,
                queue:
                    .main
            ) { [weak self] _ in

                self?.splitViewDidResize()
            }

        print(
            "SPLIT VIEW FOUND:",
            split
        )

        DispatchQueue.main.async { [weak self] in

            self?.applySavedWidthsIfPossible()
        }

        DispatchQueue.main.asyncAfter(
            deadline:
                .now() + 0.15
        ) { [weak self] in

            guard let self else {
                return
            }

            if !self.didRestoreInitialWidths {

                self.applySavedWidthsIfPossible()
            }
        }
    }


    private func splitViewDidResize() {

        guard
            let splitView,
            let settings
        else {
            return
        }

        guard
            splitView.arrangedSubviews.count >= 3
        else {
            return
        }

        if isApplyingSavedWidths {

            return
        }

        if ignoreNextResizeNotification {

            ignoreNextResizeNotification =
                false

            return
        }

        guard didRestoreInitialWidths else {

            return
        }

        let widths =
            currentPaneWidths(
                from:
                    splitView
            )

        guard widths.count >= 3 else {
            return
        }

        guard widths.allSatisfy({
            $0.isFinite && $0 > 1
        }) else {
            return
        }

        let oldWidths = [

            settings.setPaneWidth,
            settings.libraryPaneWidth,
            settings.smartlistsPaneWidth
        ]

        let changed =
            zip(
                oldWidths,
                widths
            ).contains {

                abs(
                    $0 - $1
                ) > 1.5
            }

        guard changed else {

            return
        }

        DispatchQueue.main.async {

            settings.setPaneWidth =
                widths[0]

            settings.libraryPaneWidth =
                widths[1]

            settings.smartlistsPaneWidth =
                widths[2]

            settings.currentLibraryPaneWidth =
                widths[1]

            print(
                "SPLIT SAVE (pending):",
                widths
            )
        }

        // Debounce the actual disk write — only the last width in a
        // burst of resize notifications actually gets persisted.
        pendingSettingsSaveWorkItem?.cancel()

        let workItem =
            DispatchWorkItem { [weak settings] in

                settings?.save()

                print(
                    "SPLIT SAVE (flushed to disk)"
                )
            }

        pendingSettingsSaveWorkItem =
            workItem

        DispatchQueue.main.asyncAfter(
            deadline:
                .now() + 0.4,
            execute:
                workItem
        )
    }


    private func currentPaneWidths(
        from splitView:
            NSSplitView
    ) -> [Double] {

        splitView.arrangedSubviews.map {

            Double(
                $0.frame.width
            )
        }
    }


    func applySavedWidthsIfPossible() {

        guard !didRestoreInitialWidths else {
            return
        }

        guard
            let splitView,
            let settings
        else {
            return
        }

        guard
            splitView.arrangedSubviews.count >= 3
        else {
            return
        }

        let totalWidth =
            splitView.bounds.width

        guard totalWidth > 100 else {
            return
        }

        let savedWidths = [

            settings.setPaneWidth,
            settings.libraryPaneWidth,
            settings.smartlistsPaneWidth
        ]

        guard savedWidths.allSatisfy({
            $0.isFinite && $0 > 1
        }) else {
            return
        }

        let savedTotal =
            savedWidths.reduce(
                0,
                +
            )

        let actualWidths:
            [Double]

        if abs(savedTotal - Double(totalWidth)) > 0.5 {

            let scale =
                Double(totalWidth) /
                savedTotal

            actualWidths =
                savedWidths.map {
                    $0 * scale
                }

            print(
                "SPLIT LOAD SCALE:",
                "saved:",
                savedTotal,
                "available:",
                totalWidth,
                "scale:",
                scale,
                "result:",
                actualWidths
            )

        } else {

            actualWidths =
                savedWidths
        }

        let currentWidths =
            currentPaneWidths(
                from:
                    splitView
            )

        if currentWidths.count >= 3 {

            let alreadyCorrect =
                zip(
                    currentWidths,
                    actualWidths
                ).allSatisfy {

                    abs(
                        $0 - $1
                    ) < 0.5
                }

            if alreadyCorrect {

                didRestoreInitialWidths =
                    true

                DispatchQueue.main.async {

                    settings.currentLibraryPaneWidth =
                        currentWidths[1]
                }

                print(
                    "SPLIT LOAD: already correct:",
                    currentWidths
                )

                return
            }
        }

        isApplyingSavedWidths =
            true

        ignoreNextResizeNotification =
            true

        let firstDivider =
            actualWidths[0]

        let secondDivider =
            actualWidths[0] +
            actualWidths[1]

        splitView.setPosition(
            CGFloat(
                firstDivider
            ),
            ofDividerAt:
                0
        )

        splitView.setPosition(
            CGFloat(
                secondDivider
            ),
            ofDividerAt:
                1
        )

        DispatchQueue.main.async { [weak self] in

            guard let self else {
                return
            }

            self.isApplyingSavedWidths =
                false

            self.didRestoreInitialWidths =
                true

            // Kept live even though the corresponding libraryPaneWidth
            // save is deliberately suppressed above (this scale is a
            // one-off fit-to-window correction, not a preference to
            // persist) — other windows sizing themselves off the
            // Library column's REAL current width still need this to
            // be accurate. Deferred to main.async along with the flags
            // above — setting a @Published property synchronously
            // inside this NSSplitView layout callback risks re-entrant
            // SwiftUI view updates (same class of bug as the earlier
            // "Publishing changes from within view updates" issue).
            settings.currentLibraryPaneWidth =
                actualWidths[1]
        }

        print(
            "SPLIT LOAD:",
            actualWidths
        )
    }


    private func findSplitView(
        in root:
            NSView?
    ) -> NSSplitView? {

        guard let root else {
            return nil
        }

        if let split =
            root as? NSSplitView,
           split.arrangedSubviews.count >= 3 {

            return split
        }

        for subview in root.subviews {

            if let split =
                findSplitView(
                    in:
                        subview
                ) {

                return split
            }
        }

        return nil
    }
}


// MARK: - Library Mode Help

// Same three explanations that used to live in a single plain-text
// .help() tooltip on the TrackLibrary/TandaLibrary/Setlist Picker —
// moved into a popover (triggered by the "?" button next to the
// Picker) so the three titles can be set in a larger, bold font
// instead of flattened into tooltip text.
private struct LibraryModeHelpView: View {

    private struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    private let sections: [Section] = [

        Section(
            title: "Track Library",
            body: "For experienced DJs: Build your setlist from " +
                "scratch, refining your selection by building " +
                "your own Smartlist — add tracks and narrow them " +
                "down using orchestra and singer combinations. " +
                "This gives you full control over your track " +
                "selection and lets you build every part of your " +
                "set individually."
        ),

        Section(
            title: "Tanda Library",
            body: "For beginners: Build your own Tanda Library by " +
                "grouping tracks into musically compatible sets " +
                "and saving them as Tandas. The system " +
                "automatically recognizes the orchestra and " +
                "singer combinations and adds the corresponding " +
                "Tandas to the Smartlist. This allows you to " +
                "quickly find the right Tandas by orchestra and " +
                "singer when building your setlist."
        ),

        Section(
            title: "Setlists",
            body: "For smart — or simply lazy — DJs: Reuse " +
                "setlists you have already created and save " +
                "yourself the effort of starting from scratch. " +
                "Copy an entire setlist or just the parts you " +
                "like, then adapt, extend, and reuse them for " +
                "your next event."
        )
    ]


    var body: some View {

        ScrollView {

            VStack(
                alignment: .leading,
                spacing: 18
            ) {

                ForEach(sections) { section in

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {

                        Text(section.title)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                }
            }
            .padding(20)
        }
        .frame(
            width: 420,
            height: 420
        )
    }
}


// MARK: - Import Progress

private struct ImportProgressBar:
    View {

    @ObservedObject var scanner:
        LibraryScanner


    var body:
        some View {

        VStack(
            spacing:
                4
        ) {

            ProgressView(
                value:
                    Double(
                        scanner.processedCount
                    ),
                total:
                    Double(
                        max(
                            scanner.totalCount,
                            1
                        )
                    )
            )

            Text(
                "Importing \(scanner.processedCount) " +
                "of \(scanner.totalCount)…"
            )
            .font(
                .caption
            )
            .foregroundStyle(
                .secondary
            )
        }
        .padding(
            8
        )
        .background(
            .regularMaterial
        )
    }
}


// MARK: - M3U8 Document

struct M3U8Document:
    FileDocument {

    static var readableContentTypes:
        [UTType] = []

    let data:
        Data


    init(
        data:
            Data
    ) {

        self.data =
            data
    }


    init(
        configuration:
            ReadConfiguration
    ) throws {

        fatalError(
            "M3U8Document is export-only"
        )
    }


    func fileWrapper(
        configuration:
            WriteConfiguration
    ) throws -> FileWrapper {

        FileWrapper(
            regularFileWithContents:
                data
        )
    }
}


// MARK: - Bordered Column

struct BorderedColumn:
    ViewModifier {

    func body(
        content:
            Content
    ) -> some View {

        content
            .overlay(
                RoundedRectangle(
                    cornerRadius:
                        6
                )
                .stroke(
                    Color.secondary.opacity(
                        0.55
                    ),
                    lineWidth:
                        1
                )
            )
            .padding(
                1
            )
    }
}


extension View {

    func borderedColumn() -> some View {

        modifier(
            BorderedColumn()
        )
    }
}
