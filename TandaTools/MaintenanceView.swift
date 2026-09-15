//
//  MaintenanceView.swift
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

// MARK: - Maintenance
//
// "Compact TrackLibrary" (SQLite VACUUM — see
// LibraryStore.compactCurrentLibrary() for why this is ever needed).
// Opened from the top-level "Maintenance" menu (MaintenanceCommands),
// which also holds "Manage Import Sources…" and the four Rescan
// windows — those stay as their own separate windows, this one is
// just Compact.

struct MaintenanceView: View {

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @State
    private var isCompacting = false

    @State
    private var lastResult: LibraryStore.CompactResult?

    @State
    private var errorMessage: String?


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            Text(
                "Maintenance"
            )
            .font(.title2)
            .bold()
            .padding(8)

            Divider()

            VStack(
                alignment: .leading,
                spacing: 10
            ) {

                Text(
                    "Compact TrackLibrary"
                )
                .font(.headline)

                Text(
                    "Deleting songs doesn't shrink the TrackLibrary's file on its own — the space stays reserved for reuse. Compacting rebuilds the file and reclaims that space."
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                HStack {

                    Button {

                        runCompact()

                    } label: {

                        if isCompacting {

                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 2)
                        }

                        Text(
                            isCompacting
                            ? "Compacting…"
                            : "Compact TrackLibrary"
                        )
                    }
                    .disabled(
                        isCompacting
                        || libraryStore.isLocked
                    )
                    .help(
                        libraryStore.isLocked
                        ? "Unlock the TrackLibrary to compact it"
                        : "Reclaim disk space freed by deleted songs"
                    )

                    if let lastResult {

                        Label(
                            summary(for: lastResult),
                            systemImage:
                                "checkmark.circle.fill"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(Color.green)
                    }
                }

                if let errorMessage {

                    Text(
                        errorMessage
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                }
            }
            .padding(8)

            Spacer()
        }
        .frame(
            minWidth: 420,
            minHeight: 220
        )
    }


    // MARK: - Actions

    private func runCompact() {

        isCompacting = true
        errorMessage = nil

        DispatchQueue.global(
            qos: .userInitiated
        ).async {

            do {

                let result =
                    try libraryStore.compactCurrentLibrary()

                DispatchQueue.main.async {

                    lastResult = result
                    isCompacting = false
                }

            } catch {

                DispatchQueue.main.async {

                    errorMessage =
                        error.localizedDescription

                    isCompacting = false
                }
            }
        }
    }


    private func summary(
        for result: LibraryStore.CompactResult
    ) -> String {

        let reclaimed =
            max(
                0,
                result.sizeBefore - result.sizeAfter
            )

        guard reclaimed > 0 else {
            return "Already compact — nothing to reclaim."
        }

        let formatter =
            ByteCountFormatter()

        formatter.countStyle = .file

        return
            "Reclaimed \(formatter.string(fromByteCount: reclaimed))."
    }
}
