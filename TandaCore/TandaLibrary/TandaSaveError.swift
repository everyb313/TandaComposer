//
//  TandaSaveError.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 25.08.26.
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

// MARK: - Tanda Save Error

enum TandaSaveError:
    LocalizedError {

    case tooFewTracks(Int)
    case tooManyTracks(Int)
    case duplicateTanda(existingName: String)
    case containsMissingTracks(titles: [String])

    /// Editing an existing Tanda (add/remove a track) would take it
    /// below the 3-track minimum. Distinct wording from `tooFewTracks`
    /// (which talks about the Setlist selection at creation time) —
    /// this one talks about the Tanda itself and points at the
    /// alternative (delete the whole Tanda).
    case wouldDropBelowMinimum(Int)
    case invalidReplacementTarget
    case replacementTargetChanged
    case replacementNotInLibrary
    case replacementIsMissing(String)
    case duplicateTrackInTanda(String)
    case replacementTitleMismatch

    var errorDescription:
        String? {

        switch self {

        case .tooFewTracks(let count):

            return "Please mark at least 3 tracks in the setlist for the Tanda (currently \(count))."

        case .tooManyTracks(let count):

            return "Please mark at most 8 tracks in the setlist for the Tanda (currently \(count))."

        case .duplicateTanda(let existingName):

            return "This Tanda (same tracks) already exists as \"\(existingName)\"."

        case .containsMissingTracks(let titles):

            let list =
                titles.joined(separator: ", ")

            return "Can't save a Tanda with track(s) missing on disk: \(list). Fix or remove them first."

        case .wouldDropBelowMinimum(let count):

            return "A Tanda needs at least 3 tracks (currently \(count)). Delete the whole Tanda instead if you want to remove it entirely."

        case .invalidReplacementTarget:
            return "The selected track position is no longer valid. Please reopen Same Title and try again."

        case .replacementTargetChanged:
            return "The original track has changed since Same Title was opened. Please reopen it before replacing the track."

        case .replacementNotInLibrary:
            return "The replacement track is not in the active Track Library."

        case .replacementIsMissing(let title):
            return "The replacement track is missing on disk: \(title)."

        case .duplicateTrackInTanda(let title):
            return "The Tanda already contains this track: \(title)."

        case .replacementTitleMismatch:
            return "The replacement track does not have the same title as the original track."
        }
    }
}
