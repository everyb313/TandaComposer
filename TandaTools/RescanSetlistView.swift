//
//  RescanSetlistView.swift
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

struct RescanSetlistView: View {

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @EnvironmentObject
    private var playlistStore: PlaylistStore

    /// The pending preview from `previewRescan` — nil before the first
    /// scan, or once its fixes have been applied/discarded.
    @State
    private var pendingFixes: [PlaylistStore.RescanFix]?

    /// Set once the last preview's fixes have been written (or there
    /// was nothing to write). Distinguishes "still just a preview"
    /// from "already applied" for the same `pendingFixes` value.
    @State
    private var isApplied = false

    @State
    private var saveErrorMessage: String?

    // MARK: - Status Count
    //
    // If a scan finds nothing to re-link but tracks are still showing
    // a dot, that's not a contradiction — previewRescan only re-links
    // tracks the TrackLibrary already knows about at a new location
    // (see the note above). Used to make that explicit instead of
    // just saying "no broken references found" when there clearly
    // still are some.
    private var stillFlaggedCount: Int {
        playlistStore.entries.filter { $0.status != .resolved }.count
    }

    /// Among the still-flagged entries, how many are NOT covered by
    /// the current `pendingFixes` — i.e. genuinely stuck right now
    /// (same id, TrackLibrary still doesn't have a better location for
    /// them) rather than something this rescan can do anything about.
    /// Computed against `pendingFixes`' entryIDs (frozen at preview
    /// time), so this reads the same before AND after Apply — used so
    /// "N fixed" never implies more than what actually changed when
    /// only some of the Setlist's broken entries were fixable.
    private var unfixableFlaggedCount: Int {

        guard let pendingFixes else {
            return stillFlaggedCount
        }

        let fixedIDs = Set(
            pendingFixes.map(\.entryID)
        )

        return playlistStore.entries.filter {
            $0.status != .resolved &&
            !fixedIDs.contains($0.id)
        }.count
    }


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            // =====================================================
            // HEADER — title left, action button(s) right, same
            // layout as RescanLibraryView so all three Rescan windows
            // look and behave the same way.
            // =====================================================

            HStack {

                Text(
                    "Rescan Setlist"
                )
                .font(.title2)
                .bold()

                Spacer()

                if let pendingFixes, !isApplied, !pendingFixes.isEmpty {

                    Button(role: .cancel) {

                        discardPendingFixes()

                    } label: {

                        Label(
                            "Discard",
                            systemImage:
                                "xmark"
                        )
                    }

                    Button {

                        applyPendingFixes()

                    } label: {

                        Label(
                            "Apply Fixes",
                            systemImage:
                                "checkmark.circle"
                        )
                    }

                } else {

                    Button {

                        runRescan()

                    } label: {

                        Label(
                            "Rescan Setlist",
                            systemImage:
                                "arrow.clockwise"
                        )
                    }
                }
            }
            .padding(8)

            Divider()

            Text(
                "Checks the current Setlist (\"\(playlistStore.name)\") against the TrackLibrary as currently loaded, and shows what would be re-linked by their Library ID. This does NOT scan disk itself — if a file moved and the TrackLibrary hasn't picked that up yet, run \"Rescan TrackLibrary\" first."
            )
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
            .padding(8)


            // =====================================================
            // RESULTS
            // =====================================================

            if let pendingFixes {

                if pendingFixes.isEmpty {

                    VStack(
                        spacing: 6
                    ) {

                        Spacer()

                        if stillFlaggedCount > 0 {

                            Label(
                                "Nothing to re-link, but \(stillFlaggedCount) track(s) are still missing or not in library.",
                                systemImage:
                                    "exclamationmark.circle.fill"
                            )
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)

                            Text(
                                "This only re-links tracks the TrackLibrary already found at a new location. Run \"Rescan TrackLibrary\" first, then try this again."
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                            .padding(.horizontal, 24)

                        } else {

                            Label(
                                "No broken references found.",
                                systemImage:
                                    "checkmark.circle.fill"
                            )
                            .font(.system(size: 14))
                            .foregroundStyle(Color.green)
                        }

                        Spacer()
                    }

                } else {

                    Label(
                        isApplied
                        ? "\(pendingFixes.count) reference(s) fixed and saved."
                        : "\(pendingFixes.count) reference(s) found — click \"Apply Fixes\" to fix and save them.",
                        systemImage:
                            isApplied
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(
                        isApplied
                        ? Color.green
                        : Color.orange
                    )
                    .padding(.horizontal, 8)

                    if unfixableFlaggedCount > 0 {

                        Text(
                            "\(unfixableFlaggedCount) other track(s) are still missing or not in library — the TrackLibrary hasn't found a location for them yet, so this rescan can't do anything about those."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                        .padding(.horizontal, 8)
                    }

                    ScrollView {

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {

                            ForEach(
                                Array(pendingFixes.enumerated()),
                                id: \.offset
                            ) { _, fix in

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {

                                    Text(
                                        fix.song.title ?? fix.song.filename
                                    )
                                    .font(.system(size: 14))

                                    Text(
                                        "From: \(fix.oldPath)"
                                    )
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                    Text(
                                        "To: \(fix.song.path)"
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
                                    Color.blue.opacity(0.12)
                                )
                                .cornerRadius(6)
                            }
                        }
                        .padding(8)
                    }
                }

            } else {

                VStack {

                    Spacer()

                    Text(
                        "Click \"Rescan Setlist\" to check its tracks against the current Library."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
        .frame(
            minWidth: 480,
            minHeight: 320
        )
        .alert(
            "Couldn't Save Setlist",
            isPresented: .constant(saveErrorMessage != nil),
            presenting: saveErrorMessage
        ) { _ in

            Button("OK") {
                saveErrorMessage = nil
            }

        } message: { message in

            Text(
                "The fixed reference(s) were applied in memory but the Setlist couldn't be saved: \(message). Use \"Save Set\" to try again."
            )
        }
    }


    // MARK: - Actions

    /// Step 1 — scan only. Read-only: computes what a fix WOULD do,
    /// doesn't touch the Setlist or its saved file.
    private func runRescan() {

        pendingFixes =
            playlistStore.previewRescan(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: libraryStore.missingSongIDs
            )

        isApplied = false
    }

    /// Step 2 — user confirmation happens implicitly by them clicking
    /// this button (only shown once there's something to fix); this
    /// is where the fixes are actually written.
    private func applyPendingFixes() {

        guard let pendingFixes else {
            return
        }

        let saved =
            playlistStore.applyRescan(pendingFixes)

        // Also re-run the normal resolve pass, so every entry — not
        // just the ones fixed above — ends up fully up to date
        // against the current Library.
        playlistStore.resolveAgainstLibrary(
            byID: libraryStore.songsByID,
            byPath: libraryStore.songsByNormalizedPath,
            missingSongIDs: libraryStore.missingSongIDs
        )

        isApplied = true

        if !saved {
            saveErrorMessage =
                "the Setlist may not have a saved name yet, or its file couldn't be written"
        }
    }

    private func discardPendingFixes() {

        pendingFixes = nil
        isApplied = false
    }
}
