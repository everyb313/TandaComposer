//
//  M3U8Importer.swift
//
//  Copyright © 2026 Hagen Eckert.
//

import Foundation

/// Reads M3U/M3U8 playlists into neutral `ImportedTrack` records.
///
/// The existing path-only import API remains available for the normal
/// TandaComposer import path. Foreign-library imports should use
/// `importTracks(from:)` and pass the result to `LibraryTrackMatcher`.
public enum M3U8Importer {

    public struct Result {
        public let resolvedSongs: [Song]
        public let notInLibraryPaths: [String]
        public let unreadableLines: [String]

        public init(
            resolvedSongs: [Song],
            notInLibraryPaths: [String],
            unreadableLines: [String]
        ) {
            self.resolvedSongs = resolvedSongs
            self.notInLibraryPaths = notInLibraryPaths
            self.unreadableLines = unreadableLines
        }
    }

    /// Parses an M3U/M3U8 into source records without trying to resolve
    /// anything against the current Library.
    public static func importTracks(
        from fileURL: URL
    ) throws -> [ImportedTrack] {
        let data = try Data(contentsOf: fileURL)
        let text = decodedText(from: data)
        let baseDirectory = fileURL.deletingLastPathComponent()

        var results: [ImportedTrack] = []
        var pendingEXTINF: EXTINF?
        var sourceIndex = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF:") {
                pendingEXTINF = parseEXTINF(line)
                continue
            }

            if line.hasPrefix("#") {
                continue
            }

            if uriScheme(of: line) != nil {
                // URI handling remains out of scope for the current file
                // importer. Keep the entry out of the candidate list rather
                // than inventing a local path.
                pendingEXTINF = nil
                continue
            }

            let resolvedPath = resolvedPath(line, relativeTo: baseDirectory)
            let filename = URL(fileURLWithPath: resolvedPath).lastPathComponent

            let ext = pendingEXTINF
            let parsedDisplay = parseDisplayName(ext?.displayName)

            results.append(
                ImportedTrack(
                    sourceIndex: sourceIndex,
                    path: resolvedPath,
                    filename: filename,
                    title: parsedDisplay.title,
                    artist: parsedDisplay.artist,
                    duration: ext?.duration,
                    sourceDisplayName: ext?.displayName
                )
            )

            sourceIndex += 1
            pendingEXTINF = nil
        }

        return results
    }

    /// Legacy exact-path import used by the existing normal Setlist import.
    /// It intentionally retains its old behavior; foreign matching is a
    /// separate path through `importTracks(from:)` + `LibraryTrackMatcher`.
    public static func importSongs(
        from fileURL: URL,
        songsByNormalizedPath: [String: Song]
    ) throws -> Result {
        let tracks = try importTracks(from: fileURL)

        var resolvedSongs: [Song] = []
        var notInLibraryPaths: [String] = []

        for track in tracks {
            guard let path = track.path else { continue }
            let normalized = PathNormalizer.normalize(path)

            if let song = songsByNormalizedPath[normalized] {
                resolvedSongs.append(song)
            } else {
                notInLibraryPaths.append(path)
            }
        }

        return Result(
            resolvedSongs: resolvedSongs,
            notInLibraryPaths: notInLibraryPaths,
            unreadableLines: []
        )
    }

    // MARK: - M3U parsing

    private struct EXTINF {
        let duration: Int?
        let displayName: String?
    }

    private static func parseEXTINF(_ line: String) -> EXTINF? {
        guard let comma = line.firstIndex(of: ",") else {
            return nil
        }

        let prefix = String(line[line.index(line.startIndex, offsetBy: 8)..<comma])
        let display = String(line[line.index(after: comma)...])

        return EXTINF(
            duration: Int(prefix.trimmingCharacters(in: .whitespacesAndNewlines)),
            displayName: display.isEmpty ? nil : display
        )
    }

    /// TandaComposer's own extended export uses `Artist - Title`.
    /// Foreign M3U files are not standardized here, so the parser only
    /// applies this conservative convention. The complete display text is
    /// always retained in `sourceDisplayName`.
    private static func parseDisplayName(_ value: String?) -> (artist: String?, title: String?) {
        guard let value else {
            return (nil, nil)
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, nil)
        }

        guard let separator = trimmed.range(of: " - ") else {
            return (nil, trimmed)
        }

        let artist = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
        let title = String(trimmed[separator.upperBound...]).trimmingCharacters(in: .whitespaces)

        return (
            artist.isEmpty ? nil : artist,
            title.isEmpty ? nil : title
        )
    }

    private static func decodedText(from data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8.hasPrefix("\u{FEFF}") ? String(utf8.dropFirst()) : utf8
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private static func uriScheme(of line: String) -> String? {
        guard let separatorRange = line.range(of: "://") else {
            return nil
        }

        let scheme = line[line.startIndex..<separatorRange.lowerBound]
        guard !scheme.isEmpty,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else {
            return nil
        }

        return String(scheme)
    }

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
