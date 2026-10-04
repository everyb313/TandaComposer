//
//  SpecialImportSession.swift
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

import Foundation
import Combine

/// State of the one running "Special Import" (M3U8 with manual
/// assignment). Shared between the Setlist menu, which starts it, and
/// the Special Import window, which edits it.
///
/// The existing Setlist import is not involved: this only collects
/// decisions and hands the adopted Library songs to `SetlistActions`.
@MainActor
final class SpecialImportSession: ObservableObject {

    @Published private(set) var rows: [SpecialImportRow] = []

    @Published private(set) var sourceName: String = ""

    // MARK: - Lifecycle

    func begin(
        sourceURL: URL,
        tracks: [ImportedTrack],
        songs: [Song],
        settings: AppSettings
    ) {

        sourceName =
            sourceURL
                .deletingPathExtension()
                .lastPathComponent

        rows =
            SpecialImportPlanner.makeRows(
                tracks: tracks,
                songs: songs,
                orchestraSource: settings.orchestraSource,
                singerSource: settings.singerSource
            )
    }

    func reset() {

        rows = []
        sourceName = ""
    }

    // MARK: - Decisions

    func choose(_ song: Song, for rowID: UUID) {

        update(rowID) { $0.choose(song) }
    }

    func clearChoice(for rowID: UUID) {

        update(rowID) { $0.clearChoice() }
    }

    func setSkipped(_ skipped: Bool, for rowID: UUID) {

        update(rowID) { $0.setSkipped(skipped) }
    }

    private func update(
        _ rowID: UUID,
        _ change: (inout SpecialImportRow) -> Void
    ) {

        guard let index =
            rows.firstIndex(where: { $0.id == rowID })
        else {
            return
        }

        change(&rows[index])
    }

    // MARK: - Results

    var adoptedSongs: [Song] {

        SpecialImportPlanner.adoptedSongs(from: rows)
    }

    func count(of state: SpecialImportRow.State) -> Int {

        rows.filter { $0.state == state }.count
    }
}
