//
//  DuplicateFinderView.swift
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


//
//  DuplicateFinderView.swift
//  TandaComposer
//
//  Duplicate clusters displayed with the same column layout,
//  widths and formatting as TandaLibraryView.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers


// MARK: - Duplicate Finder View

struct DuplicateFinderView:
    View {

    @EnvironmentObject
    private var libraryStore:
        LibraryStore

    @EnvironmentObject
    private var settings:
        AppSettings

    @State
    private var level:
        DuplicateLevel = .songArtist

    @State
    private var clusters:
        [DuplicateCluster] = []

    @State
    private var exportErrorMessage:
        String?


    // MARK: - Shared Library Columns

    private var columns:
        [(String, CGFloat)] {

        [
            (
                "",
                LibraryColumnDefaults.tandaLeadingSpacerWidth
            )
        ]
        +
        LibraryColumnDefaults.currentColumns()
    }


    // MARK: - Body

    var body:
        some View {

        VStack(
            alignment:
                .leading,
            spacing:
                0
        ) {

            // =====================================================
            // WINDOW HEADER
            // =====================================================

            HStack {

                Text(
                    "Find Duplicates"
                )
                .font(
                    .title2
                )
                .bold()


                Text(
                    clusters.isEmpty
                    ? "No clusters found"
                    : "\(clusters.count) cluster(s) found"
                )
                .font(
                    .subheadline
                )
                .foregroundStyle(
                    .secondary
                )


                Spacer()


                // =====================================================
                // EXPORT AS HTML
                // =====================================================

                Button {

                    exportHTML()

                } label: {

                    Label(
                        "Export HTML",
                        systemImage:
                            "square.and.arrow.up"
                    )
                }
                .disabled(
                    clusters.isEmpty
                )


                Picker(
                    "Level",
                    selection:
                        $level
                ) {

                    ForEach(
                        DuplicateLevel.allCases
                    ) { pickerLevel in

                        Text(
                            pickerLevel.title
                        )
                        .tag(
                            pickerLevel
                        )
                    }
                }
                .frame(
                    width:
                        300
                )
            }
            .padding(
                8
            )


            Divider()


            // =====================================================
            // RESULTS
            // =====================================================

            if clusters.isEmpty {

                VStack {

                    Spacer()

                    Text(
                        "No duplicates found at this level."
                    )
                    .foregroundStyle(
                        .secondary
                    )

                    Spacer()
                }

            } else {

                ScrollView(
                    [
                        .horizontal,
                        .vertical
                    ]
                ) {

                    LazyVStack(
                        alignment:
                            .leading,
                        spacing:
                            8
                    ) {

                        ForEach(
                            Array(
                                clusters.enumerated()
                            ),
                            id:
                                \.offset
                        ) { index, cluster in

                            DuplicateClusterBlock(
                                clusterNumber:
                                    index + 1,
                                cluster:
                                    cluster,
                                columns:
                                    columns
                            )
                        }
                    }
                    .padding(
                        8
                    )
                }
            }
        }
        .frame(
            minWidth:
                max(
                    settings.currentLibraryPaneWidth,
                    400
                ),
            maxWidth:
                max(
                    settings.currentLibraryPaneWidth,
                    400
                ),
            minHeight:
                420
        )
        .onAppear {

            recompute()
        }
        .onChange(
            of:
                level
        ) { _, _ in

            recompute()
        }
        .onChange(
            of:
                libraryStore.songs
        ) { _, _ in

            recompute()
        }
        .alert(
            "Couldn't Export",
            isPresented:
                .constant(
                    exportErrorMessage != nil
                ),
            presenting:
                exportErrorMessage
        ) { _ in

            Button(
                "OK"
            ) {

                exportErrorMessage =
                    nil
            }

        } message: { message in

            Text(
                message
            )
        }
    }


    // MARK: - Export HTML

    private func exportHTML() {

        let panel =
            NSSavePanel()

        panel.allowedContentTypes =
            [.html]

        panel.nameFieldStringValue =
            "TandaComposer Duplicate Report\(level.rawValue).html"

        panel.canCreateDirectories =
            true

        guard
            panel.runModal() == .OK,
            let url =
                panel.url
        else {

            return
        }

        do {

            try DuplicateHTMLExporter.export(
                clusters:
                    clusters,
                level:
                    level,
                libraryName:
                    libraryStore.currentLibraryName,
                librarySongs:
                    libraryStore.songs,
                to:
                    url
            )

        } catch {

            exportErrorMessage =
                error.localizedDescription
        }
    }


    // MARK: - Recompute

    private func recompute() {

        clusters =
            DuplicateFinder.findClusters(
                in:
                    libraryStore.songs,
                level:
                    level
            )
    }
}


// MARK: - Duplicate Cluster Block

private struct DuplicateClusterBlock:
    View {

    let clusterNumber:
        Int

    let cluster:
        DuplicateCluster

    let columns:
        [(String, CGFloat)]

    @EnvironmentObject
    private var settings:
        AppSettings


    var body:
        some View {

        VStack(
            alignment:
                .leading,
            spacing:
                0
        ) {

            // =====================================================
            // CLUSTER HEADER
            // =====================================================

            HStack {

                Text(
                    "Duplicate \(clusterNumber)"
                )
                .font(
                    .subheadline
                )
                .fontWeight(
                    .semibold
                )


                Text(
                    "\(cluster.songs.count) tracks"
                )
                .font(
                    .caption2
                )
                .foregroundStyle(
                    .secondary
                )


                Spacer()
            }
            .padding(
                .horizontal,
                8
            )
            .padding(
                .vertical,
                4
            )


            Divider()


            // =====================================================
            // COLUMN HEADER
            // =====================================================

            HStack(
                spacing:
                    0
            ) {

                ForEach(
                    columns,
                    id:
                        \.0
                ) { column in

                    Text(
                        LibraryColumnDefaults.headerTitle(
                            for: column.0,
                            settings: settings
                        )
                    )
                    .font(
                        .caption2
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .frame(
                        width:
                            column.1,
                        alignment:
                            .leading
                    )
                }
            }
            .padding(
                .horizontal,
                8
            )
            .padding(
                .vertical,
                2
            )


            Divider()


            // =====================================================
            // SONGS
            // =====================================================

            ForEach(
                Array(
                    cluster.songs.enumerated()
                ),
                id:
                    \.offset
            ) { index, song in

                DuplicateSongRow(
                    index:
                        index,
                    song:
                        song,
                    columns:
                        columns
                )
                .contentShape(
                    Rectangle()
                )
                .onTapGesture(
                    count:
                        2
                ) {

                    NotificationCenter.default.post(
                        name:
                            .tandaPreviewSongDoubleClicked,
                        object:
                            song
                    )
                }


                if index <
                    cluster.songs.count - 1 {

                    Divider()
                }
            }
        }
        .fixedSize(
            horizontal:
                true,
            vertical:
                false
        )
        .overlay(
            RoundedRectangle(
                cornerRadius:
                    6
            )
            .stroke(
                Color.secondary.opacity(
                    0.25
                )
            )
        )
    }
}


// MARK: - Duplicate Song Row

private struct DuplicateSongRow:
    View {

    let index:
        Int

    let song:
        Song

    let columns:
        [(String, CGFloat)]

    @EnvironmentObject
    private var settings:
        AppSettings


    var body:
        some View {

        HStack(
            spacing:
                0
        ) {

            ForEach(
                columns,
                id:
                    \.0
            ) { column in

                value(
                    text:
                        text(
                            for:
                                column.0
                        ),
                    width:
                        column.1
                )
            }
        }
        .padding(
            .horizontal,
            8
        )
        .padding(
            .vertical,
            3
        )
    }


    // MARK: - Column Value

    private func text(
        for columnName:
            String
    ) -> String {

        if columnName.isEmpty {

            return ""
        }


        return LibraryColumnDefaults.displayValue(
            for:
                columnName,
            song:
                song,
            settings:
                settings
        )
    }


    // MARK: - Value

    private func value(
        text:
            String,
        width:
            CGFloat
    ) -> some View {

        Text(
            text
        )
        .font(
            .system(
                size:
                    LibraryColumnDefaults.rowFontSize
            )
        )
        .lineLimit(
            1
        )
        .truncationMode(
            .tail
        )
        .frame(
            width:
                width,
            alignment:
                .leading
        )
        .help(
            text
        )
    }
}
