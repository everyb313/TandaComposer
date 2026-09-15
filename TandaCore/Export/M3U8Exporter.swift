//
//  M3U8Exporter.swift
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

public enum M3U8PathStyle {
    case relative(to: URL)
    case absolute
}

public enum M3U8Exporter {
    /// Renders the playlist to M3U8-formatted Data (UTF-8 with a leading
    /// BOM — several older/pickier hardware players expect the BOM to
    /// correctly detect UTF-8 rather than assuming Latin-1) without
    /// touching disk. Split out from `export(...)` so callers that need
    /// the bytes but not a file — like a `FileDocument`'s `fileWrapper`,
    /// which can't call back into an actor-isolated store — can render
    /// up front, on whatever actor they're already on, and hand off a
    /// plain `Data` value from there.
    public static func render(
        songs: [Song],
        pathStyle: M3U8PathStyle,
        extended: Bool
    ) -> Data {
        var lines: [String] = []
        if extended {
            lines.append("#EXTM3U")
        }

        for song in songs {
            let songURL = URL(fileURLWithPath: song.path)
            let pathString: String
            switch pathStyle {
            case .absolute:
                pathString = song.path
            case .relative(let baseURL):
                pathString = relativePath(from: baseURL, to: songURL)
            }

            if extended {
                let duration = song.duration ?? -1 // -1 is the M3U convention for "unknown"
                let title = [song.artist, song.title].compactMap { $0 }.joined(separator: " - ")
                lines.append("#EXTINF:\(duration),\(title.isEmpty ? song.filename : title)")
            }
            lines.append(pathString)
        }

        let content = lines.joined(separator: "\n") + "\n"
        return content.data(using: .utf8) ?? Data()
    }

    public static func export(
        songs: [Song],
        to fileURL: URL,
        pathStyle: M3U8PathStyle,
        extended: Bool
    ) throws {
        let data = render(songs: songs, pathStyle: pathStyle, extended: extended)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Computes a relative path from `baseURL` (where the .m3u8 file will
    /// live) to `targetURL` (a song's location), using ".." to walk back up
    /// as needed — the standard convention understood by players that
    /// support relative M3U paths.
    private static func relativePath(from baseURL: URL, to targetURL: URL) -> String {
        let baseComponents = baseURL.standardizedFileURL.deletingLastPathComponent().pathComponents
        let targetComponents = targetURL.standardizedFileURL.pathComponents

        var commonPrefixLength = 0
        while commonPrefixLength < baseComponents.count,
              commonPrefixLength < targetComponents.count,
              baseComponents[commonPrefixLength] == targetComponents[commonPrefixLength] {
            commonPrefixLength += 1
        }

        let upLevels = baseComponents.count - commonPrefixLength
        var relativeComponents = Array(repeating: "..", count: max(0, upLevels))
        relativeComponents += targetComponents[commonPrefixLength...]
        return relativeComponents.joined(separator: "/")
    }
}
