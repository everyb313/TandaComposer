//
//  SetlistView.swift
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
import UniformTypeIdentifiers
import AppKit

struct SetlistView: View {

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var setlistStore: SetlistStore

    @State private var selection = Set<UUID>()
    @State private var saveErrorMessage: String?
    @State private var saveErrorTitle = "Couldn't Save Set"
    @State private var showSavedConfirmation = false

    // MARK: - Status Counts
    //
    // Drives the "N missing" / "N not in library" summary in the
    // bottom bar — same red/blue meaning as each row's Status dot
    // (see PlaylistTableView), just aggregated so it's visible without
    // hovering over individual rows.
    private var missingCount: Int {
        setlistStore.entries.filter { $0.status == .fileMissing }.count
    }

    private var notInLibraryCount: Int {
        setlistStore.entries.filter { $0.status == .notInLibrary }.count
    }

    // MARK: - Total Playtime
    //
    // Song.duration is in seconds and is optional — it's currently
    // nil for FLAC/AIFF (see LibraryScanner) — so unknown-duration
    // tracks are skipped rather than counted as 0, and their count is
    // surfaced via a tooltip so the total doesn't look complete when
    // it isn't.
    private var totalPlaytimeSeconds: Int {
        setlistStore.songs
            .compactMap { $0.duration }
            .reduce(0, +)
    }

    private var unknownDurationCount: Int {
        setlistStore.songs
            .filter { $0.duration == nil }
            .count
    }

    private var totalPlaytimeString: String {
        String(
            format: "%02d:%02d",
            totalPlaytimeSeconds / 3600,
            (totalPlaytimeSeconds % 3600) / 60
        )
    }

    var body: some View {

        VStack(spacing: 0) {

            PlaylistTableView(
                entries: setlistStore.entries,
                selection: $selection
            )
            .environmentObject(libraryStore)
            .environmentObject(setlistStore)

            Divider()

            HStack {

                Text("\(setlistStore.songs.count) song(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !setlistStore.songs.isEmpty {

                    Text(
                        "· \(totalPlaytimeString)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(
                        unknownDurationCount > 0
                        ? "Total playtime (hh:mm). \(unknownDurationCount) track(s) have no known duration — common for FLAC/AIFF — and aren't included in this total."
                        : "Total playtime (hh:mm)"
                    )
                }

                if !setlistStore.duplicateSongIDs.isEmpty {

                    Text(
                        "\(setlistStore.duplicateSongIDs.count) duplicates"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if missingCount > 0 {

                    Label(
                        "\(missingCount) missing",
                        systemImage: "octagon.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help(
                        "File not found on disk at last TrackLibrary rescan. If the file moved, run \"Rescan TrackLibrary\", then \"Rescan Setlist\" to re-link it here."
                    )
                }

                if notInLibraryCount > 0 {

                    Label(
                        "\(notInLibraryCount) not in library",
                        systemImage: "questionmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .help(
                        "This track's Library entry no longer exists (removed or never imported)."
                    )
                }

                Spacer()

                Button(role: .destructive) {

                    removeSelected()

                } label: {

                    Label(
                        "Remove",
                        systemImage: "trash"
                    )
                }
                .disabled(selection.isEmpty)

                Button {

                    save()

                } label: {

                    Label(
                        "Save Set",
                        systemImage: "square.and.arrow.down"
                    )
                }
                .disabled(setlistStore.songs.isEmpty)

                if showSavedConfirmation {

                    Label(
                        "Saved",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
                }

                if let progress = setlistStore.importProgress {

                    HStack(spacing: 6) {

                        ProgressView()
                            .controlSize(.small)

                        Text(
                            "Importing \(progress.current) of \(progress.total)…"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(8)
        }

        .alert(
            saveErrorTitle,
            isPresented: .constant(
                saveErrorMessage != nil
            ),
            presenting: saveErrorMessage
        ) { _ in

            Button("OK") {

                saveErrorMessage = nil
            }

        } message: { message in

            Text(message)
        }

        .onAppear {

            setlistStore.resolveAgainstLibrary(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: libraryStore.missingSongIDs
            )
        }

        .onChange(of: libraryStore.songs) { _, _ in

            setlistStore.resolveAgainstLibrary(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: libraryStore.missingSongIDs
            )
        }

        .onChange(of: libraryStore.missingSongIDs) { _, newMissing in

            setlistStore.resolveAgainstLibrary(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: newMissing
            )
        }

        .onChange(of: setlistStore.name) { _, _ in

            setlistStore.resolveAgainstLibrary(
                byID: libraryStore.songsByID,
                byPath: libraryStore.songsByNormalizedPath,
                missingSongIDs: libraryStore.missingSongIDs
            )
        }

        .onChange(of: setlistStore.alreadySavedNoticeTick) { _, _ in

            flashSavedBadge()
        }
    }

    // MARK: - Selection

    private func removeSelected() {

        setlistStore.remove(
            atOffsets: setlistStore.selectedRowIndexes
        )

        selection.removeAll()
    }

    // MARK: - Save Set

    private func save() {

        do {

            try setlistStore.save()

            flashSavedBadge()

        } catch {

            saveErrorTitle = "Couldn't Save Set"
            saveErrorMessage = error.localizedDescription
        }
    }

    /// The short green "Saved" badge next to the Save button — after
    /// a save, and when a switch found nothing left to save.
    private func flashSavedBadge() {

        withAnimation {

            showSavedConfirmation = true
        }

        Task {

            try? await Task.sleep(
                nanoseconds: 1_500_000_000
            )

            withAnimation {

                showSavedConfirmation = false
            }
        }
    }

    // MARK: - Save Tanda
    //
    // Removed: the "Save Tanda" button is gone — saving a Tanda now
    // happens exclusively via drag-and-drop onto TandaLibraryView
    // (see its onDrop handler, which reads the current Setlist
    // selection at drop time via SetlistView's
    // pasteboardWriterForRow, same as this used to).
}
