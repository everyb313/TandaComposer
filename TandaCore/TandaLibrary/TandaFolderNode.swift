//
//  TandaFolderNode.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 24.08.26.
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


// MARK: - Tanda Folder Node

/// One folder in the `Tandas/` directory tree — e.g. "Biagi", or in the
/// future "Biagi/Live" if deeper nesting is ever introduced. Built
/// recursively so the tree view can go arbitrarily deep, even though
/// only one level ("Tandas/<Artist>/") is actually produced by the save
/// logic today.
struct TandaFolderNode:
    Identifiable,
    Equatable {

    /// Relative path from the `Tandas/` root — e.g. "Biagi". This is
    /// also what TandaFolderSelection.folder(_:) carries, and what
    /// Tanda.sourceFolder is compared against for filtering.
    let id: String

    /// Last path component — what's actually displayed in the row.
    let name: String

    let children: [TandaFolderNode]
}


// MARK: - Tanda Folder Selection

/// The binding shared with the Tandas library column: which folder
/// filter is currently applied. Only changes on double-click — single-
/// click only changes local row highlighting (same convention as
/// SmartlistSelection).
enum TandaFolderSelection:
    Equatable {

    case showAll
    case folder(String)
}


// MARK: - Tanda Folder Tree (Scanning)

enum TandaFolderTree {

    /// Scans `AppPaths.root/Tandas/` and returns its top-level
    /// subfolders as a recursive tree. Only directories are included
    /// — the `.json` Tanda files themselves don't appear as tree
    /// nodes, only the folders that contain them.
    static func loadRoot() -> [TandaFolderNode] {

        let tandasRoot =
            AppPaths.tandasFolder

        return children(
            of:
                tandasRoot,
            relativePath:
                ""
        )
    }


    private static func children(
        of folderURL:
            URL,
        relativePath:
            String
    ) -> [TandaFolderNode] {

        guard
            let entries =
                try? FileManager.default.contentsOfDirectory(
                    at:
                        folderURL,
                    includingPropertiesForKeys:
                        [.isDirectoryKey]
                )
        else {

            return []
        }

        let subfolders =
            entries.filter {
                (
                    try? $0.resourceValues(
                        forKeys:
                            [.isDirectoryKey]
                    )
                )?.isDirectory == true
            }
            .sorted {
                $0.lastPathComponent
                    .localizedStandardCompare(
                        $1.lastPathComponent
                    ) == .orderedAscending
            }

        return subfolders.map { url in

            let name =
                url.lastPathComponent

            let path =
                relativePath.isEmpty
                ? name
                : "\(relativePath)/\(name)"

            return TandaFolderNode(
                id:
                    path,
                name:
                    name,
                children:
                    children(
                        of:
                            url,
                        relativePath:
                            path
                    )
            )
        }
    }


    // MARK: - Tanda Folder Tree (From Loaded Tandas)

    /// Builds the same tree shape as `loadRoot()`, but from the
    /// `sourceFolder` of already-loaded Tandas instead of scanning
    /// `Tandas/` on disk itself — used by TandaFolderTreeView so it
    /// can derive its tree from whatever TandaStore the app already
    /// has loaded (shared, hoisted to ContentView — see its
    /// `tandaStore`) rather than re-scanning the folder structure on
    /// every appearance.
    ///
    /// Trade-off worth knowing: a folder that exists on disk but
    /// currently holds zero Tandas (e.g. the last Tanda in it was just
    /// deleted, or someone made an empty folder by hand in Finder)
    /// won't appear here — `loadRoot()` would still show it, this
    /// won't. Every folder the app itself creates always gets a Tanda
    /// saved into it in the very same step (see
    /// TandaStorage.ensureTandaFolder), so this only differs from
    /// `loadRoot()` for folders created or emptied outside the app.
    static func buildTree(
        fromSourceFolders sourceFolders: [String]
    ) -> [TandaFolderNode] {

        var childPathsByParent:
            [String: Set<String>] = [:]

        for folder in sourceFolders {

            guard !folder.isEmpty else {
                continue
            }

            let components =
                folder.split(separator: "/").map(String.init)

            var currentPath = ""

            for component in components {

                let parentPath = currentPath

                currentPath =
                    currentPath.isEmpty
                    ? component
                    : "\(currentPath)/\(component)"

                childPathsByParent[
                    parentPath, default: []
                ].insert(currentPath)
            }
        }

        func nodes(forParent parent: String) -> [TandaFolderNode] {

            let childPaths =
                (childPathsByParent[parent] ?? [])
                    .sorted {
                        $0.localizedStandardCompare($1)
                            == .orderedAscending
                    }

            return childPaths.map { path in

                let name =
                    path.components(separatedBy: "/").last
                        ?? path

                return TandaFolderNode(
                    id: path,
                    name: name,
                    children: nodes(forParent: path)
                )
            }
        }

        return nodes(forParent: "")
    }
}
