//
//  TandaLibraryView.swift
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
import AppKit
import UniformTypeIdentifiers




struct TandaSongRow:
    View {

    let index:
        Int

    let song:
        Song

    let status:
        SetlistEntryStatus

    let columns:
        [(String, CGFloat)]

    @EnvironmentObject
    private var settings:
        AppSettings


    var body:
        some View {

        HStack(
            spacing:
                0
        ) {

            ForEach(
                columns,
                id:
                    \.0
            ) { column in

                if column.0 ==
                    "" {

                    statusIndicator(
                        width:
                            column.1
                    )

                } else {

                    value(
                        text(
                            for:
                                column.0
                        ),
                        width:
                            column.1
                    )
                }
            }
        }
        .padding(
            .horizontal,
            8
        )
        .padding(
            .vertical,
            3
        )
    }


    // MARK: - Status Indicator
    //
    // Mirrors LibraryTableView/SetlistView's Status column: red
    // octagon for a file the Library couldn't find on disk at last
    // rescan, blue question mark for a song this Tanda references that
    // isn't in the current Library at all, nothing for a song that
    // resolves cleanly.

    @ViewBuilder
    private func statusIndicator(
        width:
            CGFloat
    ) -> some View {

        Group {

            if status == .fileMissing {

                Image(
                    systemName:
                        "octagon.fill"
                )
                .foregroundStyle(
                    Color.red
                )
                .help(
                    "File not found on disk"
                )

            } else if status == .notInLibrary {

                Image(
                    systemName:
                        "questionmark.circle.fill"
                )
                .foregroundStyle(
                    Color.blue
                )
                .help(
                    "Not found in the current Library — showing saved info"
                )

            } else if status == .staleReference {

                Image(
                    systemName:
                        "exclamationmark.triangle.fill"
                )
                .foregroundStyle(
                    Color.orange
                )
                .help(
                    "The TrackLibrary already found this file at a new location, but this Tanda hasn't been re-linked to it yet — it will fail to play. Run \"Rescan TandaLibrary\" (Tools menu) to fix it."
                )

            } else {

                Color.clear
            }
        }
        .font(
            .system(
                size:
                    8
            )
        )
        .frame(
            width:
                width,
            alignment:
                .leading
        )
    }


    // MARK: - Value For Column
    //
    // Renders values by COLUMN NAME rather than by fixed position, so
    // the row always lines up with the header — no matter what order
    // `columns` is currently in (i.e. whatever order/width the user has
    // Tracks set to via LibraryColumnDefaults.currentColumns()).

    private func text(
        for columnName:
            String
    ) -> String {

        switch columnName {

        case "#":
            return "\(index + 1)"

        case "Title":
            return song.title ?? song.filename

        case "Orchestra":
            return song.resolvedOrchestra(using: settings) ?? ""

        case "Singer":
            return song.resolvedSinger(using: settings) ?? ""

        case "Album":
            return song.album ?? ""

        case "Genre":
            return song.genre ?? ""

        case "Year":
            return yearString(song.year)

        case "Type":
            return song.fileType ?? ""

        case "SRate":
            return sampleRateString(song.sampleRate)

        case "R128 Gain":
            return replayGainString(song.replayGain)

        case "Duration":
            return durationString(song.duration)

        case "Grouping":
            return song.grouping ?? ""

        case "Comment":
            return song.comment ?? ""

        default:
            return ""
        }
    }


    // MARK: - Value

    private func value(
        _ text:
            String,
        width:
            CGFloat
    ) -> some View {

        Text(
            text
        )
        .font(
            .system(
                size:
                    LibraryColumnDefaults.rowFontSize
            )
        )
        .lineLimit(
            1
        )
        .truncationMode(
            .tail
        )
        .frame(
            width:
                width,
            alignment:
                .leading
        )
    }


    // MARK: - Year

    private func yearString(
        _ value:
            Int?
    ) -> String {

        guard
            let value
        else {
            return ""
        }

        return String(
            value
        )
    }


    // MARK: - Sample Rate

    private func sampleRateString(
        _ value:
            Int?
    ) -> String {

        guard
            let value
        else {
            return ""
        }

        return String(
            format:
                "%.1f kHz",
            Double(value) / 1000.0
        )
    }


    // MARK: - Replay Gain

    private func replayGainString(
        _ value:
            Double?
    ) -> String {

        guard
            let value
        else {
            return ""
        }

        return String(
            format:
                "%.1f dB",
            value
        )
    }


    // MARK: - Duration

    private func durationString(
        _ value:
            Int?
    ) -> String {

        guard
            let value
        else {
            return ""
        }

        return String(
            format:
                "%d:%02d",
            value / 60,
            value % 60
        )
    }
}

