//
//  ImportSourcesView.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 05.09.26.
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


// MARK: - Manage Import Sources
//
// Lists every `ImportSource` row (one per "Add Files"/"Add Folder"
// import — see Models.swift) and lets the user remove ones that are
// no longer needed. This is pure bookkeeping cleanup: an ImportSource
// only tells a full Rescan which folders to walk for new/relocated
// files — deleting one here never touches a Song row or any file on
// disk.
//
// Hard rule (not just a suggestion): a folder can only be removed if
// the Library currently has ZERO songs under it. That's the whole
// safety mechanism for this feature — no separate confirmation dialog
// needed beyond a lightweight one, since there's no real ambiguity or
// cross-reference risk the way there is for Clean Up Missing Links.

struct ImportSourcesView: View {

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @State
    private var sources: [ImportSource] = []

    @State
    private var songCountsByID: [Int64: Int] = [:]

    @State
    private var pendingDelete: ImportSource?

    @State
    private var errorMessage: String?


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            HStack {

                Text(
                    "Manage Import Sources"
                )
                .font(.title2)
                .bold()

                Spacer()

                Button {

                    reload()

                } label: {

                    Label(
                        "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
            }
            .padding(8)

            Divider()

            Text(
                "Every \"Add Files\"/\"Add Folder\" import is recorded here so a TrackLibrary Rescan knows which folders to check for new or moved files. A folder can only be removed once the Library has no tracks left under it — removing one here never deletes any track or touches anything on disk, it only shortens what a future Rescan has to walk."
            )
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
            .padding(8)

            Divider()

            if sources.isEmpty {

                VStack {

                    Spacer()

                    Text(
                        "No import sources recorded yet."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                    Spacer()
                }

            } else {

                List {

                    ForEach(sources) { source in

                        row(for: source)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(
            minWidth: 560,
            minHeight: 380
        )
        .onAppear {
            reload()
        }
        .alert(
            "Remove This Import Source?",
            isPresented:
                Binding(
                    get: { pendingDelete != nil },
                    set: { value in
                        if !value {
                            pendingDelete = nil
                        }
                    }
                ),
            presenting: pendingDelete
        ) { source in

            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }

            Button("Remove", role: .destructive) {
                confirmDelete(source)
            }

        } message: { source in

            Text(
                "\"\(source.path)\" will no longer be checked by TrackLibrary Rescan. This doesn't touch any files or Library tracks."
            )
        }
        .alert(
            "Couldn't Remove Import Source",
            isPresented:
                Binding(
                    get: { errorMessage != nil },
                    set: { value in
                        if !value {
                            errorMessage = nil
                        }
                    }
                )
        ) {

            Button("OK") {
                errorMessage = nil
            }

        } message: {

            Text(
                errorMessage ?? ""
            )
        }
    }


    // MARK: - Row

    @ViewBuilder
    private func row(for source: ImportSource) -> some View {

        let count =
            songCountsByID[source.id ?? -1] ?? 0

        HStack(alignment: .top) {

            VStack(alignment: .leading, spacing: 3) {

                Text(
                    source.path
                )
                .font(.system(size: 14, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

                HStack(spacing: 8) {

                    Text(
                        source.importedAt,
                        style: .date
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                    if let volumeName = source.volumeName {

                        Text(
                            "· \(volumeName)"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }

                    Text(
                        count == 0
                        ? "· no tracks in Library"
                        : "· \(count) track(s) in Library"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(
                        count == 0
                        ? Color.orange
                        : Color.secondary
                    )
                }
            }

            Spacer()

            Button(
                "Remove",
                role: .destructive
            ) {
                pendingDelete = source
            }
            .disabled(
                count > 0 ||
                libraryStore.isLocked
            )
            .help(
                count > 0
                ? "This folder still has \(count) track(s) in the Library"
                : libraryStore.isLocked
                ? "Unlock the Library to remove import sources"
                : "Remove this folder from the Rescan list"
            )
        }
        .padding(.vertical, 4)
    }


    // MARK: - Actions

    private func reload() {

        do {

            sources = try libraryStore.fetchImportSources()

            songCountsByID = Dictionary(
                uniqueKeysWithValues:
                    sources.compactMap { source -> (Int64, Int)? in

                        guard let id = source.id else {
                            return nil
                        }

                        return (
                            id,
                            libraryStore.songCount(
                                underImportSourcePath: source.path
                            )
                        )
                    }
            )

        } catch {

            errorMessage = error.localizedDescription
        }
    }

    private func confirmDelete(_ source: ImportSource) {

        pendingDelete = nil

        guard let id = source.id else {
            return
        }

        do {

            try libraryStore.deleteImportSource(
                id: id,
                path: source.path
            )

            reload()

        } catch {

            errorMessage = error.localizedDescription
        }
    }
}
