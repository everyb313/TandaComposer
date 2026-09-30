//
//  SmartListTreeView.swift
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

/// The binding shared with the library column: which filter is currently applied.
///
/// This only changes on double-click.
/// Single-click only changes local row highlighting.
enum SmartlistSelection: Equatable {
    case showAll
    case node(SmartlistNode)

    static func == (
        lhs: SmartlistSelection,
        rhs: SmartlistSelection
    ) -> Bool {
        switch (lhs, rhs) {
        case (.showAll, .showAll):
            return true

        case let (.node(a), .node(b)):
            return a.id == b.id

        default:
            return false
        }
    }
}

struct SmartListTreeView: View {
    @ObservedObject var store: SmartlistStore

    /// Applied filter — only changed by double-click.
    @Binding var selection: SmartlistSelection

    /// Single-click highlight.
    @State private var highlightedID: String?

    @State private var showingNewFolderPrompt = false
    @State private var showingNewRuleSetPrompt = false

    @State private var newFolderName = ""
    @State private var newRuleSetName = ""

    @State private var moveErrorMessage: String?

    /// Node awaiting delete confirmation — set instead of deleting immediately from
    /// either the toolbar trash button or the context menu's Delete item.
    @State private var pendingDelete: SmartlistNode?

    /// Current drop target.
    @State private var dropTargetID: String?

    /// Folders currently expanded — drives the DisclosureGroup tree below.
    /// Managed explicitly (instead of OutlineGroup's implicit state) so
    /// double-click can toggle it programmatically.
    @State private var expandedFolderIDs: Set<String> = []

    @Environment(\.openWindow) private var openWindow

    private let showAllRowID = "showAll"

    var body: some View {
        VStack(spacing: 0) {
            List {
                showAllRow

                ForEach(store.root.children) { node in
                    treeRow(for: node)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)

            Divider()

            HStack(spacing: 8) {
                Button {
                    showingNewRuleSetPrompt = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(store.isLocked)
                .help(store.isLocked ? "Unlock to create a new smartlist" : "New Smartlist")

                Button {
                    showingNewFolderPrompt = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .disabled(store.isLocked)
                .help(store.isLocked ? "Unlock to create a new folder" : "New Folder")

                Spacer()

                Button(role: .destructive) {
                    if let node = highlightedNode {
                        pendingDelete = node
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.isLocked || highlightedNode == nil)
                .help(store.isLocked ? "Unlock to delete" : "Delete")
            }
            .padding(8)
        }
        .onChange(of: store.lastImportEvent) {

            expandedFolderIDs.remove(store.importedFolderID)

            if case .node = selection {
                selection = .showAll
            }
        }
        .alert(
            "New Smartlist",
            isPresented: $showingNewRuleSetPrompt
        ) {
            TextField("Name", text: $newRuleSetName)

            Button("Create") {
                guard !newRuleSetName.isEmpty else {
                    return
                }

                _ = try? store.createRuleSet(
                    named: newRuleSetName,
                    in: parentForNewItem
                )

                newRuleSetName = ""
            }

            Button("Cancel", role: .cancel) {
                newRuleSetName = ""
            }
        }
        .alert(
            "New Folder",
            isPresented: $showingNewFolderPrompt
        ) {
            TextField("Name", text: $newFolderName)

            Button("Create") {
                guard !newFolderName.isEmpty else {
                    return
                }

                _ = try? store.createFolder(
                    named: newFolderName,
                    in: parentForNewItem
                )

                newFolderName = ""
            }

            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        }
        .alert(
            "Couldn't Move",
            isPresented: .constant(moveErrorMessage != nil),
            presenting: moveErrorMessage
        ) { _ in
            Button("OK") {
                moveErrorMessage = nil
            }
        } message: {
            Text($0)
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: .constant(pendingDelete != nil),
            presenting: pendingDelete
        ) { node in
            Button("Delete", role: .destructive) {
                try? store.delete(node)
                clearIfNeeded(node)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { node in
            Text(deleteConfirmationMessage(for: node))
        }
    }

    // MARK: - Delete Confirmation

    private var deleteConfirmationTitle: String {
        guard let node = pendingDelete else { return "" }
        return node.isFolder ? "Delete Folder?" : "Delete Smartlist?"
    }

    /// Every non-folder descendant of `node` (or just `node` itself if it's a leaf) —
    /// deleting a folder removes everything inside it on disk, so the confirmation
    /// should say exactly what that includes rather than just naming the folder.
    private func affectedFileNames(for node: SmartlistNode) -> [String] {
        guard node.isFolder else { return [node.name] }
        return node.children.flatMap { affectedFileNames(for: $0) }
    }

    private func deleteConfirmationMessage(for node: SmartlistNode) -> String {
        guard node.isFolder else {
            return "\"\(node.name)\" will be deleted. This can't be undone."
        }
        let affected = affectedFileNames(for: node)
        if affected.isEmpty {
            return "\"\(node.name)\" is empty and will be deleted. This can't be undone."
        }
        let list = affected.map { "• \($0)" }.joined(separator: "\n")
        return "\"\(node.name)\" and everything inside it will be deleted — \(affected.count) smartlist(s):\n\n\(list)\n\nThis can't be undone."
    }

    // MARK: - Show All

    private var showAllRow: some View {
        Label(
            "Show All",
            systemImage: "list.bullet"
        )
        .fontWeight(
            selection == .showAll
                ? .semibold
                : .regular
        )
        .listRowBackground(
            rowBackground(
                id: showAllRowID,
                isHighlighted: highlightedID == nil
            )
        )
        .contentShape(Rectangle())

        // Double-click applies Show All.
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    selection = .showAll
                }
        )

        // Single-click only highlights.
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded {
                    highlightedID = nil
                }
        )

        // Native macOS drag destination — only while unlocked.
        .if(!store.isLocked) { view in
            view.onDrop(
                of: [UTType.text.identifier],
                isTargeted: Binding(
                    get: {
                        dropTargetID == showAllRowID
                    },
                    set: { targeted in
                        if targeted {
                            dropTargetID = showAllRowID
                        } else if dropTargetID == showAllRowID {
                            dropTargetID = nil
                        }
                    }
                ),
                perform: {
                    providers in

                    handleDrop(
                        providers: providers,
                        destinationID: showAllRowID
                    )
                }
            )
        }
    }

    // MARK: - Tree

    /// Recursive replacement for OutlineGroup — folders render as a
    /// DisclosureGroup whose expand state is driven by `expandedFolderIDs`,
    /// so double-click (in `row(for:)`) can toggle it. Leaf nodes render
    /// as a plain row.
    @ViewBuilder
    private func treeRow(
        for node: SmartlistNode
    ) -> some View {
        if node.isFolder {
            DisclosureGroup(
                isExpanded: Binding(
                    get: {
                        expandedFolderIDs.contains(node.id)
                    },
                    set: { expanded in
                        if expanded {
                            expandedFolderIDs.insert(node.id)
                        } else {
                            expandedFolderIDs.remove(node.id)
                        }
                    }
                )
            ) {
                ForEach(node.childrenIfFolder ?? []) { child in
                    AnyView(treeRow(for: child))
                }
            } label: {
                row(for: node)
            }
        } else {
            row(for: node)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(
        for node: SmartlistNode
    ) -> some View {
        Label(
            node.name,
            systemImage: node.isFolder
                ? "folder.fill"
                : "line.3.horizontal.decrease.circle"
        )
        .fontWeight(
            isApplied(node)
                ? .semibold
                : .regular
        )
        .opacity(
            dropTargetID == node.id
                ? 1.0
                : 1.0
        )
        .listRowBackground(
            rowBackground(
                id: node.id,
                isHighlighted: highlightedID == node.id
            )
        )
        .contentShape(Rectangle())

        // ---------------------------------------------------------
        // Selection
        // ---------------------------------------------------------

        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    if node.isFolder {
                        highlightedID = node.id

                        if expandedFolderIDs.contains(node.id) {
                            expandedFolderIDs.remove(node.id)
                        } else {
                            expandedFolderIDs.insert(node.id)
                        }
                    } else {
                        selection = .node(node)
                    }
                }
        )

        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded {
                    highlightedID = node.id
                }
        )

        // ---------------------------------------------------------
        // Context menu
        // ---------------------------------------------------------

        .contextMenu {
            if !store.isLocked {
                if !node.isFolder {
                    Button("Edit…") {
                        openWindow(value: node.id)
                    }
                }

                Button("Delete", role: .destructive) {
                    pendingDelete = node
                }
            }
        }

        // ---------------------------------------------------------
        // DRAG SOURCE
        //
        // Do NOT use .draggable here.
        //
        // onDrag gives us an explicit NSItemProvider containing the
        // node ID. This is the macOS drag mechanism that works well
        // with List / OutlineGroup.
        //
        // Disabled while locked — moving a smart playlist counts as
        // editing the tree, same as delete/edit/create.
        // ---------------------------------------------------------

        .if(!store.isLocked) { view in
            view.onDrag {
                NSItemProvider(
                    object: NSString(string: node.id)
                )
            }
        }

        // ---------------------------------------------------------
        // DROP TARGET
        //
        // Only folders accept drops, and only while unlocked.
        //
        // We attach this directly to the Label, whose contentShape
        // makes the complete visible row interactive.
        // ---------------------------------------------------------

        .if(node.isFolder && !store.isLocked) { view in
            view.onDrop(
                of: [UTType.text.identifier],
                isTargeted: Binding(
                    get: {
                        dropTargetID == node.id
                    },
                    set: { targeted in
                        if targeted {
                            dropTargetID = node.id
                        } else if dropTargetID == node.id {
                            dropTargetID = nil
                        }
                    }
                ),
                perform: {
                    providers in

                    handleDrop(
                        providers: providers,
                        destinationID: node.id
                    )
                }
            )
        }
    }

    // MARK: - Drag / Drop

    private func handleDrop(
        providers: [NSItemProvider],
        destinationID: String
    ) -> Bool {
        guard let provider = providers.first else {
            dropTargetID = nil
            return false
        }

        provider.loadObject(
            ofClass: NSString.self
        ) { object, error in

            DispatchQueue.main.async {
                dropTargetID = nil

                guard error == nil else {
                    return
                }

                //guard let object else {
                //    return
                //}
                
                guard let object = object as? NSString else {
                    return
                }

                let nodeID = object as String

                // Never drop onto itself.
                guard nodeID != destinationID else {
                    return
                }

                performMove(
                    nodeID: nodeID,
                    intoFolderID: destinationID
                )
            }
        }

        return true
    }

    private func performMove(
        nodeID: String,
        intoFolderID folderID: String
    ) {
        guard let dragged = store.findNode(id: nodeID) else {
            return
        }

        let destination: SmartlistNode?

        if folderID == showAllRowID {
            destination = store.root
        } else {
            destination = store.findNode(id: folderID)
        }

        guard let destination else {
            return
        }

        do {
            try store.move(
                dragged,
                into: destination
            )
        } catch {
            moveErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Appearance

    private func rowBackground(
        id: String,
        isHighlighted: Bool
    ) -> Color {
        if dropTargetID == id {
            return Color.accentColor.opacity(0.35)
        }

        if isHighlighted {
            return Color.accentColor.opacity(0.15)
        }

        return Color.clear
    }

    // MARK: - Selection

    private var highlightedNode: SmartlistNode? {
        highlightedID.flatMap {
            store.findNode(id: $0)
        }
    }

    private var parentForNewItem: SmartlistNode? {
        guard let node = highlightedNode,
              node.isFolder
        else {
            return nil
        }

        return node
    }

    private func isApplied(
        _ node: SmartlistNode
    ) -> Bool {
        if case .node(let selected) = selection {
            return selected.id == node.id
        }

        return false
    }

    private func clearIfNeeded(
        _ node: SmartlistNode
    ) {
        if highlightedID == node.id {
            highlightedID = nil
        }

        if case .node(let selected) = selection,
           selected.id == node.id {
            selection = .showAll
        }
    }
}

// MARK: - SmartlistNode

private extension SmartlistNode {
    /// Used by the recursive tree walk for a folder's children.
    var childrenIfFolder: [SmartlistNode]? {
        isFolder
            ? children
            : nil
    }
}

// MARK: - Conditional View Modifier

private extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
