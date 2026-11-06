//
//  TandaLibraryJSONExporter.swift
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


// MARK: - TandaLibrary as JSON ZIP
//
// Tools → Export → "TandaLibrary (JSON-ZIP)…"
//
// The Tandas folder is exported AS IT LIES ON DISK:
//
//     Tandas/<Orchestra>/<Singer>/<Tanda>.json
//
// Every file is copied byte for byte — complete song data, file paths
// and all. There is no manifest: each Tanda file records the Orchestra /
// Singer convention in its own header ("orchestraSource",
// "singerSource").
//
// ONE exception: a file written before the header carried the
// convention gets the two missing lines inserted in the COPY (current
// Settings values, right after "tandaName"). Nothing else in the file
// changes, and the original on disk is never touched. If inserting
// would damage the file, the original bytes are copied instead.
//
// This type only fills the staging folder; the caller zips it.

public enum TandaLibraryJSONExporter {

    public struct Summary: Equatable {
        public var tandaCount = 0
        public var folderCount = 0
        /// Files that did not yet record the convention and got it in
        /// the copy.
        public var stampedCount = 0
        /// Files that are not a readable Tanda; they are not exported.
        public var unreadableFiles: [String] = []

        public init() {}
    }


    // MARK: Export

    /// Copies every Tanda file below `tandasRoot` into `stagingRoot`
    /// (same relative folders). `stagingRoot` is created if needed.
    static func export(
        to stagingRoot: URL,
        orchestraSource: TagSource = TandaConventions.orchestra,
        singerSource: TagSource = TandaConventions.singer,
        tandasRoot: URL = AppPaths.tandasFolder
    ) throws -> Summary {

        let fm = FileManager.default

        try fm.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true
        )

        var summary = Summary()

        guard fm.fileExists(atPath: tandasRoot.path),
              let enumerator = fm.enumerator(
                at: tandasRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else {
            return summary
        }

        let files =
            enumerator
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted {
                    $0.path.localizedStandardCompare($1.path)
                        == .orderedAscending
                }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var folders = Set<String>()

        for url in files {

            let relativeFolder =
                relativeFolderPath(of: url, below: tandasRoot)

            let display =
                relativeFolder.isEmpty
                ? url.lastPathComponent
                : relativeFolder + "/" + url.lastPathComponent

            guard
                let data = try? Data(contentsOf: url),
                let tanda = try? decoder.decode(
                    TandaMetadataExport.self,
                    from: data
                )
            else {
                summary.unreadableFiles.append(display)
                continue
            }

            var output = data

            if tanda.orchestraSource == nil || tanda.singerSource == nil,
               let stamped = stampedData(
                    data,
                    original: tanda,
                    orchestra: orchestraSource,
                    singer: singerSource,
                    decoder: decoder
               ) {

                output = stamped
                summary.stampedCount += 1
            }

            var folder = stagingRoot

            if !relativeFolder.isEmpty {
                folder =
                    stagingRoot.appendingPathComponent(
                        relativeFolder,
                        isDirectory: true
                    )
                folders.insert(relativeFolder)
            }

            try fm.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )

            try output.write(
                to: folder.appendingPathComponent(url.lastPathComponent),
                options: .atomic
            )

            summary.tandaCount += 1
        }

        summary.folderCount = folders.count

        return summary
    }


    // MARK: Header stamp (text insertion only)

    /// `data` with the missing convention lines added, or nil if that
    /// is not possible without risk. The result is decoded again and
    /// compared with the original before it is accepted.
    static func stampedData(
        _ data: Data,
        original: TandaMetadataExport,
        orchestra: TagSource,
        singer: TagSource,
        decoder: JSONDecoder
    ) -> Data? {

        guard
            let text = String(data: data, encoding: .utf8),
            let stamped = stampedText(
                text,
                orchestra: orchestra,
                singer: singer
            ),
            let stampedData = stamped.data(using: .utf8),
            let check = try? decoder.decode(
                TandaMetadataExport.self,
                from: stampedData
            ),
            check.tandaName == original.tandaName,
            check.songs.count == original.songs.count,
            check.orchestraSource != nil,
            check.singerSource != nil
        else {
            return nil
        }

        return stampedData
    }

    /// Inserts `"orchestraSource"` / `"singerSource"` right after the
    /// `"tandaName"` line (same indentation) when a key is missing, or
    /// fills in the value when it is `null`. A key that already has a
    /// value is left alone. nil if nothing had to change or the header
    /// has an unexpected shape.
    static func stampedText(
        _ text: String,
        orchestra: TagSource,
        singer: TagSource
    ) -> String? {

        var result = text
        var missing: [(key: String, value: String)] = []
        var changed = false

        for (key, value) in [
            ("orchestraSource", orchestra.rawValue),
            ("singerSource", singer.rawValue)
        ] {

            // present with null -> fill in
            if let range = result.range(
                of: "\"\(key)\"(\\s*:\\s*)null",
                options: .regularExpression
            ) {
                let found = String(result[range])
                let filled =
                    found.replacingOccurrences(
                        of: "null",
                        with: "\"\(value)\""
                    )

                result.replaceSubrange(range, with: filled)
                changed = true
                continue
            }

            // present with a value -> keep
            if result.range(
                of: "\"\(key)\"\\s*:",
                options: .regularExpression
            ) != nil {
                continue
            }

            missing.append((key, value))
        }

        if !missing.isEmpty {

            guard
                let pair = result.range(
                    of: #"[ \t]*"tandaName"\s*:\s*"(?:[^"\\]|\\.)*"\s*,"#,
                    options: .regularExpression
                )
            else {
                return nil
            }

            let pairText = String(result[pair])

            let indent =
                String(pairText.prefix { $0 == " " || $0 == "\t" })

            let insertion =
                missing
                    .map { "\n\(indent)\"\($0.key)\" : \"\($0.value)\"," }
                    .joined()

            result.insert(
                contentsOf: insertion,
                at: pair.upperBound
            )

            changed = true
        }

        return changed ? result : nil
    }


    // MARK: File name (the number counts up)

    /// `<name>.zip` if that is free, otherwise `<name>_2.zip`,
    /// `<name>_3.zip`, … — the first one that does not exist yet.
    /// A name that already ends in `_<number>` continues from there.
    /// The extension is always `.zip`. An existing file is never
    /// overwritten.
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


    // MARK: Helpers

    /// "Biagi/Acuna" for `<root>/Biagi/Acuna/foo.json`, "" for
    /// `<root>/foo.json`.
    private static func relativeFolderPath(
        of file: URL,
        below root: URL
    ) -> String {

        let rootComponents = root.standardizedFileURL
            .resolvingSymlinksInPath()
            .pathComponents

        let folderComponents = file.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .pathComponents

        guard folderComponents.count >= rootComponents.count,
              Array(folderComponents.prefix(rootComponents.count)) == rootComponents
        else {
            return ""
        }

        return folderComponents
            .dropFirst(rootComponents.count)
            .joined(separator: "/")
    }

 
    
}
