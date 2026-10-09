//
//  DuplicateHTMLExporter.swift
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

enum DuplicateHTMLExporter {

    // Split by responsibility into extensions:
    //   +FolderComparison.swift  folder-comparison section rendering
    //   +FolderBlocks.swift      building folder blocks from clusters
    //   +FolderPaths.swift       folder basename / metadata / parent helpers
    //   +Formatting.swift        source highlighting, TT detection, sample rate, HTML escape


    // MARK: - Export

    static func export(
        clusters: [DuplicateCluster],
        level: DuplicateLevel,
        libraryName: String,
        librarySongs: [Song],
        to url: URL
    ) throws {

        let html = render(
            clusters: clusters,
            level: level,
            libraryName: libraryName,
            librarySongs: librarySongs
        )

        try html.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Main Render

    private static func render(
        clusters: [DuplicateCluster],
        level: DuplicateLevel,
        libraryName: String,
        librarySongs: [Song]
    ) -> String {

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">

        <title>\(escapeHTML(libraryName)) - Duplicate Report Level \(level.rawValue)</title>

        <style>

        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text",
                         "Helvetica Neue", Arial, sans-serif;
            margin: 0;
            padding: 30px;
            background: #f5f5f7;
            color: #1d1d1f;
        }

        h1 {
            margin-top: 0;
            margin-bottom: 8px;
            font-size: 28px;
        }

        h2 {
            margin-top: 40px;
            margin-bottom: 15px;
            font-size: 22px;
        }

        .subtitle {
            color: #6e6e73;
            margin-bottom: 30px;
        }

        .cluster {
            margin-bottom: 35px;
            background: white;
            border-radius: 12px;
            padding: 18px;
            box-shadow: 0 1px 4px rgba(0,0,0,0.08);
        }

        .cluster-title {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 15px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            background: white;
        }

        th {
            text-align: left;
            background: #e9e9ed;
            font-weight: 600;
            padding: 9px 10px;
            border-bottom: 1px solid #d2d2d7;
            white-space: nowrap;
        }

        td {
            padding: 8px 10px;
            border-bottom: 1px solid #e5e5e7;
            vertical-align: top;
        }

        tr:last-child td {
            border-bottom: none;
        }

        .path {
            font-family: "SF Mono", Menlo, Monaco, monospace;
            font-size: 11px;
            color: #555;
            word-break: break-all;
        }

        .source-ttt {
            color: #d00000;
            font-weight: 600;
        }

        .source-tt {
            color: #e87500;
            font-weight: 600;
        }

        .folder-comparison {
            margin-top: 50px;
        }

        .folder-comparison table {
            table-layout: fixed;
        }

        .folder-path {
            font-family: "SF Mono", Menlo, Monaco, monospace;
            font-size: 11px;
            word-break: break-all;
            vertical-align: top;
        }

        .comparison-song-title {
            font-weight: 500;
        }

        .comparison-filename {
            font-family: "SF Mono", Menlo, Monaco, monospace;
            font-size: 11px;
            word-break: break-all;
        }

        .empty {
            color: #6e6e73;
            font-style: italic;
            padding: 15px 0;
        }

        /* -------------------------------------------------------
           Folder comparison summary
           ------------------------------------------------------- */

        .level3-summary {
            margin-top: 10px;
            margin-bottom: 40px;
        }

        .level3-summary table {
            table-layout: fixed;
        }

        .level3-summary th:nth-child(1),
        .level3-summary td:nth-child(1) {
            width: 40%;
        }

        .level3-summary th:nth-child(2),
        .level3-summary td:nth-child(2) {
            width: 40%;
        }

        .level3-summary th:nth-child(3),
        .level3-summary td:nth-child(3) {
            width: 20%;
            text-align: right;
        }

        .level3-summary td:nth-child(3) {
            font-weight: 600;
        }

        .level3-summary a {
            color: #0066cc;
            text-decoration: none;
        }

        .level3-summary a:hover {
            text-decoration: underline;
        }

        /* -------------------------------------------------------
           Shared Level 3 / Level 4 folder block
           ------------------------------------------------------- */

        .level3-block {
            margin-bottom: 28px;
            background: white;
            border: 1px solid #d2d2d7;
            border-radius: 12px;
            padding: 18px;
            scroll-margin-top: 20px;
        }

        .level3-block-header {
            display: grid;
            grid-template-columns:
                max-content
                minmax(140px, auto)
                minmax(150px, auto)
                1fr;
            column-gap: 20px;
            row-gap: 6px;
            align-items: baseline;
            margin-bottom: 16px;
        }

        .level3-block-label {
            color: #6e6e73;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.02em;
        }

        .level3-block-name {
            font-size: 19px;
            font-weight: 700;
            max-width: 50ch;
            overflow-wrap: anywhere;
            word-break: normal;
            white-space: normal;
        }

        .level3-block-meta {
            font-size: 12px;
            color: #444;
            white-space: nowrap;
        }

        .level3-block-path {
            font-family: "SF Mono", Menlo, Monaco, monospace;
            font-size: 11px;
            color: #6e6e73;
            word-break: break-all;
        }

        .level3-block-count {
            grid-column: 1 / -1;
            margin-top: 2px;
            font-weight: 600;
        }

        .level3-block table {
            table-layout: fixed;
        }

        /* Song */
        .level3-block th:nth-child(1),
        .level3-block td:nth-child(1) {
            width: 24%;
        }

        /* Artist */
        .level3-block th:nth-child(2),
        .level3-block td:nth-child(2) {
            width: 12%;
        }

        /* Album Artist */
        .level3-block th:nth-child(3),
        .level3-block td:nth-child(3) {
            width: 12%;
        }

        /* Year */
        .level3-block th:nth-child(4),
        .level3-block td:nth-child(4) {
            width: 8%;
        }

        /* SRate */
        .level3-block th:nth-child(5),
        .level3-block td:nth-child(5) {
            width: 6%;
            white-space: nowrap;
        }

        /* Type */
        .level3-block th:nth-child(6),
        .level3-block td:nth-child(6) {
            width: 6%;
            white-space: nowrap;
        }

        /* Filename A */
        .level3-block th:nth-child(7),
        .level3-block td:nth-child(7) {
            width: 16%;
        }

        /* Filename B */
        .level3-block th:nth-child(8),
        .level3-block td:nth-child(8) {
            width: 16%;
        }

        </style>
        </head>

        <body>

        <h1>Duplicate Report</h1>

        <div class="subtitle">
            Library:
            <strong>\(escapeHTML(libraryName))</strong>
            &nbsp;·&nbsp;
            Comparison Level:
            <strong>\(escapeHTML(level.title))</strong>
            &nbsp;·&nbsp;
            Clusters:
            <strong>\(clusters.count)</strong>
        </div>
        """

        // MARK: Duplicate Clusters

        for (index, cluster) in clusters.enumerated() {

            html += """
            <div class="cluster">

            <div class="cluster-title">
                Cluster \(index + 1)
            </div>

            <table>
            <thead>
            <tr>
                <th>Song</th>
                <th>Artist</th>
                <th>Album Artist</th>
                <th>Grouping</th>
                <th>Year</th>
                <th>Album</th>
                <th>Type</th>
                <th>SRate</th>
                <th>Path</th>
            </tr>
            </thead>

            <tbody>
            """

            for song in cluster.songs {

                let sourceClass =
                    sourceClassForPath(song.path)

                html += """
                <tr>
                    <td>\(escapeHTML(song.title ?? song.filename))</td>
                    <td>\(escapeHTML(song.artist ?? ""))</td>
                    <td>\(escapeHTML(song.albumArtist ?? ""))</td>
                    <td>\(escapeHTML(song.grouping ?? ""))</td>
                    <td>\(escapeHTML(song.year.map(String.init) ?? ""))</td>
                    <td>\(escapeHTML(song.album ?? ""))</td>
                    <td>\(escapeHTML(song.fileType ?? ""))</td>
                    <td>\(escapeHTML(sampleRateText(song.sampleRate)))</td>
                    <td class="path \(sourceClass)">\(escapeHTML(song.path))</td>
                </tr>
                """
            }

            html += """
            </tbody>
            </table>

            </div>
            """
        }

        // MARK: Folder Comparison

        if level.rawValue == 3 || level.rawValue == 4 {

            html +=
                renderFolderComparison(
                    clusters: clusters,
                    level: level,
                    librarySongs: librarySongs
                )
        }

        html += """
        </body>
        </html>
        """

        return html
    }

    // =============================================================
}
