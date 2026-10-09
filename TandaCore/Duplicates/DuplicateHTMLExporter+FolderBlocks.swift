//
//  DuplicateHTMLExporter+FolderBlocks.swift
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
//  DuplicateHTMLExporter.swift
//  TandaComposer
//

import Foundation

// MARK: - Folder block building

extension DuplicateHTMLExporter {

    // MARK: - Build Folder Blocks
    // =============================================================

    private static func trackCount(
        in folder: String,
        songs: [Song]
    ) -> Int {

        let prefix =
            folder.hasSuffix("/")
            ? folder
            : folder + "/"

        return songs.reduce(into: 0) { count, song in
            if song.path == folder || song.path.hasPrefix(prefix) {
                count += 1
            }
        }
    }

    static func makeFolderBlocks(
        clusters: [DuplicateCluster],
        librarySongs: [Song]
    ) -> [Level3Block] {

        var rowsByPair:
            [FolderPairKey: [Level3SongRow]] =
                [:]

        var sampleRatesA:
            [FolderPairKey: Set<String>] =
                [:]

        var sampleRatesB:
            [FolderPairKey: Set<String>] =
                [:]

        var fileTypesA:
            [FolderPairKey: Set<String>] =
                [:]

        var fileTypesB:
            [FolderPairKey: Set<String>] =
                [:]

        for cluster in clusters {

            let folders =
                comparisonFolders(
                    in: cluster
                )

            guard folders.count == 2 else {
                continue
            }

            let folderA =
                folders[0]

            let folderB =
                folders[1]

            let songsA =
                cluster.songs.filter {
                    parentFolder(
                        of: $0.path
                    ) == folderA
                }

            let songsB =
                cluster.songs.filter {
                    parentFolder(
                        of: $0.path
                    ) == folderB
                }

            guard
                !songsA.isEmpty,
                !songsB.isEmpty
            else {
                continue
            }

            let key =
                FolderPairKey(
                    folderA: folderA,
                    folderB: folderB
                )

            sampleRatesA[key, default: []]
                .formUnion(
                    songsA.map {
                        sampleRateText(
                            $0.sampleRate
                        )
                    }
                )

            sampleRatesB[key, default: []]
                .formUnion(
                    songsB.map {
                        sampleRateText(
                            $0.sampleRate
                        )
                    }
                )

            fileTypesA[key, default: []]
                .formUnion(
                    songsA.map {
                        $0.fileType ?? "—"
                    }
                )

            fileTypesB[key, default: []]
                .formUnion(
                    songsB.map {
                        $0.fileType ?? "—"
                    }
                )

            for (songA, songB) in zip(
                songsA,
                songsB
            ) {

                let row =
                    Level3SongRow(
                        title:
                            songA.title
                            ?? songA.filename,

                        artist:
                            combinedField(
                                songA.artist,
                                songB.artist
                            ),

                        albumArtist:
                            combinedField(
                                songA.albumArtist,
                                songB.albumArtist
                            ),

                        year:
                            combinedField(
                                songA.year.map(
                                    String.init
                                ),
                                songB.year.map(
                                    String.init
                                )
                            ),

                        sampleRate:
                            combinedField(
                                sampleRateText(
                                    songA.sampleRate
                                ),
                                sampleRateText(
                                    songB.sampleRate
                                )
                            ),

                        fileType:
                            combinedField(
                                songA.fileType,
                                songB.fileType
                            ),

                        filenameA:
                            songA.filename,

                        filenameB:
                            songB.filename
                    )

                rowsByPair[key, default: []]
                    .append(row)
            }
        }

        let sortedPairs =
            rowsByPair.sorted {
                lhs,
                rhs in

                if lhs.value.count !=
                    rhs.value.count {

                    return
                        lhs.value.count
                        >
                        rhs.value.count
                }

                let folderComparison =
                    lhs.key.folderA.localizedCaseInsensitiveCompare(
                        rhs.key.folderA
                    )

                if folderComparison !=
                    .orderedSame {

                    return
                        folderComparison
                        ==
                        .orderedAscending
                }

                return
                    lhs.key.folderB.localizedCaseInsensitiveCompare(
                        rhs.key.folderB
                    )
                    ==
                    .orderedAscending
            }

        return
            sortedPairs.enumerated().map {
                index,
                entry in

                let key =
                    entry.key

                let sortedRows =
                    entry.value.sorted {
                        lhs,
                        rhs in

                        lhs.title.localizedCaseInsensitiveCompare(
                            rhs.title
                        )
                        ==
                        .orderedAscending
                    }

                return Level3Block(
                    id:
                        "pair-\(index)",

                    folderA:
                        key.folderA,

                    folderB:
                        key.folderB,

                    trackCountA:
                        trackCount(in: key.folderA, songs: librarySongs),

                    trackCountB:
                        trackCount(in: key.folderB, songs: librarySongs),

                    folderNameA:
                        folderBasename(
                            key.folderA
                        ),

                    folderNameB:
                        folderBasename(
                            key.folderB
                        ),

                    metaA:
                        folderMeta(
                            sampleRates:
                                sampleRatesA[key]
                                ?? [],

                            fileTypes:
                                fileTypesA[key]
                                ?? []
                        ),

                    metaB:
                        folderMeta(
                            sampleRates:
                                sampleRatesB[key]
                                ?? [],

                            fileTypes:
                                fileTypesB[key]
                                ?? []
                        ),

                    rows:
                        sortedRows
                )
            }
    }

    // =============================================================
}
