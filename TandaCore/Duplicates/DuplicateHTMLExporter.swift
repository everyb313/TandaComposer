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
    // MARK: - Shared Folder Comparison
    // =============================================================

    private struct Level3SongRow {

        let title: String
        let artist: String
        let albumArtist: String
        let year: String
        let sampleRate: String
        let fileType: String
        let filenameA: String
        let filenameB: String
    }

    private struct Level3Block {

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

    private struct FolderPairKey: Hashable {

        let folderA: String
        let folderB: String
    }

    private static func renderFolderComparison(
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
    // MARK: - Build Folder Blocks
    // =============================================================

    private static func trackCount(
        in folder: String,
        songs: [Song]
    ) -> Int {

        let prefix =
            folder.hasSuffix("/")
            ? folder
            : folder + "/"

        return songs.reduce(into: 0) { count, song in
            if song.path == folder || song.path.hasPrefix(prefix) {
                count += 1
            }
        }
    }

    private static func makeFolderBlocks(
        clusters: [DuplicateCluster],
        librarySongs: [Song]
    ) -> [Level3Block] {

        var rowsByPair:
            [FolderPairKey: [Level3SongRow]] =
                [:]

        var sampleRatesA:
            [FolderPairKey: Set<String>] =
                [:]

        var sampleRatesB:
            [FolderPairKey: Set<String>] =
                [:]

        var fileTypesA:
            [FolderPairKey: Set<String>] =
                [:]

        var fileTypesB:
            [FolderPairKey: Set<String>] =
                [:]

        for cluster in clusters {

            let folders =
                comparisonFolders(
                    in: cluster
                )

            guard folders.count == 2 else {
                continue
            }

            let folderA =
                folders[0]

            let folderB =
                folders[1]

            let songsA =
                cluster.songs.filter {
                    parentFolder(
                        of: $0.path
                    ) == folderA
                }

            let songsB =
                cluster.songs.filter {
                    parentFolder(
                        of: $0.path
                    ) == folderB
                }

            guard
                !songsA.isEmpty,
                !songsB.isEmpty
            else {
                continue
            }

            let key =
                FolderPairKey(
                    folderA: folderA,
                    folderB: folderB
                )

            sampleRatesA[key, default: []]
                .formUnion(
                    songsA.map {
                        sampleRateText(
                            $0.sampleRate
                        )
                    }
                )

            sampleRatesB[key, default: []]
                .formUnion(
                    songsB.map {
                        sampleRateText(
                            $0.sampleRate
                        )
                    }
                )

            fileTypesA[key, default: []]
                .formUnion(
                    songsA.map {
                        $0.fileType ?? "—"
                    }
                )

            fileTypesB[key, default: []]
                .formUnion(
                    songsB.map {
                        $0.fileType ?? "—"
                    }
                )

            for (songA, songB) in zip(
                songsA,
                songsB
            ) {

                let row =
                    Level3SongRow(
                        title:
                            songA.title
                            ?? songA.filename,

                        artist:
                            combinedField(
                                songA.artist,
                                songB.artist
                            ),

                        albumArtist:
                            combinedField(
                                songA.albumArtist,
                                songB.albumArtist
                            ),

                        year:
                            combinedField(
                                songA.year.map(
                                    String.init
                                ),
                                songB.year.map(
                                    String.init
                                )
                            ),

                        sampleRate:
                            combinedField(
                                sampleRateText(
                                    songA.sampleRate
                                ),
                                sampleRateText(
                                    songB.sampleRate
                                )
                            ),

                        fileType:
                            combinedField(
                                songA.fileType,
                                songB.fileType
                            ),

                        filenameA:
                            songA.filename,

                        filenameB:
                            songB.filename
                    )

                rowsByPair[key, default: []]
                    .append(row)
            }
        }

        let sortedPairs =
            rowsByPair.sorted {
                lhs,
                rhs in

                if lhs.value.count !=
                    rhs.value.count {

                    return
                        lhs.value.count
                        >
                        rhs.value.count
                }

                let folderComparison =
                    lhs.key.folderA.localizedCaseInsensitiveCompare(
                        rhs.key.folderA
                    )

                if folderComparison !=
                    .orderedSame {

                    return
                        folderComparison
                        ==
                        .orderedAscending
                }

                return
                    lhs.key.folderB.localizedCaseInsensitiveCompare(
                        rhs.key.folderB
                    )
                    ==
                    .orderedAscending
            }

        return
            sortedPairs.enumerated().map {
                index,
                entry in

                let key =
                    entry.key

                let sortedRows =
                    entry.value.sorted {
                        lhs,
                        rhs in

                        lhs.title.localizedCaseInsensitiveCompare(
                            rhs.title
                        )
                        ==
                        .orderedAscending
                    }

                return Level3Block(
                    id:
                        "pair-\(index)",

                    folderA:
                        key.folderA,

                    folderB:
                        key.folderB,

                    trackCountA:
                        trackCount(in: key.folderA, songs: librarySongs),

                    trackCountB:
                        trackCount(in: key.folderB, songs: librarySongs),

                    folderNameA:
                        folderBasename(
                            key.folderA
                        ),

                    folderNameB:
                        folderBasename(
                            key.folderB
                        ),

                    metaA:
                        folderMeta(
                            sampleRates:
                                sampleRatesA[key]
                                ?? [],

                            fileTypes:
                                fileTypesA[key]
                                ?? []
                        ),

                    metaB:
                        folderMeta(
                            sampleRates:
                                sampleRatesB[key]
                                ?? [],

                            fileTypes:
                                fileTypesB[key]
                                ?? []
                        ),

                    rows:
                        sortedRows
                )
            }
    }

    // =============================================================
    // MARK: - Folder Basename
    // =============================================================

    private static func folderBasename(
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

    private static func folderMeta(
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

    private static func combinedField(
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

    private static func comparisonFolders(
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

    private static func parentFolder(
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
    // MARK: - Source Highlighting
    // =============================================================

    private static func sourceClassForPath(
        _ path: String
    ) -> String {

        let lowercased =
            path.lowercased()

        if lowercased.contains(
            "tango time travel"
        )
        || lowercased.contains(
            "tangotime travel"
        )
        || lowercased.contains(
            "tango_time_travel"
        ) {

            return "source-ttt"
        }

        if lowercased.contains(
            "tango tunes"
        )
        || lowercased.contains(
            "tangotunes"
        )
        || containsStandaloneTT(
            lowercased
        ) {

            return "source-tt"
        }

        return ""
    }

    // =============================================================
    // MARK: - Standalone TT Detection
    // =============================================================

    private static func containsStandaloneTT(
        _ text: String
    ) -> Bool {

        let characters =
            Array(text)

        guard characters.count >= 2 else {
            return false
        }

        for index in
            0..<(characters.count - 1) {

            guard
                characters[index] == "t",
                characters[index + 1] == "t"
            else {
                continue
            }

            let beforeIsBoundary:
                Bool

            if index == 0 {

                beforeIsBoundary =
                    true

            } else {

                beforeIsBoundary =
                    !characters[index - 1].isLetter
                    &&
                    !characters[index - 1].isNumber
            }

            let afterIndex =
                index + 2

            let afterIsBoundary:
                Bool

            if afterIndex >=
                characters.count {

                afterIsBoundary =
                    true

            } else {

                afterIsBoundary =
                    !characters[afterIndex].isLetter
                    &&
                    !characters[afterIndex].isNumber
            }

            if
                beforeIsBoundary
                &&
                afterIsBoundary {

                return true
            }
        }

        return false
    }

    // =============================================================
    // MARK: - Sample Rate
    // =============================================================

    private static func sampleRateText(
        _ sampleRate: Int?
    ) -> String {

        guard
            let sampleRate
        else {
            return ""
        }

        if sampleRate % 1000 == 0 {

            return
                "\(sampleRate / 1000)k"
        }

        let value =
            Double(sampleRate)
            /
            1000.0

        return
            String(
                format:
                    "%.1fk",
                value
            )
    }

    // =============================================================
    // MARK: - HTML Escape
    // =============================================================

    private static func escapeHTML(
        _ string: String
    ) -> String {

        string
            .replacingOccurrences(
                of: "&",
                with: "&amp;"
            )
            .replacingOccurrences(
                of: "<",
                with: "&lt;"
            )
            .replacingOccurrences(
                of: ">",
                with: "&gt;"
            )
            .replacingOccurrences(
                of: "\"",
                with: "&quot;"
            )
            .replacingOccurrences(
                of: "'",
                with: "&#39;"
            )
    }
}
