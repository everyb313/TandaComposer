//
//  RescanHTMLExporter.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 28.08.26.
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

enum RescanHTMLExporter {

    // MARK: - Export

    static func export(
        summary: RescanSummary,
        libraryName: String,
        to url: URL
    ) throws {

        let html =
            render(
                summary: summary,
                libraryName: libraryName
            )

        try html.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }


    // MARK: - Render

    private static func render(
        summary: RescanSummary,
        libraryName: String
    ) -> String {

        var html = ""

        html += """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">

        <title>TandaComposer Rescan Report</title>

        <style>

        body {
            font-family:
                -apple-system,
                BlinkMacSystemFont,
                "SF Pro Text",
                "Helvetica Neue",
                Arial,
                sans-serif;

            margin: 32px;
            color: #222;
            background: #fff;
        }

        h1 {
            font-size: 28px;
            margin-bottom: 6px;
        }

        .subtitle {
            color: #666;
            margin-bottom: 24px;
        }

        .summary {
            display: flex;
            flex-wrap: wrap;
            gap: 20px;
            margin-bottom: 28px;
        }

        .summary-item {
            padding: 12px 18px;
            background: #f3f3f3;
            border-radius: 8px;
        }

        .summary-label {
            display: block;
            font-size: 12px;
            color: #666;
            margin-bottom: 4px;
        }

        .summary-value {
            font-size: 20px;
            font-weight: 600;
        }

        .section {
            margin-bottom: 36px;
        }

        .section-title {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 8px;
        }

        .section-empty {
            color: #999;
            font-size: 13px;
            margin-bottom: 8px;
        }


        table {
            width: 100%;
            border-collapse: collapse;
            table-layout: fixed;
        }

        col.title {
            width: 20%;
        }

        col.artist {
            width: 15%;
        }

        col.albumArtist {
            width: 15%;
        }

        col.path {
            width: 25%;
        }

        col.oldPath {
            width: 25%;
        }

        col.error {
            width: 40%;
        }


        th {
            text-align: left;
            background: #eeeeee;
            padding: 8px;
            border: 1px solid #d0d0d0;
            font-size: 13px;
            vertical-align: top;
        }

        td {
            padding: 8px;
            border: 1px solid #d0d0d0;
            vertical-align: top;
            font-size: 13px;

            overflow-wrap: anywhere;
            word-break: break-word;
        }

        tr:nth-child(even) {
            background: #fafafa;
        }

        .path {
            font-family:
                "SF Mono",
                Menlo,
                Monaco,
                monospace;

            font-size: 11px;
            overflow-wrap: anywhere;
            word-break: break-all;
        }


        /* -------------------------------------------------------
           Section accent colors — mirrors the status-icon colors
           used elsewhere in the app (red = missing, blue = not in
           library territory, orange = attention).
           ------------------------------------------------------- */

        .section-missing .section-title {
            color: #c0392b;
        }

        .section-updated .section-title {
            color: #b8860b;
        }

        .section-relocated .section-title {
            color: #2166a8;
        }

        .section-new .section-title {
            color: #2e7d32;
        }

        .section-failed .section-title {
            color: #c0392b;
        }


        @media print {

            body {
                margin: 12px;
            }

            .section {
                break-inside: avoid;
            }

            table {
                break-inside: auto;
            }

            tr {
                break-inside: avoid;
            }
        }

        </style>
        </head>

        <body>

        <h1>TandaComposer Rescan Report</h1>

        <div class="subtitle">

            Library
            <strong>\(escapeHTML(libraryName))</strong>

        </div>

        <div class="summary">

            \(summaryItem("Unchanged", summary.unchangedCount))
            \(summaryItem("Updated", summary.updatedCount))
            \(summaryItem("Missing", summary.missingCount))
            \(summaryItem("Relocated", summary.relocatedCount))
            \(summaryItem("Newly Imported", summary.newlyImportedCount))
            \(summaryItem("Failed", summary.failedReads.count))

        </div>
        """


        html += songSection(
            title: "Missing",
            cssClass: "section-missing",
            songs: summary.missingSongs
        )

        html += songSection(
            title: "Updated",
            cssClass: "section-updated",
            songs: summary.updatedSongs
        )

        html += relocatedSection(
            summary.relocatedTracks
        )

        html += songSection(
            title: "Newly Imported",
            cssClass: "section-new",
            songs: summary.newlyImportedSongs
        )

        html += failedSection(
            summary.failedReads
        )


        html += """
        </body>
        </html>
        """

        return html
    }


    // MARK: - Summary Item

    private static func summaryItem(
        _ label: String,
        _ value: Int
    ) -> String {

        """
        <div class="summary-item">
            <span class="summary-label">
                \(escapeHTML(label))
            </span>

            <span class="summary-value">
                \(value)
            </span>
        </div>
        """
    }


    // MARK: - Plain Song Section (Missing / Updated / Newly Imported)

    private static func songSection(
        title: String,
        cssClass: String,
        songs: [Song]
    ) -> String {

        var html = """
        <div class="section \(cssClass)">

        <div class="section-title">
            \(escapeHTML(title)) (\(songs.count))
        </div>
        """

        guard
            !songs.isEmpty
        else {

            html += """
            <div class="section-empty">
                None
            </div>
            </div>
            """

            return html
        }

        html += """
        <table>

        <colgroup>
            <col class="title">
            <col class="artist">
            <col class="albumArtist">
            <col class="path">
        </colgroup>

        <thead>
        <tr>
            <th>Title</th>
            <th>Artist</th>
            <th>Album Artist</th>
            <th>Path</th>
        </tr>
        </thead>

        <tbody>
        """

        for song in songs {

            html += songRow(song)
        }

        html += """
        </tbody>
        </table>
        </div>
        """

        return html
    }


    private static func songRow(
        _ song: Song
    ) -> String {

        let title =
            song.title ??
            song.filename

        let artist =
            song.artist ??
            "—"

        let albumArtist =
            song.albumArtist ??
            "—"

        return """
        <tr>

            <td>
                \(escapeHTML(title))
            </td>

            <td>
                \(escapeHTML(artist))
            </td>

            <td>
                \(escapeHTML(albumArtist))
            </td>

            <td class="path">
                \(escapeHTML(song.path))
            </td>

        </tr>
        """
    }


    // MARK: - Relocated Section

    private static func relocatedSection(
        _ tracks: [RelocatedTrack]
    ) -> String {

        var html = """
        <div class="section section-relocated">

        <div class="section-title">
            Relocated (\(tracks.count))
        </div>
        """

        guard
            !tracks.isEmpty
        else {

            html += """
            <div class="section-empty">
                None
            </div>
            </div>
            """

            return html
        }

        html += """
        <table>

        <colgroup>
            <col class="title">
            <col class="oldPath">
            <col class="path">
        </colgroup>

        <thead>
        <tr>
            <th>Title</th>
            <th>Old Path</th>
            <th>New Path</th>
        </tr>
        </thead>

        <tbody>
        """

        for track in tracks {

            let title =
                track.song.title ??
                track.song.filename

            html += """
            <tr>

                <td>
                    \(escapeHTML(title))
                </td>

                <td class="path">
                    \(escapeHTML(track.oldPath))
                </td>

                <td class="path">
                    \(escapeHTML(track.song.path))
                </td>

            </tr>
            """
        }

        html += """
        </tbody>
        </table>
        </div>
        """

        return html
    }


    // MARK: - Failed Section

    private static func failedSection(
        _ failures: [(url: URL, error: Error)]
    ) -> String {

        var html = """
        <div class="section section-failed">

        <div class="section-title">
            Failed To Read (\(failures.count))
        </div>
        """

        guard
            !failures.isEmpty
        else {

            html += """
            <div class="section-empty">
                None
            </div>
            </div>
            """

            return html
        }

        html += """
        <table>

        <colgroup>
            <col class="path">
            <col class="error">
        </colgroup>

        <thead>
        <tr>
            <th>Path</th>
            <th>Error</th>
        </tr>
        </thead>

        <tbody>
        """

        for failure in failures {

            html += """
            <tr>

                <td class="path">
                    \(escapeHTML(failure.url.path))
                </td>

                <td>
                    \(escapeHTML(failure.error.localizedDescription))
                </td>

            </tr>
            """
        }

        html += """
        </tbody>
        </table>
        </div>
        """

        return html
    }


    // MARK: - HTML Escaping

    private static func escapeHTML(
        _ value: String
    ) -> String {

        value
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
