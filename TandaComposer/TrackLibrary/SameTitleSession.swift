//
//  SameTitleSession.swift
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

import SwiftUI
import AppKit
import Combine

/// What the "Same Title" window shows: the tracks with the same title as
/// the ones selected in the TrackLibrary when "?" was clicked (a snapshot,
/// it does not follow the TrackLibrary selection), and the window's own
/// row selection.
@MainActor
final class SameTitleSession: ObservableObject {

    @Published private(set) var result = SameTitleSession.emptyResult

    @Published private(set) var libraryName = ""

    @Published private(set) var selection = SameTitleSelection()

    /// Every row of the window, top to bottom (for Shift ranges).
    private var order: [String] = []

    private static let emptyResult = SameTitleResult(
        groups: [],
        omittedTitleCount: 0,
        untitled: []
    )

    // MARK: - Lifecycle

    func show(
        selected: [Song],
        library: [Song],
        libraryName: String,
        settings: AppSettings
    ) {

        result = SameTitleFinder.find(
            for: selected,
            in: library,
            orchestraSource: settings.orchestraSource,
            singerSource: settings.singerSource
        )

        order = result.groups.flatMap { group in
            group.songs.map(\.normalizedPath)
        }

        selection = SameTitleSelection()
        self.libraryName = libraryName
    }

    /// Empties the window, e.g. after the TrackLibrary was switched.
    func clear() {

        result = SameTitleSession.emptyResult
        order = []
        selection = SameTitleSelection()
        libraryName = ""
    }

    // MARK: - Selection

    func click(on song: Song, command: Bool, shift: Bool) {

        selection.click(
            song.normalizedPath,
            in: order,
            command: command,
            shift: shift
        )
    }

    func isSelected(_ song: Song) -> Bool {
        selection.contains(song.normalizedPath)
    }

    /// The selected rows in the order they are shown. For the later
    /// "Add to Setlist".
    var selectedSongs: [Song] {

        result.groups
            .flatMap(\.songs)
            .filter { selection.contains($0.normalizedPath) }
    }
}
