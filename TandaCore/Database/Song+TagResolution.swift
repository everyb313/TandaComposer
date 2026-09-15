//
//  Song+TagResolution.swift
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


// MARK: - Song + Tag Resolution
//
// "Orchestra" and "Singer" are not raw tag fields — they are a
// user-configurable VIEW onto the raw fields (Artist/AlbumArtist/
// Grouping), because tango-tagging conventions vary per collection
// (see AppSettings.TagSource). Everything that needs "the orchestra"
// or "the singer" as a concept (Library/Tanda/Setlist table display,
// sorting, Tanda folder naming) goes through this resolver instead of
// reading `song.artist`/`song.albumArtist` directly, so it stays
// correct no matter which raw field the user has designated.
//
// Deliberately NOT used by: the HTML/M3U8/metadata exporters, or
// TandaDragPayload — those work with the actual tag fields as tag
// fields, not with the Orchestra/Singer concept, and must keep doing
// so.

extension Song {

    /// The raw value of whichever tag field `source` designates.
    func rawTagValue(
        for source:
            TagSource
    ) -> String? {

        switch source {

        case .artist:
            return artist

        case .albumArtist:
            return albumArtist

        case .grouping:
            return grouping
        }
    }


    /// This song's Orchestra, per the current `AppSettings.orchestraSource`.
    ///
    /// `@MainActor`: `AppSettings` is main-actor-isolated (it's an
    /// `ObservableObject` driving SwiftUI), and every call site here
    /// (Library/Tanda/Setlist table display + sort, Tanda saving) is
    /// already on the main actor — this struct itself (`Song`) is not,
    /// since it's also used off-main during background scanning, so
    /// the isolation has to be declared on these two methods
    /// specifically rather than inferred from the type.
    @MainActor
    func resolvedOrchestra(
        using settings:
            AppSettings
    ) -> String? {

        rawTagValue(
            for:
                settings.orchestraSource
        )
    }


    /// This song's Singer, per the current `AppSettings.singerSource`.
    /// See `resolvedOrchestra(using:)` for the `@MainActor` rationale.
    @MainActor
    func resolvedSinger(
        using settings:
            AppSettings
    ) -> String? {

        rawTagValue(
            for:
                settings.singerSource
        )
    }
}
