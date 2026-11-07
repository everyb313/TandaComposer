//
//  SetlistJSONReader.swift
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


// MARK: - Setlist JSON → ImportedTrack
//
// Reads a Setlist file written by TandaComposer (Save Set or
// Tools → Export → "Current Setlist (JSON)…") for Special Import.
//
// Tracks use the same shape as text/M3U8 import: `artist` is the
// ORCHESTRA and `singer` is the SINGER, taken from the tag fields the
// file header names (`orchestraSource` / `singerSource`). Matching is
// role against role. A file without those keys is read as Artist /
// AlbumArtist.
//
// libraryID is not used — it belongs to the sender's database.

enum SetlistJSONReader {

    static let formatName = "TandaComposer Setlist"

    struct Result {
        let name: String
        let tracks: [ImportedTrack]
        /// nil if the file was written before the header recorded it.
        let orchestraSource: TagSource?
        let singerSource: TagSource?
    }

    /// True if the file is a JSON object whose "format" is a Setlist.
    static func looksLikeSetlist(_ url: URL) -> Bool {

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

    static func read(from url: URL) throws -> Result {

        let export =
            try SetlistMetadataExporter.load(from: url)

        guard export.format == formatName else {
            throw SetlistJSONReaderError.notASetlist
        }

        let orchestraSource =
            export.orchestraSource ?? .artist

        let singerSource =
            export.singerSource ?? .albumArtist

        let tracks =
            export.songs.enumerated().map { index, song in
                TandaJSONReader.importedTrack(
                    from: song,
                    sourceIndex: index,
                    orchestraSource: orchestraSource,
                    singerSource: singerSource
                )
            }

        let trimmedName =
            export.setlistName
                .trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(
            name:
                trimmedName.isEmpty
                ? url.deletingPathExtension().lastPathComponent
                : trimmedName,
            tracks: tracks,
            orchestraSource: export.orchestraSource,
            singerSource: export.singerSource
        )
    }

    /// Short line for the Special Import window, or nil when the file
    /// carried no convention (older save) or sources match yours.
    static func conventionNote(
        orchestraSource: TagSource?,
        singerSource: TagSource?,
        ownOrchestra: TagSource,
        ownSinger: TagSource
    ) -> String? {

        let own =
            "You: Orchestra = \(ownOrchestra.displayName), "
            + "Singer = \(ownSinger.displayName)."

        guard
            let o = orchestraSource,
            let s = singerSource
        else {
            return
                "Sender: Orchestra / Singer not recorded (older file); "
                + "Artist / AlbumArtist assumed. " + own
        }

        let sender =
            "Sender: Orchestra = \(o.displayName), "
            + "Singer = \(s.displayName)."

        if o == ownOrchestra, s == ownSinger {
            return sender + " Same as you."
        }

        return
            sender + " " + own
            + " Names are compared by role, not by tag field."
    }
}

enum SetlistJSONReaderError: LocalizedError {

    case notASetlist

    var errorDescription: String? {
        switch self {
        case .notASetlist:
            return "This JSON file is not a TandaComposer Setlist."
        }
    }
}
