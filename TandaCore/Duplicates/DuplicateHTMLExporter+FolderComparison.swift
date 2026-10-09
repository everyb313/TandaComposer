//
//  DuplicateHTMLExporter+FolderComparison.swift
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

// MARK: - Folder comparison rendering

extension DuplicateHTMLExporter {

    // MARK: - Shared Folder Comparison
    // =============================================================

    struct Level3SongRow {

        let title: String
        let artist: String
        let albumArtist: String
        let year: String
        let sampleRate: String
        let fileType: String
        let filenameA: String
        let filenameB: String
    }

    struct Level3Block {

        let id: String
        let folderA: String
        let folderB: String
        let trackCountA: Int
        let trackCountB: Int
        let folderNameA: String
        let folderNameB: String
        let metaA: String
        let metaB: String
        let rows: [Level3SongRow]
    }

    struct FolderPairKey: Hashable {

        let folderA: String
        let folderB: String
    }

    static func renderFolderComparison(
        clusters: [DuplicateCluster],
        level: DuplicateLevel,
        librarySongs: [Song]
    ) -> String {

        let blocks =
            makeFolderBlocks(
                clusters: clusters,
                librarySongs: librarySongs
            )

        var html = """
        <div class="folder-comparison">

        <h2>
            Folder Comparison — Level \(level.rawValue)
        </h2>
        """

        if blocks.isEmpty {

            html += """
            <div class="empty">
                No folder comparisons available.
            </div>

            </div>
            """

            return html
        }

        // MARK: Summary

        html += """
        <div class="level3-summary">

        <table>
        <thead>
        <tr>
            <th>Subfolder A</th>
            <th>Subfolder B</th>
            <th>Common Tracks</th>
        </tr>
        </thead>

        <tbody>
        """

        for block in blocks {

            html += """
            <tr>
                <td class="folder-path">
                    <a href="#\(block.id)">
                        \(escapeHTML(block.folderA))
                    </a>
                </td>

                <td class="folder-path">
                    <a href="#\(block.id)">
                        \(escapeHTML(block.folderB))
                    </a>
                </td>

                <td>
                    <a href="#\(block.id)">
                        \(block.rows.count)
                    </a>
                </td>
            </tr>
            """
        }

        html += """
        </tbody>
        </table>

        </div>
        """

        // MARK: Folder Blocks

        for block in blocks {

            html += """
            <div class="level3-block" id="\(block.id)">

            <div class="level3-block-header">

                <div class="level3-block-label">
                    Subfolder A · \(block.trackCountA) track(s)
                </div>

                <div class="level3-block-name">
                    \(escapeHTML(block.folderNameA))
                </div>

                <div class="level3-block-meta">
                    \(escapeHTML(block.metaA))
                </div>

                <div class="level3-block-path">
                    \(escapeHTML(block.folderA))
                </div>

                <div class="level3-block-label">
                    Subfolder B · \(block.trackCountB) track(s)
                </div>

                <div class="level3-block-name">
                    \(escapeHTML(block.folderNameB))
                </div>

                <div class="level3-block-meta">
                    \(escapeHTML(block.metaB))
                </div>

                <div class="level3-block-path">
                    \(escapeHTML(block.folderB))
                </div>

                <div class="level3-block-count">
                    \(block.rows.count) common track(s)
                </div>

            </div>

            <table>

            <thead>
            <tr>
                <th>Song</th>
                <th>Artist</th>
                <th>Album Artist</th>
                <th>Year</th>
                <th>SRate</th>
                <th>Type</th>
                <th>Filename A</th>
                <th>Filename B</th>
            </tr>
            </thead>

            <tbody>
            """

            for row in block.rows {

                html += """
                <tr>

                    <td class="comparison-song-title">
                        \(escapeHTML(row.title))
                    </td>

                    <td>
                        \(escapeHTML(row.artist))
                    </td>

                    <td>
                        \(escapeHTML(row.albumArtist))
                    </td>

                    <td>
                        \(escapeHTML(row.year))
                    </td>

                    <td>
                        \(escapeHTML(row.sampleRate))
                    </td>

                    <td>
                        \(escapeHTML(row.fileType))
                    </td>

                    <td class="comparison-filename">
                        \(escapeHTML(row.filenameA))
                    </td>

                    <td class="comparison-filename">
                        \(escapeHTML(row.filenameB))
                    </td>

                </tr>
                """
            }

            html += """
            </tbody>
            </table>

            </div>
            """
        }

        html += """
        </div>
        """

        return html
    }

    // =============================================================
}
