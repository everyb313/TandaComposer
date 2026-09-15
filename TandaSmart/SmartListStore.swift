//
//  SmartListStore.swift
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

import Foundation
import Combine

/// A node in the Smartlist tree: either an organizational folder or a leaf rule-set file.
///
/// `id` is derived from the file path (not a fresh random UUID) so that identity survives
/// `reload()` — needed for selection, drag targets, and the editor window (which is opened by id
/// and looks the node back up in the store) to keep working across tree rebuilds. This does mean
/// a node's id changes if the underlying file is moved/renamed; see `SmartlistStore.move`.
final class SmartlistNode: Identifiable, ObservableObject, Equatable {
    var id: String { url.path }
    @Published var name: String
    @Published fileprivate(set) var url: URL
    let isFolder: Bool
    @Published var children: [SmartlistNode]
    /// Populated (lazily, on demand) only for leaf nodes.
    @Published var ruleSet: SmartListRuleSet?

    init(name: String, url: URL, isFolder: Bool, children: [SmartlistNode] = [], ruleSet: SmartListRuleSet? = nil) {
        self.name = name
        self.url = url
        self.isFolder = isFolder
        self.children = children
        self.ruleSet = ruleSet
    }

    static func == (lhs: SmartlistNode, rhs: SmartlistNode) -> Bool { lhs.id == rhs.id }
}

enum SmartPlaylistStoreError: LocalizedError {
    case destinationExists
    case cannotMoveIntoSelfOrDescendant

    var errorDescription: String? {
        switch self {
        case .destinationExists: return "A smartlist or folder with that name already exists there."
        case .cannotMoveIntoSelfOrDescendant: return "Can't move a folder into itself or one of its own subfolders."
        }
    }
}

/// Manages the on-disk folder tree of Smartlist rule-set JSON files.
/// Default location: AppPaths.smartlistFolder (a subfolder of the app's own storage root).
@MainActor
final class SmartlistStore: ObservableObject {
    @Published private(set) var root: SmartlistNode

    /// Gates editing, deleting, creating, and moving smart playlists — applying one via
    /// double-click still works while locked, since browsing/using them is the whole point.
    /// Always starts locked (deliberately not persisted) so a session never "inherits" an
    /// unlocked state from last time without the person noticing.
    @Published var isLocked: Bool = true

    /// Fires with a new value after each successful import — the
    /// tree view observes this to collapse "Imported" back down and
    /// clear any node selection, since the contents just changed
    /// out from under whatever was showing.
    @Published private(set) var lastImportEvent: UUID?

    private let fileManager = FileManager.default

    init(rootURLOverride: URL? = nil) {
        self.rootURLOverride = rootURLOverride
        let rootURL = rootURLOverride ?? Self.defaultRootURL()
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        self.root = SmartlistNode(name: "Smartlists", url: rootURL, isFolder: true)
        reload()
    }

    /// Fixed at construction (currently never actually passed by any
    /// call site, but honored if it ever is) — `reload()` re-derives
    /// against this override too, rather than always falling back to
    /// `defaultRootURL()`.
    private let rootURLOverride: URL?

    static func defaultRootURL() -> URL {
        AppPaths.smartlistFolder
    }

    /// Rebuilds the tree from disk. Selection is kept by id in the UI layer (SmartlistSelection),
    /// so a reload after a save/move naturally re-resolves as long as the id (file path) is unchanged.
    ///
    /// `objectWillChange.send()` is explicit here on purpose: `root` is @Published on the *store*,
    /// but we're mutating `root.children` (a property of the *node* object `root` points to), not
    /// reassigning `root` itself — so the store's own publisher never fires on its own, and any view
    /// observing just the store (not each individual node) would silently miss the update.
    func reload() {

        // Re-derive the root URL fresh every time, not just at
        // construction — the active TrackLibrary (and therefore
        // AppPaths.smartlistFolder) can change after this store was
        // created (see LibraryActions.openLibrary/newLibrary/
        // resetToFactoryState, which call this reload() precisely
        // for that reason). Without this, `root.url` stayed pinned
        // to whichever library was active at app launch, so
        // switching libraries silently kept showing the OLD
        // library's Smartlists until the next full app restart.
        let currentRootURL =
            rootURLOverride ?? Self.defaultRootURL()

        if root.url != currentRootURL {
            try? fileManager.createDirectory(at: currentRootURL, withIntermediateDirectories: true)
            root.url = currentRootURL
        }

        objectWillChange.send()
        root.children = loadChildren(of: root.url)
    }

    private func loadChildren(of folderURL: URL) -> [SmartlistNode] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url -> SmartlistNode? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let node = SmartlistNode(name: url.lastPathComponent, url: url, isFolder: true)
                node.children = loadChildren(of: url)
                return node
            } else if url.pathExtension == "json" {
                let ruleSet = try? loadRuleSet(from: url)
                let name = ruleSet?.name ?? url.deletingPathExtension().lastPathComponent
                return SmartlistNode(name: name, url: url, isFolder: false, ruleSet: ruleSet)
            }
            return nil
        }.sorted { $0.isFolder != $1.isFolder ? $0.isFolder : $0.name < $1.name }
    }

    func loadRuleSet(from url: URL) throws -> SmartListRuleSet {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SmartListRuleSet.self, from: data)
    }

    /// Explicit save — called only from the editor window's Save button, never automatically.
    /// Same objectWillChange note as `reload()` above: this mutates the node directly (from a
    /// *different* window than the tree view), so without an explicit publish here, the tree
    /// wouldn't visibly update until something unrelated forced it to redraw.
    func save(_ ruleSet: SmartListRuleSet, to node: SmartlistNode) throws {
        let data = try JSONEncoder().encode(ruleSet)
        try data.write(to: node.url, options: .atomic)
        objectWillChange.send()
        node.ruleSet = ruleSet
        node.name = ruleSet.name
    }

    /// Finds a node anywhere in the tree by its current id (file path).
    func findNode(id: String) -> SmartlistNode? {
        findNode(id: id, in: [root] + root.children)
    }

    private func findNode(id: String, in nodes: [SmartlistNode]) -> SmartlistNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findNode(id: id, in: node.children) { return found }
        }
        return nil
    }

    @discardableResult
    func createRuleSet(named name: String, in folder: SmartlistNode? = nil) throws -> SmartlistNode {
        let parent = folder ?? root
        let fileURL = parent.url.appendingPathComponent("\(name).json")
        let ruleSet = SmartListRuleSet(name: name)
        let data = try JSONEncoder().encode(ruleSet)
        try data.write(to: fileURL, options: .atomic)
        reload()
        return findNode(id: fileURL.path) ?? SmartlistNode(name: name, url: fileURL, isFolder: false, ruleSet: ruleSet)
    }

    @discardableResult
    func createFolder(named name: String, in folder: SmartlistNode? = nil) throws -> SmartlistNode {
        let parent = folder ?? root
        let folderURL = parent.url.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        reload()
        return findNode(id: folderURL.path) ?? SmartlistNode(name: name, url: folderURL, isFolder: true)
    }

    func delete(_ node: SmartlistNode) throws {
        try fileManager.removeItem(at: node.url)
        reload()
    }

    /// Moves `node` (file or folder) to become a child of `destinationFolder`. Drag-and-drop only —
    /// no separate "move to folder" menu. Fails on a name collision at the destination rather than
    /// silently renaming, and refuses to move a folder into itself or its own descendant.
    func move(_ node: SmartlistNode, into destinationFolder: SmartlistNode) throws {
        guard destinationFolder.isFolder, node.id != destinationFolder.id else { return }

        if node.isFolder {
            let sourcePrefix = node.url.path + "/"
            guard !(destinationFolder.url.path + "/").hasPrefix(sourcePrefix) else {
                throw SmartPlaylistStoreError.cannotMoveIntoSelfOrDescendant
            }
        }

        let destinationURL = destinationFolder.url.appendingPathComponent(node.url.lastPathComponent)
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw SmartPlaylistStoreError.destinationExists
        }

        try fileManager.moveItem(at: node.url, to: destinationURL)
        reload()
    }


    // MARK: - Export / Import

    private var importedFolderURL: URL {
        root.url.appendingPathComponent("Imported", isDirectory: true)
    }

    /// Node id (= file path) of the internal "Imported" folder — the
    /// tree view uses this to collapse it back down after an import.
    var importedFolderID: String {
        importedFolderURL.path
    }

    /// Whether an "Imported" folder already has content — callers
    /// use this to decide whether to warn before overwriting it.
    var importedFolderExists: Bool {
        fileManager.fileExists(atPath: importedFolderURL.path)
    }

    /// Copies the complete Smart Playlist tree to `destinationURL`
    /// (a not-yet-existing folder chosen by the user).
    func exportAll(to destinationURL: URL) throws {
        try fileManager.copyItem(at: root.url, to: destinationURL)
    }

    /// Replaces the internal "Imported" folder with the CONTENTS of
    /// `sourceURL` — not `sourceURL` itself. That's deliberate: it
    /// means importing a previously exported tree, even one that
    /// itself contains an "Imported" subfolder, never nests
    /// "Imported/Imported" — only sourceURL's children ever become
    /// Imported's children, regardless of what sourceURL is named.
    ///
    /// Deletes any existing "Imported" folder first — callers are
    /// expected to confirm that with the user via
    /// `importedFolderExists` before calling this.
    func importAll(from sourceURL: URL) throws {

        if fileManager.fileExists(atPath: importedFolderURL.path) {
            try fileManager.removeItem(at: importedFolderURL)
        }

        try fileManager.createDirectory(
            at: importedFolderURL,
            withIntermediateDirectories: true
        )

        let items = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for item in items {

            let destination =
                importedFolderURL.appendingPathComponent(item.lastPathComponent)

            try fileManager.copyItem(at: item, to: destination)
        }

        reload()

        lastImportEvent = UUID()
    }
}
