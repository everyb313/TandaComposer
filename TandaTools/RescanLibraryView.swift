//
//  RescanLibraryView.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 28.08.26.
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

struct RescanLibraryView: View {

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @EnvironmentObject
    private var scanner: LibraryScanner

    @State
    private var summary: RescanSummary?

    @State
    private var errorMessage: String?

    /// Set once a rescan has finished and its results have been
    /// reviewed and written to the database via `applyRescan(_:)`. As
    /// long as this is false, `summary`'s fixes are only a preview —
    /// nothing has actually changed in the Library yet.
    @State
    private var isApplied = false

    @State
    private var isApplying = false


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            // =====================================================
            // HEADER
            // =====================================================

            HStack {

                Text(
                    "Rescan Library"
                )
                .font(.title2)
                .bold()


                Spacer()


                if let summary {

                    Button {

                        exportHTML(
                            summary
                        )

                    } label: {

                        Label(
                            "Export HTML",
                            systemImage:
                                "square.and.arrow.up"
                        )
                    }
                }


                if let summary, !isApplied, summary.hasChangesToApply {

                    Button(role: .cancel) {

                        discardPendingSummary()

                    } label: {

                        Label(
                            "Discard",
                            systemImage:
                                "xmark"
                        )
                    }
                    .disabled(isApplying)

                    Button {

                        applyPendingSummary()

                    } label: {

                        Label(
                            "Apply Fixes",
                            systemImage:
                                "checkmark.circle"
                        )
                    }
                    .disabled(
                        isApplying ||
                        libraryStore.isLocked
                    )
                    .help(
                        libraryStore.isLocked
                        ? "Unlock the Library to apply these fixes"
                        : "Write these changes to the Library"
                    )

                } else {

                    Button {

                        startRescan()

                    } label: {

                        Label(
                            "Start Rescan",
                            systemImage:
                                "arrow.clockwise"
                        )
                    }
                    .disabled(
                        scanner.isScanning ||
                        libraryStore.isLocked
                    )
                    .help(
                        libraryStore.isLocked
                        ? "Unlock the Library to rescan"
                        : "Rescan the whole Library"
                    )
                }
            }
            .padding(8)


            Divider()


            // =====================================================
            // PROGRESS
            // =====================================================

            if scanner.isScanning {

                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {

                    if let phase = scanner.currentPhase {

                        Text(
                            phase.label
                        )
                        .font(.callout)
                        .foregroundStyle(.primary)
                    }

                    ProgressView(
                        value:
                            Double(scanner.processedCount),
                        total:
                            Double(max(scanner.totalCount, 1))
                    )

                    Text(
                        "\(scanner.processedCount) / \(scanner.totalCount)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(8)

                Divider()
            }


            // =====================================================
            // RESULTS
            // =====================================================

            if let summary {

                ScrollView {

                    VStack(
                        alignment: .leading,
                        spacing: 20
                    ) {

                        if summary.hasChangesToApply {

                            Label(
                                isApplied
                                ? "Applied to the Library."
                                : "Preview only — click \"Apply Fixes\" to write these changes to the Library.",
                                systemImage:
                                    isApplied
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.circle.fill"
                            )
                            .font(.callout)
                            .foregroundStyle(
                                isApplied
                                ? Color.green
                                : Color.orange
                            )
                        }

                        summaryRow(
                            summary
                        )

                        resultGroup(
                            title: "Missing",
                            color: .red,
                            songs: summary.missingSongs
                        )

                        resultGroup(
                            title: "Updated",
                            color: .yellow,
                            songs: summary.updatedSongs
                        )

                        relocatedGroup(
                            summary.relocatedTracks
                        )

                        resultGroup(
                            title: "Newly Imported",
                            color: .green,
                            songs: summary.newlyImportedSongs
                        )

                        failedGroup(
                            summary.failedReads
                        )
                    }
                    .padding(8)
                }

            } else {

                VStack {

                    Spacer()

                    Text(
                        scanner.isScanning
                        ? "Scanning…"
                        : "Click \"Start Rescan\" to check the Library against what's actually on disk."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
        .frame(
            minWidth: 700,
            minHeight: 420
        )
        .alert(
            "Couldn't Rescan Library",
            isPresented: .constant(errorMessage != nil),
            presenting: errorMessage
        ) { _ in

            Button("OK") {
                errorMessage = nil
            }

        } message: { message in

            Text(message)
        }
    }


    // MARK: - Summary Row

    private func summaryRow(
        _ summary: RescanSummary
    ) -> some View {

        HStack(
            spacing: 20
        ) {

            summaryItem("Unchanged", summary.unchangedCount)
            summaryItem("Updated", summary.updatedCount)
            summaryItem("Missing", summary.missingCount)
            summaryItem("Relocated", summary.relocatedCount)
            summaryItem("New", summary.newlyImportedCount)
            summaryItem("Failed", summary.failedReads.count)
        }
    }


    private func summaryItem(
        _ label: String,
        _ value: Int
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 2
        ) {

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.title3)
                .bold()
        }
        .padding(
            .horizontal, 12
        )
        .padding(
            .vertical, 8
        )
        .background(
            Color.secondary.opacity(0.1)
        )
        .cornerRadius(8)
    }


    // MARK: - Result Group (Missing / Updated / Newly Imported)

    @ViewBuilder
    private func resultGroup(
        title: String,
        color: Color,
        songs: [Song]
    ) -> some View {

        if !songs.isEmpty {

            VStack(
                alignment: .leading,
                spacing: 4
            ) {

                Text(
                    "\(title) (\(songs.count))"
                )
                .font(.headline)
                .foregroundStyle(color)

                ForEach(
                    Array(songs.enumerated()),
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
                        color.opacity(0.12)
                    )
                    .cornerRadius(6)
                }
            }
        }
    }


    // MARK: - Relocated Group

    @ViewBuilder
    private func relocatedGroup(
        _ tracks: [RelocatedTrack]
    ) -> some View {

        if !tracks.isEmpty {

            VStack(
                alignment: .leading,
                spacing: 4
            ) {

                Text(
                    "Relocated (\(tracks.count))"
                )
                .font(.headline)
                .foregroundStyle(.blue)

                ForEach(
                    Array(tracks.enumerated()),
                    id: \.offset
                ) { _, track in

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {

                        Text(
                            track.song.title ?? track.song.filename
                        )
                        .font(.system(size: 14))

                        Text(
                            "From: \(track.oldPath)"
                        )
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)

                        Text(
                            "To: \(track.song.path)"
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
        }
    }


    // MARK: - Failed Group

    @ViewBuilder
    private func failedGroup(
        _ failures: [(url: URL, error: Error)]
    ) -> some View {

        if !failures.isEmpty {

            VStack(
                alignment: .leading,
                spacing: 4
            ) {

                Text(
                    "Failed To Read (\(failures.count))"
                )
                .font(.headline)
                .foregroundStyle(.red)

                ForEach(
                    Array(failures.enumerated()),
                    id: \.offset
                ) { _, failure in

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {

                        Text(
                            failure.url.path
                        )
                        .font(.system(size: 12, design: .monospaced))

                        Text(
                            failure.error.localizedDescription
                        )
                        .font(.system(size: 12))
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
        }
    }


    // MARK: - Actions

    private func startRescan() {

        summary = nil
        isApplied = false

        Task {

            do {

                let result =
                    try await scanner.rescanLibrary()

                summary = result

                // Nothing meaningful to review — write the (harmless,
                // invisible) unchanged-file timestamp refresh right
                // away instead of making the user click "Apply Fixes"
                // for something that isn't really a fix.
                if !result.hasChangesToApply {

                    try await scanner.applyRescan(result)
                    try libraryStore.reload()

                    isApplied = true
                }

            } catch {

                errorMessage =
                    error.localizedDescription
            }
        }
    }


    private func applyPendingSummary() {

        guard let summary else {
            return
        }

        isApplying = true

        Task {

            do {

                try await scanner.applyRescan(summary)

                try libraryStore.reload()

                isApplied = true

            } catch {

                errorMessage =
                    error.localizedDescription
            }

            isApplying = false
        }
    }


    private func discardPendingSummary() {

        summary = nil
        isApplied = false
    }


    private func exportHTML(
        _ summary: RescanSummary
    ) {

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue =
            "TandaComposer Rescan Report.html"
        panel.canCreateDirectories = true

        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }

        do {

            try RescanHTMLExporter.export(
                summary: summary,
                libraryName:
                    libraryStore.currentLibraryName,
                to: url
            )

        } catch {

            errorMessage =
                error.localizedDescription
        }
    }
}
