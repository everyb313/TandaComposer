//
//  TandaLibraryExporter.swift
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

// MARK: - Format

/// How the Tandas are written for sharing.
public enum TandaExportFormat {

    /// One text file per Tanda, one track per line:
    /// `1. Orchestra - Title (Singer: Name)`. Readable by people and
    /// by the text import ("Import Setlist (Pick Tracks)").
    case text

    /// One M3U8 playlist per Tanda with bare file names (no folders),
    /// for other players. Carries the orchestra and the title only.
    case m3u8

    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .m3u8: return "m3u8"
        }
    }
}

// MARK: - Result

public struct TandaExportSummary {

    public var tandaCount = 0
    public var folderCount = 0
    public var trackCount = 0

    /// Tracks the current TrackLibrary does not know. Their tags come
    /// from the saved Tanda file.
    public var notInLibraryCount = 0

    /// Tracks the Library knows but whose file is missing on disk.
    public var missingFileCount = 0

    /// Tanda files that could not be read (relative paths).
    public var unreadableFiles: [String] = []
}

public enum TandaExportError: LocalizedError {

    case zipFailed(String)

    public var errorDescription: String? {
        switch self {
        case .zipFailed(let message):
            return "The ZIP file could not be created: \(message)"
        }
    }
}

// MARK: - Exporter

/// Exports the whole TandaLibrary (`Tandas/<Folder>/<Tanda>.json`) as
/// one plain file per Tanda, keeping the folder structure.
///
/// Read-only: nothing in the TandaLibrary or the audio files is
/// changed. Tags are taken from the current TrackLibrary where the
/// track is known there (so edited tags are exported), otherwise from
/// the saved Tanda.
public enum TandaLibraryExporter {

    /// Writes the files into `stagingFolder` (which must exist).
    public static func export(
        to stagingFolder: URL,
        format: TandaExportFormat,
        orchestraSource: TagSource,
        singerSource: TagSource,
        songsByID: [Int64: Song],
        songsByPath: [String: Song],
        missingSongIDs: Set<Int64>
    ) throws -> TandaExportSummary {

        let fm = FileManager.default
        let root = AppPaths.tandasFolder
        var summary = TandaExportSummary()

        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(
                  at: root,
                  includingPropertiesForKeys: nil
              )
        else {
            return summary
        }

        let files = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted {
                $0.path.localizedStandardCompare($1.path)
                    == .orderedAscending
            }

        var folders = Set<String>()

        for url in files {

            let relativeFolder =
                relativeFolderPath(of: url, below: root)

            let export: TandaMetadataExport

            do {
                export = try TandaMetadataExporter.load(from: url)
            } catch {
                summary.unreadableFiles.append(
                    relativeFolder.isEmpty
                        ? url.lastPathComponent
                        : relativeFolder + "/" + url.lastPathComponent
                )
                continue
            }

            // IDs belong to one database: trust them only when the
            // Tanda was saved against the active TrackLibrary.
            let trustID =
                export.savedAgainstLibraryName
                    == AppPaths.currentLibraryName

            var songs: [Song] = []

            for saved in export.songs {

                let resolution = LibraryReferenceResolver.resolve(
                    saved,
                    byID: songsByID,
                    byPath: songsByPath,
                    missingSongIDs: missingSongIDs,
                    trustID: trustID
                )

                if let live = resolution.live {

                    songs.append(live)

                    if resolution.isMissing {
                        summary.missingFileCount += 1
                    }

                } else {

                    songs.append(saved)
                    summary.notInLibraryCount += 1
                }
            }

            let data: Data

            switch format {

            case .text:
                data = textData(
                    tandaName: export.tandaName,
                    comment: export.comment,
                    songs: songs,
                    orchestraSource: orchestraSource,
                    singerSource: singerSource
                )

            case .m3u8:
                data = m3u8Data(
                    songs: songs,
                    orchestraSource: orchestraSource
                )
            }

            var outFolder = stagingFolder

            if !relativeFolder.isEmpty {

                outFolder = outFolder.appendingPathComponent(
                    relativeFolder,
                    isDirectory: true
                )

                folders.insert(relativeFolder)
            }

            try fm.createDirectory(
                at: outFolder,
                withIntermediateDirectories: true
            )

            let stem =
                url.deletingPathExtension().lastPathComponent

            try data.write(
                to: outFolder
                    .appendingPathComponent(stem)
                    .appendingPathExtension(format.fileExtension),
                options: .atomic
            )

            summary.tandaCount += 1
            summary.trackCount += songs.count
        }

        summary.folderCount = folders.count

        return summary
    }

    // MARK: - ZIP

    /// Zips `folder` (kept as the single top-level folder of the
    /// archive) into `destination`, replacing an existing file.
    public static func zip(
        folder: URL,
        to destination: URL
    ) throws {

        if FileManager.default.fileExists(
            atPath: destination.path
        ) {
            try FileManager.default.removeItem(at: destination)
        }

        let process = Process()

        process.executableURL =
            URL(fileURLWithPath: "/usr/bin/ditto")

        process.arguments = [
            "-c", "-k",
            "--sequesterRsrc",
            "--keepParent",
            folder.path,
            destination.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {

            let message =
                String(
                    data: errorPipe.fileHandleForReading
                        .readDataToEndOfFile(),
                    encoding: .utf8
                )
                ?? "ditto failed with status \(process.terminationStatus)"

            throw TandaExportError.zipFailed(message)
        }
    }

    // MARK: - Text

    private static func textData(
        tandaName: String,
        comment: String?,
        songs: [Song],
        orchestraSource: TagSource,
        singerSource: TagSource
    ) -> Data {

        var lines: [String] = []

        // Lines starting with "#" are ignored by the text import.
        if let name = oneLine(tandaName) {
            lines.append("# Tanda: \(name)")
        }

        if let comment {

            let parts =
                comment
                    .components(separatedBy: .newlines)
                    .compactMap { oneLine($0) }

            if !parts.isEmpty {
                lines.append(
                    "# Comment: " + parts.joined(separator: " / ")
                )
            }
        }

        for (index, song) in songs.enumerated() {

            lines.append(
                "\(index + 1). "
                + trackLine(
                    song,
                    orchestraSource: orchestraSource,
                    singerSource: singerSource
                )
            )
        }

        return (lines.joined(separator: "\n") + "\n")
            .data(using: .utf8) ?? Data()
    }

    /// "Juan D'Arienzo - Paciencia (Singer: Enrique Carbel)".
    private static func trackLine(
        _ song: Song,
        orchestraSource: TagSource,
        singerSource: TagSource
    ) -> String {

        let orchestra =
            oneLine(value(of: song, for: orchestraSource))

        let singer =
            oneLine(value(of: song, for: singerSource))

        let title =
            oneLine(song.title)
            ?? oneLine(AudioFileSuffix.strip(song.filename).stem)
            ?? song.filename

        var line =
            orchestra.map { "\($0) - \(title)" } ?? title

        if let singer, singer != orchestra {
            line += " (Singer: \(singer))"
        }

        return line
    }

    // MARK: - M3U8

    private static func m3u8Data(
        songs: [Song],
        orchestraSource: TagSource
    ) -> Data {

        let shared = songs.map { song -> Song in

            var copy = song

            // Bare file name: no folders of this computer are given
            // away, and the importer matches by file name anyway.
            copy.path = song.filename

            // The EXTINF line shows "artist - title".
            copy.artist = value(of: song, for: orchestraSource)

            return copy
        }

        return M3U8Exporter.render(
            songs: shared,
            pathStyle: .absolute,
            extended: true
        )
    }

    // MARK: - Helpers

    private static func value(
        of song: Song,
        for source: TagSource
    ) -> String? {

        switch source {
        case .artist: return song.artist
        case .albumArtist: return song.albumArtist
        case .grouping: return song.grouping
        }
    }

    /// Single line, white space collapsed; nil when nothing is left.
    private static func oneLine(_ value: String?) -> String? {

        guard let value else {
            return nil
        }

        let collapsed =
            value
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

        return collapsed.isEmpty ? nil : collapsed
    }

    /// "Biagi" for `<root>/Biagi/foo.json`, "" for `<root>/foo.json`.
    private static func relativeFolderPath(
        of file: URL,
        below root: URL
    ) -> String {

        let folder = file.deletingLastPathComponent().path

        guard folder.hasPrefix(root.path) else {
            return ""
        }

        return String(folder.dropFirst(root.path.count))
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
    }
}
