//
//  TandaLibraryView.swift
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
import AppKit
import UniformTypeIdentifiers




struct TandaLibraryStatusCounts {
    var missing = 0
    var notInLibrary = 0
    var stale = 0
}

struct TandaLibraryStatusResult {
    let libraryByID: [Int64: Song]
    let libraryByPath: [String: Song]
    let counts: TandaLibraryStatusCounts
}

enum TandaLibraryStatusResolver {

    static func resolve(
        tandas: [Tanda],
        libraryStore: LibraryStore
    ) -> TandaLibraryStatusResult {
        let byID = libraryStore.songsByID
        let byPath = libraryStore.songsByNormalizedPath
        var counts = TandaLibraryStatusCounts()

        for tanda in tandas {
            let trustID = tanda.savedAgainstLibraryName == AppPaths.currentLibraryName

            for song in tanda.songs {
                let resolution = LibraryReferenceResolver.resolve(
                    song,
                    byID: byID,
                    byPath: byPath,
                    missingSongIDs: libraryStore.missingSongIDs,
                    trustID: trustID
                )

                guard resolution.live != nil else {
                    counts.notInLibrary += 1
                    continue
                }

                if resolution.isMissing {
                    counts.missing += 1
                } else if resolution.pathChanged {
                    counts.stale += 1
                }
            }
        }

        return TandaLibraryStatusResult(
            libraryByID: byID,
            libraryByPath: byPath,
            counts: counts
        )
    }
}

struct TandaLibraryTaskTrigger: Equatable {
    let songIDs: [Int64?]
    let missingSongIDs: Set<Int64>
    let tandaCount: Int
}
