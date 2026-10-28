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

import Combine

/// Shared state for the Same-Title filter shown in the existing TrackView.
/// This type deliberately contains no separate-window selection or replacement logic.
@MainActor
final class SameTitleSession: ObservableObject {

    /// The Setlist song whose normalized title is used to filter TrackView.
    @Published private(set) var trackViewFilterSong: Song?

    /// Toggle the filter for a song. Selecting the same anchor again turns it off.
    func toggleTrackViewFilter(for song: Song) {
        if let current = trackViewFilterSong,
           current.normalizedPath == song.normalizedPath {
            trackViewFilterSong = nil
        } else {
            trackViewFilterSong = song
        }
    }

    /// Set or retarget the active filter without toggling it off.
    /// Used when focus moves to another row in the Setlist.
    func setTrackViewFilter(for song: Song) {
        trackViewFilterSong = song
    }

    func clearTrackViewFilter() {
        trackViewFilterSong = nil
    }
}
