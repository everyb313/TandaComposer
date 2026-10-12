//
//  RescanTandaView.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 29.08.26.
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

struct RescanTandaView: View {

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @EnvironmentObject
    private var settings: AppSettings

    @StateObject
    private var tandaStore =
        TandaStore()

    /// The pending preview from `previewRescan` — nil before the
    /// first scan, or once explicitly discarded. Deliberately stays
    /// populated after Apply too (applyPendingFixes never clears it) —
    /// the applied view still needs it to know WHICH Tandas were
    /// touched; see lastSummary below for the actual outcome counts.
    @State
    private var pendingFixes: [TandaRescanFix]?

    /// Set once the last preview's fixes have been written (or there
    /// was nothing to write).
    @State
    private var isApplied = false

    @State
    private var lastSummary: TandaRescanSummary?

    // MARK: - Status Count
    //
    // Same reasoning as RescanSetlistView's stillFlaggedCount — a
    // clean previewRescan (nothing to re-link) doesn't mean nothing is
    // wrong; it only means the TrackLibrary hasn't found a new
    // location for anything yet.
    private var stillFlaggedCount: Int {

        let libraryIDs =
            Set(
                libraryStore.songs.compactMap {
                    $0.id
                }
            )

        return tandaStore.tandas.reduce(0) { total, tanda in

            total + tanda.songs.filter { song in

                guard let id = song.id else {
                    return true
                }

                guard libraryIDs.contains(id) else {
                    return true
                }

                return libraryStore.missingSongIDs.contains(id)

            }.count
        }
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
            // layout as RescanLibraryView/RescanSetlistView.
            // =====================================================

            HStack {

                Text(
                    "Rescan TandaLibrary"
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
                        : "Reconnect moved tracks in the saved Tandas"
                    )

                } else {

                    Button {

                        runRescan()

                    } label: {

                        Label(
                            "Rescan TandaLibrary",
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
                    "Reconnects moved tracks in all saved Tandas and saves the fixes.",
                limits:
                    "Also checks each Tanda's name and folder, and offers a rename if the orchestra or singer changed.",
                hint:
                    "Files moved? Run \"Rescan TrackLibrary\" first."
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
                                "No moved files found. Still missing across all Tandas: \(RescanText.count(stillFlaggedCount, "track")).",
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
                                "No moved tracks and no name or folder changes found.",
                                systemImage:
                                    "checkmark.circle.fill"
                            )
                            .font(.system(size: 16))
                            .foregroundStyle(Color.green)
                        }

                        Spacer()
                    }

                } else {

                    // Before Apply: these are what the preview FOUND
                    // (an intent), read from pendingFixes. After Apply:
                    // deliberately read the ACTUAL outcome from
                    // lastSummary instead of recomputing the same shape
                    // from pendingFixes again — pendingFixes still holds
                    // every fix that was ATTEMPTED, which would silently
                    // over-count if any of them ended up in
                    // lastSummary.failedWrites below.
                    let totalFixed =
                        isApplied
                        ? (lastSummary?.fixedReferenceCount ?? 0)
                        : pendingFixes.reduce(0) { $0 + $1.fixedSongCount }

                    let totalRenamed =
                        isApplied
                        ? (lastSummary?.renamedTandaCount ?? 0)
                        : pendingFixes.filter { $0.rename != nil }.count

                    let tandaCount =
                        isApplied
                        ? (lastSummary?.updatedTandaCount ?? 0)
                        : pendingFixes.count

                    let summarySubject =
                        totalRenamed > 0
                        ? "\(RescanText.count(totalFixed, "track")) and \(RescanText.count(totalRenamed, "rename"))"
                        : "\(RescanText.count(totalFixed, "track"))"

                    Label(
                        isApplied
                        ? "\(summarySubject) fixed across \(RescanText.count(tandaCount, "Tanda"))."
                        : "\(summarySubject) can be fixed across \(RescanText.count(tandaCount, "Tanda")). Click \"Apply Fixes\" to save.",
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

                    if let lastSummary, !lastSummary.failedWrites.isEmpty {

                        Text(
                            "\(RescanText.count(lastSummary.failedWrites.count, "Tanda file")) couldn't be saved."
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
                                        $0.url == fix.tanda.sourceURL
                                    } ?? false

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {

                                    Text(
                                        fix.rename != nil
                                        ? "\(fix.tanda.name) (\(RescanText.count(fix.fixedSongCount, "track")), renamed)"
                                        : "\(fix.tanda.name) (\(RescanText.count(fix.fixedSongCount, "track")))"
                                    )
                                    .font(.system(size: 16))

                                    Text(
                                        fix.tanda.sourceFolder.isEmpty
                                        ? fix.tanda.sourceURL.lastPathComponent
                                        : "\(fix.tanda.sourceFolder)/\(fix.tanda.sourceURL.lastPathComponent)"
                                    )
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .strikethrough(
                                        fix.rename != nil
                                    )

                                    if let rename = fix.rename {

                                        Text(
                                            "→ \(rename.newFolder.pathComponents.suffix(2).joined(separator: "/"))/\(rename.newName).json"
                                        )
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundStyle(.blue)
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
                        "Click \"Rescan TandaLibrary\" to check its tracks against the current Library."
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
    /// doesn't touch any Tanda file on disk.
    private func runRescan() {

        pendingFixes =
            tandaStore.previewRescan(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: libraryStore.missingSongIDs,
                settings: settings
            )

        isApplied = false
        lastSummary = nil
    }

    /// Step 2 — user confirmation happens implicitly by them clicking
    /// this button (only shown once there's something to fix); this
    /// is where the affected Tanda files are actually rewritten.
    private func applyPendingFixes() {

        guard let pendingFixes else {
            return
        }

        let summary =
            tandaStore.applyRescan(pendingFixes)

        lastSummary = summary
        isApplied = true

        // Same notification TandaLibraryView already listens for
        // after saving a new Tanda — reuses that existing reload path
        // so any currently-open Tandaview picks up the corrected
        // paths immediately, without needing a separate mechanism.
        if summary.updatedTandaCount > 0 {

            NotificationCenter.default.post(
                name: AppNotification.tandaSaved,
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
