//
//  TandaConventions.swift
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


// MARK: - Tanda Conventions
//
// "Orchestra" and "Singer" are not tags of their own: the user decides
// which tag field (Artist, AlbumArtist or Grouping) holds them
// (Settings → `AppSettings.orchestraSource` / `singerSource`).
//
// Every Tanda file records that choice in its header
// ("orchestraSource", "singerSource"), so whoever reads the file later —
// for example another DJ importing the Tanda into a different
// TrackLibrary — knows how to read the raw tags in it.
//
// The Tanda writer (`TandaMetadataExporter.export`) takes the values
// from here by default, the same way it takes the library name from
// `AppPaths.currentLibraryName`: this is a MIRROR of the two settings,
// kept in step by `AppSettings` (didSet on both properties). It exists
// only so that code which writes a Tanda without having the settings at
// hand (editing a comment, adding or removing a track, a rescan) still
// records the current choice.

public enum TandaConventions {

    public static var orchestra: TagSource = .artist

    public static var singer: TagSource = .albumArtist
}
