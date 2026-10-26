//
//  SameTitleBlock.swift
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

import SwiftUI
import AppKit

/// One title of the "Same Title" window, drawn like a Tanda block of the
/// TandaLibrary: header with title and track count, column header, rows
/// (`TandaSongRow`), thin rounded border.
struct SameTitleBlock: View {

    let group: SameTitleGroup
    let missingSongIDs: Set<Int64>
    let setlistPaths: Set<String>
    let selection: SameTitleSelection
    let onClick: (Song) -> Void

    @EnvironmentObject
    private var settings: AppSettings

    /// Two small markers: selected track of the TrackLibrary, and
    /// "already in the Setlist".
    private static let markerColumnWidth: CGFloat = 40

    private var columns: [(String, CGFloat)] {

        [("", LibraryColumnDefaults.statusColumnWidth)]
        + LibraryColumnDefaults.currentColumns()
    }

    private func status(for song: Song) -> SetlistEntryStatus {

        if let id = song.id, missingSongIDs.contains(id) {
            return .fileMissing
        }

        return .resolved
    }

    private func isAnchor(_ song: Song) -> Bool {

        group.anchors.contains { $0.normalizedPath == song.normalizedPath }
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            // =====================================================
            // HEADER
            // =====================================================

            HStack {

                Text(group.title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("\(group.songs.count) tracks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if group.otherCount == 0 {

                    Text("No other track with this title")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // =====================================================
            // COLUMN HEADER
            // =====================================================

            HStack(spacing: 0) {

                Color.clear
                    .frame(width: Self.markerColumnWidth)

                ForEach(columns, id: \.0) { column in

                    Text(
                        LibraryColumnDefaults.headerTitle(
                            for: column.0,
                            settings: settings
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: column.1, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)

            Divider()

            // =====================================================
            // TRACKS
            // =====================================================

            ForEach(
                Array(group.songs.enumerated()),
                id: \.element.normalizedPath
            ) { index, song in

                HStack(spacing: 0) {

                    markers(for: song)
                        .padding(.leading, 8)
                        .frame(
                            width: Self.markerColumnWidth,
                            alignment: .leading
                        )

                    TandaSongRow(
                        index: index,
                        song: song,
                        status: status(for: song),
                        columns: columns
                    )
                }
                .background(
                    selection.contains(song.normalizedPath)
                        ? Color.accentColor.opacity(0.25)
                        : Color.clear
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onClick(song)
                }

                if index < group.songs.count - 1 {

                    Divider()
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Markers

    @ViewBuilder
    private func markers(for song: Song) -> some View {

        HStack(spacing: 4) {

            if isAnchor(song) {

                Image(systemName: "smallcircle.filled.circle")
                    .foregroundStyle(Color.accentColor)
                    .help("Selected in the TrackLibrary")

            } else {

                Color.clear
                    .frame(width: 10)
            }

            if setlistPaths.contains(song.normalizedPath) {

                Image(systemName: "music.note.list")
                    .foregroundStyle(.secondary)
                    .help("Already in the Setlist")
            }
        }
        .font(.system(size: 10))
    }
}
