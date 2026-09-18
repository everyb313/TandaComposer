//
//  M3U8Importer.swift
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

/// Reads an `.m3u8` file — TandaComposer's own export, or a foreign one
/// from another tool — and resolves it into Songs already known to the
/// active TrackLibrary.
///
/// Deliberately path-only, even for files this app exported itself: a
/// TandaComposer export also writes a `.tanda.json` sidecar with full
/// Song records and ids, but using it here would mean two different
/// resolution paths (rich metadata for "our" files, path-only for
/// everyone else's) with different failure behavior. One path is
/// simpler and matches every other "no fallback" decision made for
/// this feature. The sidecar keeps being written by
/// `SetlistMetadataExporter` regardless — nothing here removes it.
public enum M3U8Importer {

    public struct Result {
        /// Order and duplicates preserved exactly as they appeared in
        /// the file.
        public let resolvedSongs: [Song]

        /// Paths that parsed fine but don't match any song currently
        /// in the Library (by `normalizedPath`). No fallback is
        /// attempted — a near-miss (e.g. same file, different mount
        /// point) is reported here, not guessed at.
        public let notInLibraryPaths: [String]

        /// Lines that couldn't be read as a plain file path at all —
        /// currently only `scheme://...` URI-style lines (e.g.
        /// `file://…`), which are out of scope for this version.
        public let unreadableLines: [String]
    }

    /// Parses `fileURL` and resolves every entry against
    /// `songsByNormalizedPath` (pass `LibraryStore.songsByNormalizedPath`
    /// — already built once per Library, no need to rebuild it here).
    ///
    /// Throws only if the file itself can't be read (missing,
    /// permissions). A malformed or partially unreadable *contents*
    /// never throws — that's reported per-line in the returned
    /// `Result` instead.
    public static func importSongs(
        from fileURL: URL,
        songsByNormalizedPath: [String: Song]
    ) throws -> Result {
        let parsedLines = try parseLines(from: fileURL)

        var resolvedSongs: [Song] = []
        var notInLibraryPaths: [String] = []
        var unreadableLines: [String] = []

        for parsedLine in parsedLines {
            switch parsedLine {
            case .unreadable(let description):
                unreadableLines.append(description)

            case .path(let path):
                let normalized = PathNormalizer.normalize(path)
                if let song = songsByNormalizedPath[normalized] {
                    resolvedSongs.append(song)
                } else {
                    notInLibraryPaths.append(path)
                }
            }
        }

        return Result(
            resolvedSongs: resolvedSongs,
            notInLibraryPaths: notInLibraryPaths,
            unreadableLines: unreadableLines
        )
    }

    // MARK: - Line parsing

    private enum ParsedLine {
        case path(String)
        case unreadable(String)
    }

    private static func parseLines(from fileURL: URL) throws -> [ParsedLine] {
        let data = try Data(contentsOf: fileURL)
        let text = decodedText(from: data)
        let baseDirectory = fileURL.deletingLastPathComponent()

        var results: [ParsedLine] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            guard !line.isEmpty else { continue }

            // "#EXTM3U", "#EXTINF:...", or any other directive/comment
            // line — informational only in this app's own exports, and
            // not needed for path-only resolution, so simply skipped
            // rather than parsed.
            if line.hasPrefix("#") { continue }

            if let scheme = uriScheme(of: line) {
                results.append(
                    .unreadable("\(line)  (unsupported \(scheme):// URI — plain file paths only)")
                )
                continue
            }

            results.append(.path(resolvedPath(line, relativeTo: baseDirectory)))
        }

        return results
    }

    /// UTF-8 first, with a leading BOM (some tools, including possibly
    /// this app's own exporter, may write one) stripped if present.
    /// Falls back to Latin-1 on outright decode failure — every byte
    /// value is valid Latin-1, so this never fails; it's the
    /// deliberate last resort for older/legacy M3U files.
    private static func decodedText(from data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8.hasPrefix("\u{FEFF}") ? String(utf8.dropFirst()) : utf8
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Detects a `scheme://...` prefix (e.g. `file://`, `http://`).
    /// Plain POSIX paths — including ones that legitimately contain
    /// "://" nowhere at the start — never match this.
    private static func uriScheme(of line: String) -> String? {
        guard let separatorRange = line.range(of: "://") else {
            return nil
        }
        let scheme = line[line.startIndex..<separatorRange.lowerBound]
        guard
            !scheme.isEmpty,
            scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else {
            return nil
        }
        return String(scheme)
    }

    /// Absolute paths pass through unchanged. Relative paths are
    /// resolved against the directory the `.m3u8` file itself lives
    /// in — the inverse of `M3U8Exporter.relativePath`, which is what
    /// produces paths in this exact shape ("../", "sub/name.mp3", …)
    /// when a Setlist was exported with relative pathing.
    private static func resolvedPath(_ line: String, relativeTo baseDirectory: URL) -> String {
        if line.hasPrefix("/") {
            return line
        }
        return baseDirectory
            .appendingPathComponent(line)
            .standardizedFileURL
            .path
    }
}
