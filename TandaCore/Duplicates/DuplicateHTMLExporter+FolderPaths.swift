//
//  DuplicateHTMLExporter+FolderPaths.swift
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

//
//  DuplicateHTMLExporter.swift
//  TandaComposer
//

import Foundation

// MARK: - Folder path & metadata helpers

extension DuplicateHTMLExporter {

    // MARK: - Folder Basename
    // =============================================================

    static func folderBasename(
        _ path: String
    ) -> String {

        URL(
            fileURLWithPath: path
        )
        .lastPathComponent
    }

    // =============================================================
    // MARK: - Folder Metadata
    // =============================================================

    static func folderMeta(
        sampleRates: Set<String>,
        fileTypes: Set<String>
    ) -> String {

        let rates =
            sampleRates
                .sorted()
                .joined(
                    separator: ", "
                )

        let types =
            fileTypes
                .sorted()
                .joined(
                    separator: ", "
                )

        return
            "\(rates) · \(types)"
    }

    // =============================================================
    // MARK: - Combined Field
    // =============================================================

    static func combinedField(
        _ a: String?,
        _ b: String?
    ) -> String {

        let valueA =
            a?.isEmpty == false
            ? a!
            : "—"

        let valueB =
            b?.isEmpty == false
            ? b!
            : "—"

        if valueA == valueB {
            return valueA
        }

        return
            "\(valueA) / \(valueB)"
    }

    // =============================================================
    // MARK: - Folder Extraction
    // =============================================================

    static func comparisonFolders(
        in cluster: DuplicateCluster
    ) -> [String] {

        let folders =
            Set(
                cluster.songs.map {
                    parentFolder(
                        of: $0.path
                    )
                }
            )

        return
            folders.sorted {
                $0.localizedCaseInsensitiveCompare(
                    $1
                )
                ==
                .orderedAscending
            }
    }

    // =============================================================
    // MARK: - Parent Folder
    // =============================================================

    static func parentFolder(
        of path: String
    ) -> String {

        let url =
            URL(
                fileURLWithPath:
                    path
            )

        return
            url
            .deletingLastPathComponent()
            .path
    }

    // =============================================================
}
