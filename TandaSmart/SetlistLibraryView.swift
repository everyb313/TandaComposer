//
//  SetlistLibraryView.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 26.08.26.
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


// MARK: - Setlist Library View
//
// Middle-column content for the "Setlist" library display mode. Shows
// whichever saved Setlist was double-clicked in SavedSetlistBrowser-
// View (the right panel, in this mode), in its actual saved order —
// read-only, via LibraryTableView's new `allowsSorting: false`.
//
// Dragging rows out works exactly like Track Library (same
// LibraryTableView drag source, same SetInsertionMode toggle), so the
// existing Library-drag branch in PlaylistView's drop handling needs no
// changes at all.

struct SetlistLibraryView:
    View {

    @ObservedObject
    var viewerStore:
        SavedSetlistViewerStore

    @State
    private var selection:
        Set<Int64?> = []

    @State
    private var insertionMode:
        SetInsertionMode = .add


    var body:
        some View {

        VStack(
            spacing:
                0
        ) {

            if viewerStore.setlistName == nil {

                VStack {

                    Spacer()

                    Text(
                        "Select a saved Setlist on the right to view it here."
                    )
                    .foregroundStyle(
                        .secondary
                    )

                    Spacer()
                }

            } else {

                LibraryTableView(
                    songs:
                        viewerStore.songs,
                    missingSongIDs:
                        [],
                    selection:
                        $selection,
                    insertionMode:
                        insertionMode,
                    allowsSorting:
                        false
                )
            }


            Divider()


            // =====================================================
            // BOTTOM BAR
            // =====================================================

            HStack {

                Text(
                    "\(viewerStore.songs.count) track(s)"
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )


                Spacer()


                // =====================================================
                // ADD / INSERT TO SET
                //
                // Same component as Track Library's toggle — not
                // gated by the Library lock, same as dragging directly
                // out of Track Library isn't either (only imports and
                // deletes are lock-gated, not adding to the Set).
                // =====================================================

                Toggle(
                    isOn:
                        Binding(
                            get: {

                                insertionMode == .insert
                            },
                            set: { isInsert in

                                insertionMode =
                                    isInsert
                                    ? .insert
                                    : .add
                            }
                        )
                ) {

                    Label(
                        insertionMode.buttonTitle,
                        systemImage:
                            insertionMode.systemImage
                    )
                }
                .toggleStyle(
                    SetInsertionToggleStyle()
                )
                .help(
                    insertionMode.helpText
                )
                .disabled(
                    viewerStore.setlistName == nil
                )
            }
            .padding(
                8
            )
        }
    }
}
