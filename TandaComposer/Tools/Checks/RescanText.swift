//
//  RescanText.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 28.08.26.
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

/// Small text helpers shared by the Rescan windows.
enum RescanText {

    /// "1 track" / "3 tracks" — replaces the "track(s)" hedge.
    /// Pass `plural` for words that don't just take an "s".
    static func count(
        _ n: Int,
        _ singular: String,
        _ plural: String? = nil
    ) -> String {

        "\(n) " + (n == 1 ? singular : (plural ?? singular + "s"))
    }
}
