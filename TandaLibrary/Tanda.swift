//
//  Tanda.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 23.08.26.
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

struct Tanda:
    Identifiable {

    let name: String
    let songs: [Song]

    /// Free-text note, editable in the Tanda Library's header
    /// (TandaLibraryView). `var` (unlike the other fields here) since
    /// it's the one thing about a loaded Tanda meant to be edited
    /// in place — see TandaStore.updateComment(for:to:).
    var comment: String

    /// Relative path (from the `Tandas/` root) of the folder this Tanda
    /// was loaded from — e.g. "Biagi", or "Biagi/Live" once deeper
    /// nesting exists. Used by TandaFolderTreeView's folder filter; not
    /// part of the saved JSON itself, purely derived from the file's
    /// location on disk (see TandaStore.loadTanda(from:)).
    let sourceFolder: String

    /// The exact file this Tanda was loaded from. Not part of the saved
    /// JSON itself — purely derived from disk location, same as
    /// `sourceFolder`. This is the Tanda's true stable identity (used
    /// for `id`, selection, and TandaStore.delete(_:)) since the JSON
    /// content itself has no unique identifier and a Tanda's `name`
    /// alone isn't guaranteed unique across folders.
    let sourceURL: URL

    /// Which TrackLibrary this Tanda's song `id`s were resolved
    /// against when the file was last saved — read straight from
    /// `TandaMetadataExport.savedAgainstLibraryName` (see that
    /// property's doc comment). `nil` for files saved before this
    /// field existed or copied in by hand.
    let savedAgainstLibraryName: String?

    var id: URL {

        sourceURL
    }
}
