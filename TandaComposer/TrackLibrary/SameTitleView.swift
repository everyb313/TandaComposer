//
//  SameTitleView.swift
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

// =====================================================================
// SAME TITLE
//
// Opened by the "?" button of the TrackLibrary header. Lists, per title
// of the selected tracks, every track of the TrackLibrary that carries
// the same title, in blocks styled like the Tandas of the TandaLibrary.
//
// Rows can be selected (click, Command-click, Shift-click). The
// selection belongs to this window only; it prepares "Add to Setlist".
// =====================================================================

struct SameTitleView: View {

    @EnvironmentObject
    private var session: SameTitleSession

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @EnvironmentObject
    private var setlistStore: SetlistStore

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            header

            Divider()

            if session.result.isEmpty {

                emptyState

            } else {

                ScrollView([.vertical, .horizontal]) {

                    VStack(alignment: .leading, spacing: 12) {

                        ForEach(session.result.groups) { group in

                            SameTitleBlock(
                                group: group,
                                missingSongIDs: libraryStore.missingSongIDs,
                                setlistPaths: setlistPaths,
                                selection: session.selection,
                                onClick: { song in
                                    let flags = NSEvent.modifierFlags

                                    session.click(
                                        on: song,
                                        command: flags.contains(.command),
                                        shift: flags.contains(.shift)
                                    )
                                }
                            )
                        }

                        notes
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 280)
    }

    // MARK: - Pieces

    private var setlistPaths: Set<String> {

        Set(setlistStore.entries.map { $0.song.normalizedPath })
    }

    private var header: some View {

        HStack {

            Text("Same Title")
                .font(.title3)
                .fontWeight(.semibold)

            if !session.libraryName.isEmpty {

                Text("Library: " + session.libraryName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !session.selection.isEmpty {

                Text("\(session.selection.count) selected")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {

        VStack {

            Spacer()

            Text("Select a track in the Track Library and click ? to see the tracks with the same title.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var notes: some View {

        if session.result.omittedTitleCount > 0 {

            Text(
                "and \(session.result.omittedTitleCount) more titles. "
                + "Select fewer tracks to see them."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if !session.result.untitled.isEmpty {

            Text(
                "\(session.result.untitled.count) selected track(s) have no "
                + "title and cannot be searched."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
