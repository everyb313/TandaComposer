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




enum TandaLibraryActions {

    static func saveSetlistSelectionAsTanda(
        store: TandaStore,
        libraryStore: LibraryStore,
        setlistStore: SetlistStore,
        settings: AppSettings
    ) throws {
        guard !libraryStore.isLocked else { return }

        let songs = setlistStore.selectedRowIndexes.compactMap { index -> Song? in
            setlistStore.songs.indices.contains(index)
                ? setlistStore.songs[index]
                : nil
        }

        try TandaSaver.save(
            songs: songs,
            existingTandas: store.tandas,
            missingSongIDs: libraryStore.missingSongIDs,
            settings: settings
        )
    }

    static func appendSetlistSelectionToTanda(
        _ tanda: Tanda,
        store: TandaStore,
        libraryStore: LibraryStore,
        setlistStore: SetlistStore
    ) throws {
        guard !libraryStore.isLocked else { return }

        let songs = setlistStore.selectedRowIndexes.compactMap { index -> Song? in
            setlistStore.songs.indices.contains(index)
                ? setlistStore.songs[index]
                : nil
        }

        try store.addSongs(
            songs,
            to: tanda,
            missingSongIDs: libraryStore.missingSongIDs
        )
    }

    static func deleteSong(
        at songIndex: Int,
        from tanda: Tanda,
        store: TandaStore
    ) throws {
        try store.removeSong(at: songIndex, from: tanda)
    }

    static func commitComment(
        _ newComment: String,
        for tanda: Tanda,
        store: TandaStore
    ) throws {
        guard newComment != tanda.comment else { return }
        try store.updateComment(for: tanda, to: newComment)
    }

    static func deleteTanda(
        _ tanda: Tanda,
        store: TandaStore
    ) throws {
        try store.delete(tanda)
    }
}
