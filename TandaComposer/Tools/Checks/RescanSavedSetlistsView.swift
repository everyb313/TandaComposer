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


    /// True while "Apply Fixes" is on screen but can't be clicked
    /// because the Library is locked (same condition the header
    /// uses to show that button).
    private var applyBlockedByLock: Bool {

        guard
            libraryStore.isLocked,
            let pendingFixes,
            !isApplied,
            !pendingFixes.isEmpty
        else {
            return false
        }

        return true
    }


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
                .font(.system(size: 20))
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
                        : "Reconnect moved tracks in the saved Setlists"
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
            .controlSize(.large)
            .padding(8)

            Divider()

            // =====================================================
            // LOCK NOTICE — "Apply Fixes" is disabled while the
            // Library is locked; say so visibly, not only in a
            // tooltip.
            // =====================================================

            if applyBlockedByLock {
                LibraryLockBanner(
                    thenClick: "Apply Fixes"
                )
            }

            RescanIntro(
                what:
                    "Reconnects moved tracks in all your saved Setlists and saves the fixes.",
                limits:
                    "Tracks that are missing from disk are only listed. Nothing changes for them.",
                hint:
                    "Files moved? Run \"Rescan TrackLibrary\" first. For the open Setlist use \"Rescan Setlist\"."
            )


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
                            "No moved tracks found. Everything is up to date.",
                            systemImage:
                                "checkmark.circle.fill"
                        )
                        .font(.system(size: 16))
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
                        ? "\(RescanText.count(totalFixed, "track")) reconnected in \(RescanText.count(pendingFixes.count, "Setlist"))."
                        : "\(RescanText.count(totalFixed, "track")) can be reconnected in \(RescanText.count(pendingFixes.count, "Setlist")). Click \"Apply Fixes\" to save.",
                        systemImage:
                            isApplied
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle.fill"
                    )
                    .font(.system(size: 16, weight: .semibold))
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
                            "\(RescanText.count(totalMissing, "track")) missing from disk. Listed for information only."
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 8)
                    }

                    if let lastSummary, !lastSummary.failedWrites.isEmpty {

                        Text(
                            "\(RescanText.count(lastSummary.failedWrites.count, "Setlist file")) couldn't be saved."
                        )
                        .font(.system(size: 14))
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
                                        ? "\(fix.name) (\(RescanText.count(fix.fixedSongCount, "track")) reconnected)"
                                        : "\(fix.name) (no path fixes)"
                                    )
                                    .font(.system(size: 16))

                                    Text(
                                        fix.url.lastPathComponent
                                    )
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                    if !fix.missingSongTitles.isEmpty {

                                        Text(
                                            "Missing: "
                                            + fix.missingSongTitles.joined(
                                                separator: ", "
                                            )
                                        )
                                        .font(.system(size: 14))
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
                    .font(.system(size: 16))
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
                name: AppNotification.setlistSaved,
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
