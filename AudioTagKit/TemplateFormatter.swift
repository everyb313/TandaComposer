//
//  TemplateFormatter.swift
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

/// Substitutes "{tagName}" tokens in a template string with matching row
/// values — exiftool's -p custom print format, reused here for both
/// `read --format` (one-line-per-file summaries) and `rename --template`
/// (filename generation).
public enum TemplateFormatter {
    /// Lookup is case-insensitive and matches on the row's key only — the
    /// group prefix, if any, is ignored, so "{title}" matches
    /// "VorbisComment:TITLE" just as well as "Common:title". First match
    /// wins when the same key name appears in multiple groups.
    public static func apply(_ template: String, to rows: [MetadataRow]) -> String {
        var lookup: [String: String] = [:]
        for row in rows where lookup[row.key.lowercased()] == nil {
            lookup[row.key.lowercased()] = row.value
        }

        var result = ""
        var remaining = Substring(template)

        while let openRange = remaining.range(of: "{") {
            result += remaining[remaining.startIndex..<openRange.lowerBound]
            remaining = remaining[openRange.upperBound...]

            guard let closeRange = remaining.range(of: "}") else {
                result += "{" + remaining
                remaining = ""
                break
            }

            let token = String(remaining[remaining.startIndex..<closeRange.lowerBound]).lowercased()
            result += lookup[token] ?? ""
            remaining = remaining[closeRange.upperBound...]
        }

        result += remaining
        return result
    }
}
