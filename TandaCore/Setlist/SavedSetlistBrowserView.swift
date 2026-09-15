//
//  SavedSetlistBrowserView.swift
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


// MARK: - Saved Setlist Browser View
//
// Right-panel counterpart to SmartListTreeView (Tracks mode) and
// TandaFolderTreeView (Tandas mode) for the new "Setlist" mode: a flat
// list of saved Setlist names (no subfolders — saved Setlists aren't
// nested like Tandas are). Single-click only highlights; double-click
// loads that Setlist into `viewerStore` for read-only display in the
// middle column. Purely a picker — no create/delete/lock here (Setlist
// management already has its own Open/Delete Setlist menu elsewhere).

struct SavedSetlistBrowserView:
    View {

    @EnvironmentObject
    private var playlistStore:
        PlaylistStore

    @EnvironmentObject
    private var libraryStore:
        LibraryStore

    @ObservedObject
    var viewerStore:
        SavedSetlistViewerStore

    @State
    private var highlightedName:
        String?

    @State
    private var loadErrorMessage:
        String?


    var body:
        some View {

        List {

            ForEach(
                playlistStore.savedPlaylistNamesList,
                id:
                    \.self
            ) { name in

                let isCurrentlyShown =
                    viewerStore.setlistName == name

                // The Setlist currently being edited (left column) —
                // pulling it into the middle view would just show what
                // the left column already has, so it's disabled here
                // too, same as the one already loaded into the middle.
                let isActiveSetlist =
                    playlistStore.name == name

                let isDisabled =
                    isCurrentlyShown ||
                    isActiveSetlist


                Label(
                    name,
                    systemImage:
                        "music.note.list"
                )
                .fontWeight(
                    isCurrentlyShown
                    ? .semibold
                    : .regular
                )
                .foregroundStyle(
                    isDisabled
                    ? AnyShapeStyle(
                        .tertiary
                    )
                    : AnyShapeStyle(
                        .primary
                    )
                )
                .listRowBackground(
                    highlightedName == name
                    ? Color.accentColor.opacity(
                        0.15
                    )
                    : Color.clear
                )
                .contentShape(
                    Rectangle()
                )
                .help(
                    isCurrentlyShown
                    ? "Already showing"
                    : isActiveSetlist
                    ? "This is the Setlist currently being edited"
                    : ""
                )
                .simultaneousGesture(
                    TapGesture(
                        count:
                            2
                    )
                    .onEnded {

                        guard
                            !isDisabled
                        else {
                            return
                        }

                        highlightedName =
                            name

                        loadSetlist(
                            named:
                                name
                        )
                    }
                )
                .simultaneousGesture(
                    TapGesture(
                        count:
                            1
                    )
                    .onEnded {

                        guard
                            !isDisabled
                        else {
                            return
                        }

                        highlightedName =
                            name
                    }
                )
            }
        }
        .listStyle(
            .sidebar
        )
        .scrollContentBackground(
            .hidden
        )
        .background(
            Color.clear
        )
        .alert(
            "Couldn't Open Setlist",
            isPresented:
                .constant(
                    loadErrorMessage != nil
                ),
            presenting:
                loadErrorMessage
        ) { _ in

            Button(
                "OK"
            ) {

                loadErrorMessage =
                    nil
            }

        } message: { message in

            Text(
                message
            )
        }
        // Keep an already-open saved Setlist's songs (paths in
        // particular) current if the Library changes while it's being
        // viewed — same pattern PlaylistView uses for the live Set,
        // otherwise a rescan/relocation after opening a saved Setlist
        // wouldn't be reflected until it's reloaded.
        .onChange(
            of:
                libraryStore.songs
        ) { _, _ in

            viewerStore.resolveAgainstLibrary(
                byID:
                    libraryStore.songsByID,
                byPath:
                    libraryStore.songsByNormalizedPath,
                missingSongIDs:
                    libraryStore.missingSongIDs
            )
        }
        .onChange(
            of:
                libraryStore.missingSongIDs
        ) { _, newMissing in

            viewerStore.resolveAgainstLibrary(
                byID:
                    libraryStore.songsByID,
                byPath:
                    libraryStore.songsByNormalizedPath,
                missingSongIDs:
                    newMissing
            )
        }
        // "Rescan Saved Setlists" (option C) rewrites saved Setlist
        // FILES directly — if the one currently open here happens to
        // be among them, its in-memory `songs` (already corrected by
        // the .onChange handlers above, at least for path) don't need
        // a reload for playback to work, but reloading anyway keeps
        // every other field (e.g. re-tagged metadata) in sync with
        // what's now actually on disk, and is cheap.
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    .setlistSaved
            )
        ) { _ in

            if let currentName = viewerStore.setlistName {

                loadSetlist(
                    named:
                        currentName
                )
            }
        }
    }


    private func loadSetlist(
        named name:
            String
    ) {

        do {

            try viewerStore.load(
                name:
                    name,
                byID:
                    libraryStore.songsByID,
                byPath:
                    libraryStore.songsByNormalizedPath,
                missingSongIDs:
                    libraryStore.missingSongIDs
            )

        } catch {

            loadErrorMessage =
                error.localizedDescription
        }
    }
}
