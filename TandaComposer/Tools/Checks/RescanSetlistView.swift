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
    private var setlistStore: SetlistStore

    /// The pending preview from `previewRescan` — nil before the first
    /// scan, or once its fixes have been applied/discarded.
    @State
    private var pendingFixes: [SetlistStore.RescanFix]?

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
        setlistStore.entries.filter { $0.status != .resolved }.count
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

        return setlistStore.entries.filter {
            $0.status != .resolved &&
            !fixedIDs.contains($0.id)
        }.count
    }


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
            // layout as RescanLibraryView so all three Rescan windows
            // look and behave the same way.
            // =====================================================

            HStack {

                Text(
                    "Rescan Setlist"
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
                        : "Reconnect the Setlist's moved tracks"
                    )

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
                    "Reconnects tracks in \"\(setlistStore.name)\" whose files have moved.",
                limits:
                    "Uses what the TrackLibrary already knows. It does not search your disks.",
                hint:
                    "Still missing afterwards? Run \"Rescan TrackLibrary\" first, then try again."
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

                        if stillFlaggedCount > 0 {

                            Label(
                                "No moved files found. Still missing: \(RescanText.count(stillFlaggedCount, "track")).",
                                systemImage:
                                    "exclamationmark.circle.fill"
                            )
                            .font(.system(size: 16))
                            .foregroundStyle(.orange)

                            Text(
                                "Next step: run \"Rescan TrackLibrary\", then try again."
                            )
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                            .padding(.horizontal, 24)

                        } else {

                            Label(
                                "No moved tracks found. Everything is up to date.",
                                systemImage:
                                    "checkmark.circle.fill"
                            )
                            .font(.system(size: 16))
                            .foregroundStyle(Color.green)
                        }

                        Spacer()
                    }

                } else {

                    Label(
                        isApplied
                        ? "\(RescanText.count(pendingFixes.count, "track")) reconnected and saved."
                        : "\(RescanText.count(pendingFixes.count, "track")) can be reconnected. Click \"Apply Fixes\" to save.",
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

                    if unfixableFlaggedCount > 0 {

                        Text(
                            "Still missing: \(RescanText.count(unfixableFlaggedCount, "more track")). Run \"Rescan TrackLibrary\" to look for them."
                        )
                        .font(.system(size: 14))
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
                                    .font(.system(size: 16))

                                    Text(
                                        "From: \(fix.oldPath)"
                                    )
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                    Text(
                                        "To: \(fix.song.path)"
                                    )
                                    .font(.system(size: 14, design: .monospaced))
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
                "The tracks were reconnected, but the Setlist couldn't be saved: \(message). Click \"Save Set\" to try again."
            )
        }
    }


    // MARK: - Actions

    /// Step 1 — scan only. Read-only: computes what a fix WOULD do,
    /// doesn't touch the Setlist or its saved file.
    private func runRescan() {

        pendingFixes =
            setlistStore.previewRescan(
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
            setlistStore.applyRescan(pendingFixes)

        // Also re-run the normal resolve pass, so every entry — not
        // just the ones fixed above — ends up fully up to date
        // against the current Library.
        setlistStore.resolveAgainstLibrary(
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
