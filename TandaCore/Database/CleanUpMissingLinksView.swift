//
//  CleanUpMissingLinksView.swift
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


// MARK: - Clean Up Missing Links
//
// Confirmation sheet for LibraryStore.deleteSongs(ids:) — the one
// place in the app that can remove a Song row from the Library
// entirely. Always operates on the FULL current `missingSongIDs` set
// (not the caller's selection) so its scope is self-evident: "clean up
// everything currently flagged missing", nothing more, nothing
// picked-and-chosen.
//
// Deliberately doesn't touch anything relocatable — a song a rescan
// could still find at a new location isn't "missing" here in the
// first place (missingSongIDs only contains what the last check
// couldn't find AT ALL), so there's no risk of this deleting something
// "Rescan TrackLibrary" would have fixed a moment later.

struct CleanUpMissingLinksView: View {

    let missingSongs: [Song]

    let onCancel: () -> Void
    let onConfirm: () -> Void


    @State
    private var isScanning = true

    @State
    private var affectedSetlistNames: [String] = []

    @State
    private var affectedTandaCount = 0


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            HStack {

                Text(
                    "Clean Up Missing Links"
                )
                .font(.title2)
                .bold()

                Spacer()
            }
            .padding(8)

            Divider()

            Text(
                "These \(missingSongs.count) track(s) weren't found on disk at the last check. This only removes their LINK from the Library's own record — it doesn't touch or delete the actual files. If any of these are on a drive that's just not connected right now, cancel and reconnect it first instead."
            )
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
            .padding(8)


            // =====================================================
            // CROSS-REFERENCE WARNING
            // =====================================================

            if isScanning {

                HStack(spacing: 6) {

                    ProgressView()
                        .controlSize(.small)

                    Text(
                        "Checking saved Setlists and Tandas…"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            } else if !affectedSetlistNames.isEmpty || affectedTandaCount > 0 {

                Label(
                    warningText,
                    systemImage:
                        "exclamationmark.triangle.fill"
                )
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }


            // =====================================================
            // TRACK LIST
            // =====================================================

            ScrollView {

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {

                    ForEach(
                        Array(missingSongs.enumerated()),
                        id: \.offset
                    ) { _, song in

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {

                            Text(
                                song.title ?? song.filename
                            )
                            .font(.system(size: 14))

                            Text(
                                song.path
                            )
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                        .padding(
                            .horizontal, 8
                        )
                        .padding(
                            .vertical, 5
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .background(
                            Color.red.opacity(0.12)
                        )
                        .cornerRadius(6)
                    }
                }
                .padding(8)
            }

            Divider()

            HStack {

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.defaultAction)

                Button(
                    "Remove \(missingSongs.count) Link(s)",
                    role: .destructive
                ) {
                    onConfirm()
                }
            }
            .padding(8)
        }
        .frame(
            minWidth: 480,
            minHeight: 420
        )
        .onAppear {
            scanReferences()
        }
    }


    // MARK: - Warning Text

    private var warningText: String {

        var parts: [String] = []

        if !affectedSetlistNames.isEmpty {

            let preview =
                affectedSetlistNames
                    .prefix(3)
                    .joined(separator: ", ")

            let suffix =
                affectedSetlistNames.count > 3
                ? ", …"
                : ""

            parts.append(
                "\(affectedSetlistNames.count) setlist(s) (\(preview)\(suffix))"
            )
        }

        if affectedTandaCount > 0 {
            parts.append("\(affectedTandaCount) tanda(s)")
        }

        return
            "Also referenced by \(parts.joined(separator: " and ")) — those will show as \"not in library\" afterward."
    }


    // MARK: - Cross-Reference Scan
    //
    // Read-only: loads every saved Setlist (via SetlistMetadataExporter
    // directly, NOT the app's live PlaylistStore, so this never
    // disturbs whatever Setlist the user currently has open) and every
    // saved Tanda (a fresh, throwaway TandaStore — same pattern
    // RescanTandaView already uses), and checks which ones reference
    // any of the ids about to be deleted.

    private func scanReferences() {

        let missingIDs =
            Set(missingSongs.compactMap(\.id))

        // Runs on the MainActor like everything else in this project
        // (PlaylistStore/TandaStore aren't Sendable and are MainActor-
        // isolated) — fine for this size of work (a few dozen Setlist/
        // Tanda files at most), just wrapped in `Task` so `isScanning`
        // still paints before the work starts.
        Task {

            var setlistNames: [String] = []

            if let playlistNames =
                try? PlaylistStore.listPlaylistNamesOnDisk() {

                for name in playlistNames {

                    guard
                        let export =
                            try? SetlistMetadataExporter.load(
                                from:
                                    PlaylistStore.fileURLOnDisk(
                                        forName: name
                                    )
                            )
                    else {
                        continue
                    }

                    let referencesMissing =
                        export.songs.contains {
                            $0.id.map(missingIDs.contains) ?? false
                        }

                    if referencesMissing {
                        setlistNames.append(name)
                    }
                }
            }

            let tandaStore =
                TandaStore()

            let tandaCount =
                tandaStore.tandas.filter { tanda in

                    tanda.songs.contains {
                        $0.id.map(missingIDs.contains) ?? false
                    }

                }.count

            affectedSetlistNames = setlistNames
            affectedTandaCount = tandaCount
            isScanning = false
        }
    }
}
