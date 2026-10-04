//
//  TextListImporter.swift
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

// MARK: - Audio file suffix

/// Knows which trailing ".xyz" really is an audio file suffix.
///
/// Only these are stripped. A title such as "Vol. 2" or "A. Pugliese"
/// must keep everything after its dot, which a generic
/// "delete path extension" would cut off.
public enum AudioFileSuffix {

    public static let known: Set<String> = [
        "flac", "mp3", "m4a", "aac", "alac", "m4b", "m4p",
        "aiff", "aif", "aifc", "wav", "ogg", "opus", "wma",
        "wv", "ape"
    ]

    /// `name` without a known audio suffix, and whether one was there.
    public static func strip(
        _ name: String
    ) -> (stem: String, hadSuffix: Bool) {

        let nsName = name as NSString
        let ext = nsName.pathExtension.lowercased()

        guard !ext.isEmpty, known.contains(ext) else {
            return (name, false)
        }

        return (nsName.deletingPathExtension, true)
    }
}


// MARK: - Text list importer

/// Reads a plain text file with one track per line into neutral
/// `ImportedTrack` records.
///
/// Every line may be, in any mix:
/// - a full path (`/Users/me/Music/Di Sarli - Poema.flac`), a `file://`
///   URL, a `~/…` path, or a relative path with a known audio suffix
/// - a file name with suffix (`Di Sarli - Poema.flac`)
/// - a name without suffix (`Di Sarli - Poema`, or just `Poema`)
///
/// Empty lines and lines starting with `#` are ignored. Nothing is
/// resolved against the Library here.
public enum TextListImporter {

    public static func importTracks(
        from fileURL: URL
    ) throws -> [ImportedTrack] {

        let data = try Data(contentsOf: fileURL)

        return parse(
            text: decodedText(from: data),
            baseDirectory: fileURL.deletingLastPathComponent()
        )
    }

    public static func parse(
        text: String,
        baseDirectory: URL?
    ) -> [ImportedTrack] {

        let lines =
            text.components(separatedBy: .newlines)
                .map {
                    unquoted(
                        $0.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    )
                }

        let order = declaredOrder(in: lines)

        let candidates =
            lines.filter {
                !$0.isEmpty
                    && !$0.hasPrefix("#")
                    && !isStructureLine($0)
            }

        // A list whose tracks are numbered ("1. …") is a document with
        // headings, remarks and cortinas in between. Then only the
        // numbered lines (and explicit paths / file names) are tracks.
        let numbered =
            candidates.filter { hasListNumber($0) }.count

        let numberedMode =
            numbered >= 3
            && numbered * 10 >= candidates.count * 3

        var results: [ImportedTrack] = []
        var sourceIndex = 0

        for line in candidates {

            if numberedMode, !isExplicitTrackLine(line) {
                continue
            }

            let location = locate(
                line,
                baseDirectory: baseDirectory
            )

            guard !location.name.isEmpty else {
                continue
            }

            let split = AudioFileSuffix.strip(location.name)

            guard !split.stem.isEmpty else {
                continue
            }

            let reading = interpret(split.stem, order: order)

            results.append(
                ImportedTrack(
                    sourceIndex: sourceIndex,
                    path: location.path,
                    filename: split.hadSuffix ? location.name : nil,
                    title: reading.title,
                    artist: reading.artist,
                    sourceDisplayName: location.name,
                    year: reading.year,
                    singer: reading.singer
                )
            )

            sourceIndex += 1
        }

        return results
    }

    // MARK: - Line classification

    private struct Location {
        let path: String?
        let name: String
    }

    private static func locate(
        _ line: String,
        baseDirectory: URL?
    ) -> Location {

        // file:// URL.
        if line.lowercased().hasPrefix("file://") {

            let url =
                URL(string: line)
                ?? URL(
                    string: line.replacingOccurrences(
                        of: " ",
                        with: "%20"
                    )
                )

            if let url, url.isFileURL {

                return Location(
                    path: url.path,
                    name: url.lastPathComponent
                )
            }
        }

        // ~/… path.
        if line.hasPrefix("~") {

            let expanded =
                (line as NSString).expandingTildeInPath

            if expanded.hasPrefix("/") {

                return Location(
                    path: expanded,
                    name: (expanded as NSString).lastPathComponent
                )
            }
        }

        // Absolute path.
        if line.hasPrefix("/") {

            return Location(
                path: line,
                name: (line as NSString).lastPathComponent
            )
        }

        // Windows-style path: only the file name is of any use here.
        if isWindowsPath(line) {

            let name =
                line
                    .split(
                        whereSeparator: { $0 == "\\" || $0 == "/" }
                    )
                    .last
                    .map(String.init)
                    ?? line

            return Location(path: nil, name: name)
        }

        // Relative path — only when its last component really is an
        // audio file. Otherwise a "/" is part of a title.
        if line.contains("/") {

            let last = (line as NSString).lastPathComponent

            if AudioFileSuffix.strip(last).hadSuffix {

                let resolved =
                    baseDirectory?
                        .appendingPathComponent(line)
                        .standardizedFileURL
                        .path

                return Location(path: resolved, name: last)
            }
        }

        // Plain name.
        return Location(path: nil, name: line)
    }

    private static func isWindowsPath(_ line: String) -> Bool {

        if line.contains("\\") {
            return true
        }

        return line.range(
            of: #"^[A-Za-z]:[\\/]"#,
            options: .regularExpression
        ) != nil
    }

    private static func unquoted(_ line: String) -> String {

        guard line.count >= 2,
              let first = line.first,
              let last = line.last,
              first == last,
              first == "\"" || first == "'"
        else {
            return line
        }

        return String(line.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Structure lines

    /// Lines that structure a list but are no tracks: "[Tanda 1: …]"
    /// headings, "--- Cortina ---" separators, "--> remark" lines,
    /// "TANDA 2: …" / "CORTINA 3 (…)" headings and "Orchester: …"
    /// style labels.
    private static func isStructureLine(_ line: String) -> Bool {

        if line.hasPrefix("["), line.hasSuffix("]") {
            return true
        }

        let patterns = [
            #"^[-=*_~\x{2013}\x{2014}]{3,}"#,
            #"^[-=]+>"#,
            #"^(?:tanda|cortina|das finale)\b"#,
            #"^(?:format|struktur|structure|orchester|orchestra|orquesta|ablauf|hinweis|notiz|notes?|datum|date|dj|ort|event|setlist|playlist)\s*:"#
        ]

        return patterns.contains {
            line.range(
                of: $0,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
    }

    // MARK: - Numbered lists

    private static let listNumberPattern =
        #"^\s*\d{1,3}(?:\s*[.)]\s*(?=\D)|\s*-\s+)"#

    private static func hasListNumber(_ line: String) -> Bool {

        line.range(
            of: listNumberPattern,
            options: .regularExpression
        ) != nil
    }

    /// In a numbered list: lines that are tracks even without a number.
    private static func isExplicitTrackLine(_ line: String) -> Bool {

        hasListNumber(line)
            || line.hasPrefix("/")
            || line.hasPrefix("~")
            || line.lowercased().hasPrefix("file://")
            || isWindowsPath(line)
            || AudioFileSuffix.strip(line).hadSuffix
    }

    // MARK: - Name order

    private enum NameOrder {
        case artistFirst
        case titleFirst
    }

    /// Honors a declaration such as "Format: Songname - Interpret".
    /// Without one the order is "Artist - Title". The Library match
    /// corrects single lines that are the other way round anyway.
    private static func declaredOrder(
        in lines: [String]
    ) -> NameOrder {

        let titleWords =
            ["song", "titel", "title", "track", "st\u{00FC}ck", "stueck"]

        let artistWords =
            ["interpret", "artist", "orchester", "orchestra",
             "orquesta", "k\u{00FC}nstler", "kuenstler"]

        for line in lines {

            guard let content = capture(
                #"^(?:format|reihenfolge|order)\s*:\s*(.+)$"#,
                in: line
            ) else {
                continue
            }

            let parts =
                content
                    .replacingOccurrences(of: " \u{2013} ", with: " - ")
                    .replacingOccurrences(of: " \u{2014} ", with: " - ")
                    .components(separatedBy: " - ")

            guard parts.count >= 2 else {
                continue
            }

            let first = parts[0].lowercased()

            if artistWords.contains(where: { first.contains($0) }) {
                return .artistFirst
            }

            if titleWords.contains(where: { first.contains($0) }) {
                return .titleFirst
            }
        }

        return .artistFirst
    }

    // MARK: - Line reading

    private struct Reading {
        var artist: String?
        var title: String
        var year: Int?
        var singer: String?
    }

    /// "1. Juan D'Arienzo - Paciencia (Gesang: Enrique Carbel) (1937)"
    /// → artist "Juan D'Arienzo", title "Paciencia",
    ///   singer "Enrique Carbel", year 1937.
    ///
    /// Only a leading list number and trailing brackets that are
    /// recognizably a year or a singer are taken out. Any other
    /// bracket, e.g. "(Remastered)", stays in the title.
    private static func interpret(
        _ stem: String,
        order: NameOrder
    ) -> Reading {

        var text =
            stem.trimmingCharacters(in: .whitespacesAndNewlines)

        // Leading list number: "1. ", "12) ", "01 - ".
        let withoutNumber =
            text.replacingOccurrences(
                of: listNumberPattern,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !withoutNumber.isEmpty {
            text = withoutNumber
        }

        // Trailing "(…)" / "[…]" groups.
        var year: Int?
        var singer: String?

        for _ in 0..<4 {

            guard let range = text.range(
                of: #"\s*[(\[][^()\[\]]*[)\]]\s*$"#,
                options: .regularExpression
            ) else {
                break
            }

            let raw =
                String(text[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

            let content =
                String(raw.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)

            var rest = text
            rest.removeSubrange(range)

            rest = rest.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !rest.isEmpty else {
                break
            }

            if year == nil,
               content.range(
                    of: #"^(?:18|19|20)\d{2}$"#,
                    options: .regularExpression
               ) != nil
            {
                year = Int(content)
                text = rest

            } else if singer == nil,
                      let name = singerName(in: content)
            {
                singer = name
                text = rest

            } else {
                break
            }
        }

        // "Artist - Title".
        let unified =
            text
                .replacingOccurrences(of: " \u{2013} ", with: " - ")
                .replacingOccurrences(of: " \u{2014} ", with: " - ")

        if let dash = unified.range(of: " - ") {

            let artist =
                String(unified[..<dash.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

            let title =
                String(unified[dash.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

            if !artist.isEmpty, !title.isEmpty {

                // "Artist - Title", or "Title - Artist" when the file
                // says so; the parts are named by position here.
                let swapped = order == .titleFirst

                return Reading(
                    artist: swapped ? title : artist,
                    title: swapped ? artist : title,
                    year: year,
                    singer: singer
                )
            }
        }

        return Reading(
            artist: nil,
            title: text,
            year: year,
            singer: singer
        )
    }

    /// "Gesang: Enrique Carbel" → "Enrique Carbel".
    private static func singerName(in content: String) -> String? {

        let pattern =
            #"^(?:gesang|vocals?|vocalist|voc\.?|singer|s\x{00E4}nger(?:in)?|saenger(?:in)?|cantor|canta|cantante|sung by)\s*[:\-]?\s*(.+)$"#

        guard let found = capture(pattern, in: content) else {
            return nil
        }

        let name =
            found.trimmingCharacters(in: .whitespacesAndNewlines)

        return name.isEmpty ? nil : name
    }

    /// First capture group of a case-insensitive match, if any.
    private static func capture(
        _ pattern: String,
        in text: String
    ) -> String? {

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let whole = NSRange(text.startIndex..., in: text)

        guard let match = regex.firstMatch(
            in: text,
            options: [],
            range: whole
        ),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[range])
    }

    // MARK: - Decoding

    private static func decodedText(from data: Data) -> String {

        if data.starts(with: [0xFF, 0xFE])
            || data.starts(with: [0xFE, 0xFF]),
           let utf16 = String(data: data, encoding: .utf16)
        {
            return utf16
        }

        if let utf8 = String(data: data, encoding: .utf8) {

            return utf8.hasPrefix("\u{FEFF}")
                ? String(utf8.dropFirst())
                : utf8
        }

        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}
