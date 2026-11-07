//
//  TandaJSONReader.swift
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


// MARK: - Tanda JSON → ImportedTrack
//
// Reads a Tanda file written by TandaComposer (the files in a
// "TandaLibrary (JSON-ZIP)" export) for the "Tandas from ZIP" import.
//
// The tracks are handed over in the SAME shape the text-list import
// produces, because the matcher and `TandaImportResolver.agrees` rely
// on it: `artist` is the ORCHESTRA and `singer` is the SINGER. They are
// read from the tag fields the file's header names:
//
//     "orchestraSource" : "artist" | "albumArtist" | "grouping"
//     "singerSource"    : same
//
// So an orchestra the sender kept in AlbumArtist arrives as the
// orchestra, and the resolver then compares it with whatever field the
// RECEIVER uses for the orchestra — role against role, not field
// against field.
//
// A file without these keys (written by an older version) is read as
// Artist / AlbumArtist, and the import window says so.
//
// Everything else of the song is carried over as it is: title, album,
// year, duration, bpm, key, file name, path and the SHA-256 file hash
// (an exact match of the audio file, whatever the tags say).
//
// Not carried over: `libraryID` — the id belongs to the sender's
// database and is meaningless here.

enum TandaJSONReader {

    /// The "format" value of a Tanda file (see `TandaMetadataExport`).
    static let formatName = "TandaComposer Tanda"

    /// True if the file is a JSON object whose "format" says it is a
    /// TandaComposer Tanda. Any other JSON file in a ZIP is not ours:
    /// it is ignored (like a cover image), not reported as unreadable.
    /// A file that SAYS it is a Tanda but cannot be read is reported.
    static func looksLikeTanda(_ url: URL) -> Bool {

        guard
            let data = try? Data(contentsOf: url),
            let object =
                try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
            let format = object["format"] as? String
        else {
            return false
        }

        return format == formatName
    }

    struct Result {
        let name: String
        let comment: String?
        let tracks: [ImportedTrack]
        /// What the file's header says; nil if it says nothing (older file).
        let orchestraSource: TagSource?
        let singerSource: TagSource?
    }

    static func read(from url: URL) throws -> Result {

        let export = try TandaMetadataExporter.load(from: url)

        let orchestraSource = export.orchestraSource ?? .artist
        let singerSource = export.singerSource ?? .albumArtist

        let tracks =
            export.songs.enumerated().map { index, song in
                importedTrack(
                    from: song,
                    sourceIndex: index,
                    orchestraSource: orchestraSource,
                    singerSource: singerSource
                )
            }

        let trimmedName =
            export.tandaName
                .trimmingCharacters(in: .whitespacesAndNewlines)

        let comment =
            export.comment?
                .trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(
            name:
                trimmedName.isEmpty
                ? url.deletingPathExtension().lastPathComponent
                : trimmedName,
            comment:
                (comment?.isEmpty == false) ? comment : nil,
            tracks: tracks,
            orchestraSource: export.orchestraSource,
            singerSource: export.singerSource
        )
    }

    static func importedTrack(
        from song: Song,
        sourceIndex: Int,
        orchestraSource: TagSource,
        singerSource: TagSource
    ) -> ImportedTrack {

        ImportedTrack(
            sourceIndex: sourceIndex,
            path: song.path,
            filename: song.filename,
            title: song.title,
            artist: clean(song.rawTagValue(for: orchestraSource)),
            album: song.album,
            duration: song.duration,
            bpm: song.bpm,
            key: song.key,
            fileHash: song.fileHash,
            year: song.year,
            singer: clean(song.rawTagValue(for: singerSource))
        )
    }

    private static func clean(_ value: String?) -> String? {

        guard let trimmed =
                value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }

        return trimmed
    }
}


// MARK: - What the import window says about the sender's convention

enum SenderConventionNote {

    /// A short line for the import window, or nil if the ZIP holds no
    /// JSON Tandas (text / M3U8 lists carry no convention).
    static func text(
        for tandas: [SharedTanda],
        ownOrchestra: TagSource,
        ownSinger: TagSource
    ) -> String? {

        let json = tandas.filter { $0.isJSON }

        guard !json.isEmpty else {
            return nil
        }

        let unknown =
            json.filter {
                $0.orchestraSource == nil || $0.singerSource == nil
            }
            .count

        var pairs: [String] = []

        for tanda in json {
            if let o = tanda.orchestraSource, let s = tanda.singerSource {
                let pair = "Orchestra = \(o.displayName), Singer = \(s.displayName)"
                if !pairs.contains(pair) {
                    pairs.append(pair)
                }
            }
        }

        let own =
            "Orchestra = \(ownOrchestra.displayName), "
            + "Singer = \(ownSinger.displayName)"

        var parts: [String] = []

        switch pairs.count {

        case 0:
            parts.append(
                "The sender's Tanda files do not record which tags hold the "
                + "Orchestra and Singer; Artist / AlbumArtist is assumed."
            )

        case 1:
            parts.append("Sender: \(pairs[0]).")

        default:
            parts.append(
                "The Tandas record different conventions: "
                + pairs.joined(separator: "; ")
                + "."
            )
        }

        if unknown > 0 && !pairs.isEmpty {
            parts.append(
                "\(unknown) Tandas record none; Artist / AlbumArtist is assumed for them."
            )
        }

        parts.append("You: \(own). Names are compared by role, not by tag field.")

        return parts.joined(separator: " ")
    }
}
