//
//  PathNormalizer.swift
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

/// Utilities for comparing/storing file paths stably. macOS's filesystem
/// (APFS) stores filenames as Unicode, but the same visual filename can
/// arrive as different byte sequences (decomposed vs. precomposed accents)
/// depending on how it was created — a naive string comparison or a raw
/// path used as a database unique key can silently treat the same file as
/// two different ones. Normalizing before comparing/storing avoids this.
public enum PathNormalizer {
    /// Canonical form to store in the database's `normalized_path` column
    /// and to use for duplicate-detection — NOT necessarily what you'd
    /// display to the user (use the URL's own path for that).
    public static func normalize(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    public static func normalize(_ url: URL) -> String {
        normalize(url.standardizedFileURL.path)
    }
}
