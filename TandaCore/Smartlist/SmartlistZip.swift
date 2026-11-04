//
//  SmartlistZip.swift
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


// MARK: - Smartlist ZIP
//
// Tools → Export → "Smartlists (ZIP)…" / Tools → Import →
// "Smartlists (ZIP)…" (and the same two items in the Smartlists menu).
//
// The ZIP holds the complete Smartlist tree below ONE top-level folder
// named "Smartlists" — the same tree the former folder export wrote.
// Import hands the CONTENTS of that folder to `SmartlistStore.importAll`,
// which puts them into the internal "Imported" folder, exactly as before.
//
// An export never overwrites a ZIP: `firstFreeURL(for:)` counts the
// number up. Backup / Restore is a separate feature and is not touched.

public enum SmartlistZipError: LocalizedError {

    case unzipFailed(String)
    case noSmartlistsInZip

    public var errorDescription: String? {
        switch self {
        case .unzipFailed(let message):
            return "The ZIP file could not be opened: \(message)"
        case .noSmartlistsInZip:
            return "This ZIP file does not contain any Smartlists."
        }
    }
}


public enum SmartlistZip {

    /// `<name>.zip` if that is free, otherwise `<name>_2.zip`,
    /// `<name>_3.zip`, … — the first one that does not exist yet.
    /// A name that already ends in `_<number>` continues from there
    /// (`Smartlists_2.zip` taken -> `Smartlists_3.zip`). The extension
    /// is always `.zip`.
    public static func firstFreeURL(for url: URL) -> URL {

        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent

        let first =
            folder
                .appendingPathComponent(stem)
                .appendingPathExtension("zip")

        guard fm.fileExists(atPath: first.path) else {
            return first
        }

        var base = stem
        var number = 2

        if let range = stem.range(of: #"_[0-9]+$"#, options: .regularExpression),
           let n = Int(stem[range].dropFirst()) {

            base = String(stem[..<range.lowerBound])
            number = n + 1
        }

        while true {

            let candidate =
                folder
                    .appendingPathComponent("\(base)_\(number)")
                    .appendingPathExtension("zip")

            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }

            number += 1
        }
    }


    // MARK: Export

    /// `copyTree` must copy the complete Smartlist tree to the folder it
    /// is given (a not-yet-existing folder) — in the app that is
    /// `SmartlistStore.exportAll(to:)`. The result is zipped into
    /// `destination` with that folder, named "Smartlists", as the single
    /// top-level folder. The caller passes a free URL (see
    /// `firstFreeURL(for:)`); an existing file there would be replaced.
    public static func export(
        copyTree: (URL) throws -> Void,
        to destination: URL
    ) throws {

        let fm = FileManager.default

        let temp =
            fm.temporaryDirectory
                .appendingPathComponent(
                    "TandaComposer-SmartlistZip-\(UUID().uuidString)",
                    isDirectory: true
                )

        try fm.createDirectory(
            at: temp,
            withIntermediateDirectories: true
        )

        defer {
            try? fm.removeItem(at: temp)
        }

        let tree =
            temp.appendingPathComponent("Smartlists", isDirectory: true)

        try copyTree(tree)

        try TandaLibraryExporter.zip(
            folder: tree,
            to: destination
        )
    }


    // MARK: Import

    /// Unzips `zipURL` into a temporary folder and calls `body` with
    /// the folder whose CONTENTS are the Smartlist tree: the single
    /// top-level folder of the ZIP, or the unzipped folder itself if
    /// the ZIP has no such folder. The temporary files are removed
    /// afterwards.
    ///
    /// `body` is only called if the ZIP really contains Smartlist files
    /// (`.json`), so a wrong ZIP changes nothing.
    public static func importTree<T>(
        from zipURL: URL,
        _ body: (URL) throws -> T
    ) throws -> T {

        let fm = FileManager.default

        let temp =
            fm.temporaryDirectory
                .appendingPathComponent(
                    "TandaComposer-SmartlistZip-\(UUID().uuidString)",
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

        let items =
            (try? fm.contentsOfDirectory(
                at: temp,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

        var root = temp

        if items.count == 1,
           (try? items[0].resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory == true {

            root = items[0]
        }

        guard containsSmartlistFile(in: root) else {
            throw SmartlistZipError.noSmartlistsInZip
        }

        return try body(root)
    }

    private static func containsSmartlistFile(in folder: URL) -> Bool {

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let url as URL in enumerator
        where url.pathExtension.lowercased() == "json" {
            return true
        }

        return false
    }

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

            throw SmartlistZipError.unzipFailed(
                (message?.isEmpty == false ? message : nil)
                    ?? "unzip failed with status \(process.terminationStatus)"
            )
        }
    }
}
