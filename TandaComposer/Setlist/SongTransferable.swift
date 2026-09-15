//
//  SongTransferable.swift
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
import CoreTransferable
import UniformTypeIdentifiers
//import TandaCore

/// Lets a Song be dragged from the library Table into the playlist List
/// (and reordered within it) via SwiftUI's `.draggable`/`.dropDestination`.
///
/// Uses the built-in `.json` content type rather than declaring a custom
/// UTType — a custom exported UTI needs to be registered in the app's
/// Info.plist (UTExportedTypeDeclarations), which only exists once this
/// is built as a real Xcode App target rather than run via `swift run`.
/// `.json` avoids that setup step; switch to a custom UTI later if you
/// want other apps to be able to receive a dragged Song too.
extension Song: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
