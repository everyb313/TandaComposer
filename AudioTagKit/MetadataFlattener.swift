//
//  MetadataFlattener.swift
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

public struct MetadataRow {
    public let group: String
    public let key: String
    public let value: String
}

public struct FileMetadataResult {
    public let path: String
    public let rows: [MetadataRow]

    public init(path: String, rows: [MetadataRow]) {
        self.path = path
        self.rows = rows
    }
}

/// Flattens the nested metadata dictionaries our readers produce into a
/// flat list of (group, key, value) rows. The "group" concept mirrors
/// exiftool's -G (EXIF:/IPTC:/XMP:) — here the natural groups are the
/// container-specific sections: VorbisComment, StreamInfo, ID3-ish
/// format-specific blocks, iTunes-ish format-specific blocks, etc.
public enum MetadataFlattener {
    public static func flatten(_ metadata: [String: Any]) -> [MetadataRow] {
        var rows: [MetadataRow] = []

        for (topKey, topValue) in metadata {
            if topKey == "formatSpecific", let dict = topValue as? [String: [String: Any]] {
                // One extra level of nesting: the format name itself
                // becomes the group label (e.g. "id3 ", "iTunesMetadata").
                for (formatName, fields) in dict {
                    for (fieldKey, fieldValue) in fields {
                        rows.append(MetadataRow(group: formatName, key: fieldKey, value: stringify(fieldValue)))
                    }
                }
                continue
            }

            let group = groupLabel(for: topKey)

            if let dict = topValue as? [String: Any] {
                for (fieldKey, fieldValue) in dict {
                    rows.append(MetadataRow(group: group, key: fieldKey, value: stringify(fieldValue)))
                }
            } else {
                rows.append(MetadataRow(group: group, key: topKey, value: stringify(topValue)))
            }
        }

        return rows.sorted { ($0.group, $0.key) < ($1.group, $1.key) }
    }

    private static func groupLabel(for topLevelKey: String) -> String {
        switch topLevelKey {
        case "vorbisComments": return "VorbisComment"
        case "streamInfo": return "StreamInfo"
        case "common": return "Common"
        case "format", "durationSeconds": return "File"
        case "hasArtwork", "artworkInfo": return "Artwork"
        default: return "Other"
        }
    }

    private static func stringify(_ value: Any) -> String {
        String(describing: value)
    }
}
