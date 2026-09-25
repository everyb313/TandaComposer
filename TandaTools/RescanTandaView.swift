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
                        : "Re-link Tanda references that moved"
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
            .padding(8)

            Divider()

            Text(
                "Checks all saved Tandas against the TrackLibrary as currently loaded (re-links tracks by their Library ID), and also checks whether a Tanda's saved name/folder still matches what its CURRENT tracks resolve to (e.g. after adding or removing a track changed the Orchestra/Singer mix) — offering to rename/refile it if not. This does NOT scan disk itself — if a file moved and the TrackLibrary hasn't picked that up yet, run \"Rescan TrackLibrary\" first."
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
                                "Nothing to re-link, but \(stillFlaggedCount) track(s) across all Tandas are still missing or not in library.",
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
                                "No broken references or name/folder drift found.",
                                systemImage:
                                    "checkmark.circle.fill"
                            )
                            .font(.system(size: 14))
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
                        ? "\(totalFixed) reference(s) and \(totalRenamed) rename(s)"
                        : "\(totalFixed) reference(s)"

                    Label(
                        isApplied
                        ? "\(summarySubject) fixed across \(tandaCount) Tanda(s)."
                        : "\(summarySubject) found across \(tandaCount) Tanda(s) — click \"Apply Fixes\" to fix and save them.",
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

                    if let lastSummary, !lastSummary.failedWrites.isEmpty {

                        Text(
                            "\(lastSummary.failedWrites.count) Tanda file(s) couldn't be updated."
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
                                        $0.url == fix.tanda.sourceURL
                                    } ?? false

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {

                                    Text(
                                        fix.rename != nil
                                        ? "\(fix.tanda.name) (\(fix.fixedSongCount) track(s), renamed)"
                                        : "\(fix.tanda.name) (\(fix.fixedSongCount) track(s))"
                                    )
                                    .font(.system(size: 14))

                                    Text(
                                        fix.tanda.sourceFolder.isEmpty
                                        ? fix.tanda.sourceURL.lastPathComponent
                                        : "\(fix.tanda.sourceFolder)/\(fix.tanda.sourceURL.lastPathComponent)"
                                    )
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .strikethrough(
                                        fix.rename != nil
                                    )

                                    if let rename = fix.rename {

                                        Text(
                                            "→ \(rename.newFolder.pathComponents.suffix(2).joined(separator: "/"))/\(rename.newName).json"
                                        )
                                        .font(.system(size: 12, design: .monospaced))
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
                name: .tandaSaved,
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
