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



// MARK: - Tanda Dance Filter

enum TandaDanceFilter:
    String,
    CaseIterable,
    Identifiable,
    Equatable {

    case all
    case tango
    case vals
    case milonga
    case variousGenres

    var id:
        Self {
        self
    }

    var title:
        String {

        switch self {

        case .all:
            return "A"

        case .tango:
            return "T"

        case .vals:
            return "V"

        case .milonga:
            return "M"

        case .variousGenres:
            return "X"
        }
    }

    var helpText:
        String {

        switch self {

        case .all:
            return "Show all dance types"

        case .tango:
            return "Show Tango only"

        case .vals:
            return "Show Vals only"

        case .milonga:
            return "Show Milonga only"

        case .variousGenres:
            return "Show VariousGenres only"
        }
    }

    /// Exact second component expected in the Tanda filename.
    ///
    /// Examples:
    ///
    /// Artist_Tango_...json
    /// Artist_Vals_...json
    /// Artist_Milonga_...json
    /// Artist_VariousGenres_...json
    ///
    /// The third component, such as VariousSingers, is deliberately
    /// not used for dance-type filtering.
    var filenameComponent:
        String? {

        switch self {

        case .all:
            return nil

        case .tango:
            return "Tango"

        case .vals:
            return "Vals"

        case .milonga:
            return "Milonga"

        case .variousGenres:
            return "VariousGenres"
        }
    }
}




// MARK: - Filtering

enum TandaLibraryFiltering {

    static func filteredTandas(
        store: TandaStore,
        folderSelection: TandaFolderSelection,
        danceFilter: TandaDanceFilter
    ) -> [Tanda] {

        let folderFilteredTandas: [Tanda]

        switch folderSelection {
        case .showAll:
            folderFilteredTandas = store.tandas

        case .folder(let path):
            folderFilteredTandas = store.tandas.filter { tanda in
                tanda.sourceFolder == path ||
                tanda.sourceFolder.hasPrefix("\(path)/")
            }
        }

        let danceFilteredTandas: [Tanda]

        if let requiredComponent = danceFilter.filenameComponent {
            danceFilteredTandas = folderFilteredTandas.filter { tanda in
                let filename = tanda.sourceURL
                    .deletingPathExtension()
                    .lastPathComponent

                let components = filename.split(
                    separator: "_",
                    omittingEmptySubsequences: false
                )

                guard components.count >= 2 else {
                    return false
                }

                return components[1] == requiredComponent
            }
        } else {
            danceFilteredTandas = folderFilteredTandas
        }

        return danceFilteredTandas.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
