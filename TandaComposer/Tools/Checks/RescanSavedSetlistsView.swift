//
//  RescanSavedSetlistsView.swift
//  TandaComposer
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

struct RescanSavedSetlistsView: View {

    @EnvironmentObject
    private var libraryStore: LibraryStore

    /// The pending preview from `previewRescan` — nil before the
    /// first scan, or once its fixes have been applied/discarded.
    @State
    private var pendingFixes: [SavedSetlistRescanFix]?

    /// Set once the last preview's fixes have been written (or there
    /// was nothing to write).
    @State
    private var isApplied = false

    @State
    private var lastSummary: SavedSetlistRescanSummary?


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            // =====================================================
            // HEADER — title left, action button(s) right, same
            // layout as RescanTandaView/RescanSetlistView.
            // =====================================================

            HStack {

                Text(
                    "Rescan Saved Setlists"
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
                    .disabled(
                        libraryStore.isLocked
                    )
                    .help(
                        libraryStore.isLocked
                        ? "Unlock the Library to apply these fixes"
                        : "Re-link Setlist references that moved"
                    )

                } else {

                    Button {

                        runRescan()

                    } label: {

                        Label(
                            "Rescan Saved Setlists",
                            systemImage:
                                "arrow.clockwise"
                        )
                    }
                }
            }
            .padding(8)

            Divider()

            Text(
                "Checks every SAVED Setlist file against the TrackLibrary as currently loaded: rewrites tracks whose stored path has drifted (matched by Library ID, or by file path for older entries saved without one), and reports — without changing anything — tracks that matched but whose file the Library currently can't find. This does NOT scan disk itself: if a file moved and the TrackLibrary hasn't picked that up yet, run \"Rescan TrackLibrary\" first. The currently open Set (if any) still needs \"Rescan Setlist\" separately."
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

                        Label(
                            "No broken references found.",
                            systemImage:
                                "checkmark.circle.fill"
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(Color.green)

                        Spacer()
                    }

                } else {

                    let totalFixed =
                        pendingFixes.reduce(0) { $0 + $1.fixedSongCount }

                    let totalMissing =
                        pendingFixes.reduce(0) { $0 + $1.missingSongTitles.count }

                    Label(
                        isApplied
                        ? "\(totalFixed) reference(s) fixed across \(pendingFixes.count) Setlist(s)."
                        : "\(totalFixed) reference(s) found across \(pendingFixes.count) Setlist(s) — click \"Apply Fixes\" to fix and save them.",
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

                    if totalMissing > 0 {

                        // Informational only — these aren't written
                        // anywhere (there's no status field in a
                        // saved Setlist file to update), just
                        // surfaced so the user knows the track's file
                        // is currently missing in the Library, same
                        // as `.fileMissing` would show for the live
                        // Set.
                        Text(
                            "\(totalMissing) track(s) matched but currently missing in the Library (file not found) — not fixable here, listed for information only."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 8)
                    }

                    if let lastSummary, !lastSummary.failedWrites.isEmpty {

                        Text(
                            "\(lastSummary.failedWrites.count) Setlist file(s) couldn't be updated."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red)
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

                                let writeFailed =
                                    lastSummary?.failedWrites.contains {
                                        $0.url == fix.url
                                    } ?? false

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {

                                    Text(
                                        fix.fixedSongCount > 0
                                        ? "\(fix.name) (\(fix.fixedSongCount) track(s) fixed)"
                                        : "\(fix.name) (no path fixes)"
                                    )
                                    .font(.system(size: 14))

                                    Text(
                                        fix.url.lastPathComponent
                                    )
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                    if !fix.missingSongTitles.isEmpty {

                                        Text(
                                            "Missing: "
                                            + fix.missingSongTitles.joined(
                                                separator: ", "
                                            )
                                        )
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.orange)
                                    }
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
                                    (writeFailed ? Color.red : Color.blue)
                                        .opacity(0.12)
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
                        "Click \"Rescan Saved Setlists\" to check every saved Setlist against the current Library."
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
    }


    // MARK: - Actions

    /// Step 1 — scan only. Read-only: computes what a fix WOULD do,
    /// doesn't touch any Setlist file on disk.
    private func runRescan() {

        pendingFixes =
            SavedSetlistsRescanner.previewRescan(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: libraryStore.missingSongIDs
            )

        isApplied = false
        lastSummary = nil
    }

    /// Step 2 — user confirmation happens implicitly by them clicking
    /// this button (only shown once there's something to fix); this
    /// is where the affected Setlist files are actually rewritten.
    private func applyPendingFixes() {

        guard let pendingFixes else {
            return
        }

        let summary =
            SavedSetlistsRescanner.applyRescan(pendingFixes)

        lastSummary = summary
        isApplied = true

        // Same idea as RescanTandaView posting .tandaSaved — lets any
        // currently-open saved-Setlist viewer (SavedSetlistViewerStore,
        // via SavedSetlistBrowserView's own Library-change listener)
        // pick up the corrected paths if it happens to have the same
        // Setlist open. Not required for correctness (the file itself
        // is already fixed either way), just avoids a stale on-screen
        // copy until the next reload.
        if summary.updatedSetlistCount > 0 {

            NotificationCenter.default.post(
                name: .setlistSaved,
                object: nil
            )
        }
    }

    private func discardPendingFixes() {

        pendingFixes = nil
        isApplied = false
        lastSummary = nil
    }
}
