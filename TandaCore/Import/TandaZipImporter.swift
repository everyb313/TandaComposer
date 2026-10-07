//
//  TandaZipImporter.swift
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

// MARK: - Model

/// One Tanda file read from a ZIP written by "Export TandaLibrary for
/// Sharing" (`Tandas/<Orchestra>/<Singer>/<Tanda>.txt` or `.m3u8`).
struct SharedTanda: Identifiable {

    let id = UUID()

    /// First folder level inside the ZIP (the orchestra); "" for files
    /// without a folder.
    let folder: String

    /// Folders below it (the singer), joined by "/"; "" if none.
    let subfolder: String

    /// File name without extension.
    let fileName: String

    /// From the "# Tanda:" line, else the file name.
    let name: String

    /// From the "# Comment:" line (text files only).
    let comment: String?

    let tracks: [ImportedTrack]
}

struct SharedTandaScan {

    var tandas: [SharedTanda] = []

    /// Relative paths of files that could not be read.
    var unreadable: [String] = []
}

enum TandaZipError: LocalizedError {

    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .unzipFailed(let message):
            return "The ZIP file could not be opened: \(message)"
        }
    }
}

// MARK: - Reader

/// Reads the Tanda files of a ZIP. Nothing is kept on disk: the ZIP is
/// unpacked into a temporary folder, parsed, and the folder removed.
enum TandaZipImporter {

    static func read(zipURL: URL) throws -> SharedTandaScan {

        let fm = FileManager.default

        let temp =
            fm.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        try fm.createDirectory(
            at: temp,
            withIntermediateDirectories: true
        )

        defer {
            try? fm.removeItem(at: temp)
        }

        try unzip(zipURL, to: temp)

        return scan(folder: temp)
    }

    // MARK: Unzip

    /// Info-ZIP `unzip` drops "../" path components, so an entry cannot
    /// reach outside the temporary folder.
    private static func unzip(
        _ zip: URL,
        to folder: URL
    ) throws {

        let process = Process()

        process.executableURL =
            URL(fileURLWithPath: "/usr/bin/unzip")

        process.arguments = [
            "-qq", "-o",
            zip.path,
            "-x", "__MACOSX/*", "*/__MACOSX/*",
            "-d", folder.path
        ]

        let errorPipe = Pipe()

        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        // 0 = fine, 1 = finished with warnings.
        guard process.terminationStatus <= 1 else {

            let message =
                String(
                    data: errorPipe.fileHandleForReading
                        .readDataToEndOfFile(),
                    encoding: .utf8
                )?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            throw TandaZipError.unzipFailed(
                (message?.isEmpty == false ? message : nil)
                    ?? "unzip failed with status \(process.terminationStatus)"
            )
        }
    }

    // MARK: Scan

    private static func scan(
        folder: URL
    ) -> SharedTandaScan {

        var result = SharedTandaScan()

        let base = folder.resolvingSymlinksInPath().path

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: nil
        ) else {
            return result
        }

        var files: [(url: URL, parts: [String])] = []

        for case let url as URL in enumerator {

            guard ["txt", "m3u8", "m3u"]
                    .contains(url.pathExtension.lowercased()),
                  !url.lastPathComponent.hasPrefix("._")
            else {
                continue
            }

            let path = url.resolvingSymlinksInPath().path

            guard path.hasPrefix(base) else {
                continue
            }

            let parts =
                String(path.dropFirst(base.count))
                    .split(separator: "/")
                    .map(String.init)

            guard !parts.isEmpty,
                  !parts.contains("__MACOSX")
            else {
                continue
            }

            files.append((url, parts))
        }

        // The "Tandas" folder our export puts around everything is
        // dropped. Any other first folder is a real orchestra folder.
        var wrapper: String?

        if files.allSatisfy({
            $0.parts.count >= 2
                && $0.parts[0].caseInsensitiveCompare("Tandas")
                    == .orderedSame
        }) {
            wrapper = "Tandas"
        }

        for file in files {

            var folders = Array(file.parts.dropLast())

            if wrapper != nil, !folders.isEmpty {
                folders.removeFirst()
            }

            let stem =
                file.url.deletingPathExtension().lastPathComponent

            do {

                let tracks: [ImportedTrack]
                var name = stem
                var comment: String?

                if file.url.pathExtension.lowercased() == "txt" {

                    tracks =
                        try TextListImporter.importTracks(
                            from: file.url
                        )

                    let header = readHeader(of: file.url)

                    if let headerName = header.name {
                        name = headerName
                    }

                    comment = header.comment

                } else {

                    tracks =
                        try M3U8Importer.importTracks(
                            from: file.url
                        )
                }

                guard !tracks.isEmpty else {
                    result.unreadable.append(
                        file.parts.joined(separator: "/")
                    )
                    continue
                }

                result.tandas.append(
                    SharedTanda(
                        folder: folders.first ?? "",
                        subfolder:
                            folders.dropFirst()
                                .joined(separator: "/"),
                        fileName: stem,
                        name: name,
                        comment: comment,
                        tracks: tracks
                    )
                )

            } catch {

                result.unreadable.append(
                    file.parts.joined(separator: "/")
                )
            }
        }

        result.tandas.sort {

            let a = $0.folder + "/" + $0.subfolder + "/" + $0.fileName
            let b = $1.folder + "/" + $1.subfolder + "/" + $1.fileName

            return a.localizedStandardCompare(b) == .orderedAscending
        }

        return result
    }

    /// "# Tanda: Name" and "# Comment: Text" lines of a text file.
    private static func readHeader(
        of url: URL
    ) -> (name: String?, comment: String?) {

        guard let data = try? Data(contentsOf: url) else {
            return (nil, nil)
        }

        let text =
            String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "\u{FEFF}", with: "")

        var name: String?
        var comment: String?

        for raw in text.components(separatedBy: .newlines) {

            let line =
                raw.trimmingCharacters(in: .whitespaces)

            guard line.hasPrefix("#") else {
                continue
            }

            let body =
                line.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)

            let lower = body.lowercased()

            if lower.hasPrefix("tanda:") {

                let value =
                    String(body.dropFirst("tanda:".count))
                        .trimmingCharacters(in: .whitespaces)

                if !value.isEmpty {
                    name = value
                }

            } else if lower.hasPrefix("comment:") {

                let value =
                    String(body.dropFirst("comment:".count))
                        .trimmingCharacters(in: .whitespaces)

                if !value.isEmpty {
                    comment = value
                }
            }
        }

        return (name, comment)
    }
}
