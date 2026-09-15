//
//  TandaFolderTreeView.swift
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


// MARK: - Tanda Folder Tree View
//
// Read-only counterpart to SmartListTreeView for the Tandas display
// mode: instead of user-defined rule-based smartlists, this just
// browses the actual `Tandas/<Artist>/` folder structure that Tanda-
// saving already creates on disk (see PlaylistView.swift's
// TandaStorage.ensureTandaFolder). No create/delete/lock/drag — the
// folders aren't a manually-curated structure, they're a direct
// reflection of where Tandas happen to be saved.
//
// Same click convention as SmartListTreeView: single-click only
// highlights a row; double-click actually applies the filter.

struct TandaFolderTreeView:
    View {

    /// Passed in from the shared, hoisted TandaStore (see ContentView)
    /// instead of this view owning/loading its own — `rootNodes` below
    /// derives from this and updates automatically via normal SwiftUI
    /// reactivity whenever it changes, no notification listener
    /// needed anymore.
    let tandas:
        [Tanda]

    @Binding var selection:
        TandaFolderSelection

    @State private var highlightedID:
        String?

    /// Folders currently expanded — same explicit-state pattern as
    /// SmartListTreeView (not OutlineGroup's implicit state), so
    /// double-click can toggle it programmatically.
    @State private var expandedFolderIDs:
        Set<String> = []

    private let showAllRowID =
        "showAll"

    private var rootNodes:
        [TandaFolderNode] {

        TandaFolderTree.buildTree(
            fromSourceFolders:
                tandas.map(\.sourceFolder)
        )
    }


    var body:
        some View {

        VStack(
            spacing:
                0
        ) {

            List {

                showAllRow

                ForEach(
                    rootNodes
                ) { node in

                    AnyView(
                        treeRow(
                            for:
                                node
                        )
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
        }
    }


    // MARK: - Show All

    private var showAllRow:
        some View {

        Label(
            "Show All",
            systemImage:
                "list.bullet"
        )
        .fontWeight(
            selection == .showAll
                ? .semibold
                : .regular
        )
        .listRowBackground(
            rowBackground(
                isHighlighted:
                    highlightedID == nil
            )
        )
        .contentShape(
            Rectangle()
        )

        // Double-click applies Show All.
        .simultaneousGesture(
            TapGesture(
                count:
                    2
            )
            .onEnded {

                selection =
                    .showAll
            }
        )

        // Single-click only highlights.
        .simultaneousGesture(
            TapGesture(
                count:
                    1
            )
            .onEnded {

                highlightedID =
                    nil
            }
        )
    }


    // MARK: - Tree

    @ViewBuilder
    private func treeRow(
        for node:
            TandaFolderNode
    ) -> some View {

        if node.children.isEmpty {

            row(
                for:
                    node
            )

        } else {

            DisclosureGroup(
                isExpanded:
                    Binding(
                        get: {

                            expandedFolderIDs.contains(
                                node.id
                            )
                        },
                        set: { expanded in

                            if expanded {

                                expandedFolderIDs.insert(
                                    node.id
                                )

                            } else {

                                expandedFolderIDs.remove(
                                    node.id
                                )
                            }
                        }
                    )
            ) {

                ForEach(
                    node.children
                ) { child in

                    AnyView(
                        treeRow(
                            for:
                                child
                        )
                    )
                }

            } label: {

                row(
                    for:
                        node
                )
            }
        }
    }


    // MARK: - Row

    private func row(
        for node:
            TandaFolderNode
    ) -> some View {

        Label(
            node.name,
            systemImage:
                "folder.fill"
        )
        .fontWeight(
            isApplied(
                node
            )
            ? .semibold
            : .regular
        )
        .listRowBackground(
            rowBackground(
                isHighlighted:
                    highlightedID == node.id
            )
        )
        .contentShape(
            Rectangle()
        )

        // Double-click: apply this folder as the filter. If it also
        // has children, expand/collapse it too (matches Smartlists'
        // "double-click both selects and toggles" behavior for
        // folders — a folder here can both BE a filter target and
        // CONTAIN further subfolders).
        .simultaneousGesture(
            TapGesture(
                count:
                    2
            )
            .onEnded {

                highlightedID =
                    node.id

                selection =
                    .folder(
                        node.id
                    )

                if !node.children.isEmpty {

                    if expandedFolderIDs.contains(
                        node.id
                    ) {

                        expandedFolderIDs.remove(
                            node.id
                        )

                    } else {

                        expandedFolderIDs.insert(
                            node.id
                        )
                    }
                }
            }
        )

        // Single-click: highlight only.
        .simultaneousGesture(
            TapGesture(
                count:
                    1
            )
            .onEnded {

                highlightedID =
                    node.id
            }
        )
    }


    // MARK: - Appearance

    private func rowBackground(
        isHighlighted:
            Bool
    ) -> Color {

        isHighlighted
        ? Color.accentColor.opacity(
            0.15
        )
        : Color.clear
    }


    // MARK: - Selection

    private func isApplied(
        _ node:
            TandaFolderNode
    ) -> Bool {

        if case .folder(let path) =
            selection {

            return path == node.id
        }

        return false
    }
}
