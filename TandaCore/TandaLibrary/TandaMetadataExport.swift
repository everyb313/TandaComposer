//
//  TandaMetadataExport.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 23.08.26.
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


//
//  TandaMetadataExport.swift
//  TandaComposer
//

import Foundation

/// File format for a TandaComposer Tanda.
///
/// A Tanda contains complete Song records, not just references
/// to the Track Library. Therefore a saved Tanda is self-describing.
public struct TandaMetadataExport: Codable {

    public let format: String
    public let version: Int
    public let tandaName: String
    public let savedAt: Date
    public let songs: [Song]

    /// Free-text note the user can edit in the Tanda Library's header
    /// (TandaLibraryView). Optional so existing Tanda files saved
    /// before this field existed still decode fine — Codable's
    /// synthesized init treats a missing key for an Optional property
    /// as `nil`, not a decode failure.
    public let comment: String?

    /// Which TrackLibrary this file's song `id`s were resolved
    /// against when it was last saved — same rationale as
    /// `SetlistMetadataExport.savedAgainstLibraryName`; see that
    /// property's doc comment.
    public let savedAgainstLibraryName: String?

    /// Which tag field the user's "Orchestra" / "Singer" came from when
    /// this file was last written (Settings → Tag Source): "artist",
    /// "albumArtist" or "grouping". The raw tags in `songs` are only
    /// meaningful together with this choice. `nil` for files written
    /// before these fields existed (the convention is unknown then).
    public let orchestraSource: TagSource?
    public let singerSource: TagSource?

    public init(
        tandaName: String,
        songs: [Song],
        savedAt: Date = Date(),
        comment: String? = nil,
        savedAgainstLibraryName: String? = AppPaths.currentLibraryName,
        orchestraSource: TagSource? = nil,
        singerSource: TagSource? = nil
    ) {
        self.format = "TandaComposer Tanda"
        self.version = 1
        self.tandaName = tandaName
        self.savedAt = savedAt
        self.songs = songs
        self.comment = comment
        self.savedAgainstLibraryName = savedAgainstLibraryName
        self.orchestraSource = orchestraSource
        self.singerSource = singerSource
    }
}


// MARK: - Tanda exporter

public enum TandaMetadataExporter {

    /// Exports a Tanda as a self-contained JSON file.
    ///
    /// The order of `songs` is preserved exactly as supplied.
    ///
    /// The header records which tag fields the user's "Orchestra" and
    /// "Singer" came from (`orchestraSource` / `singerSource`). By default
    /// that is the current choice from Settings (see `TandaConventions`),
    /// so every write of a Tanda file — new save, comment, add/remove a
    /// track, rescan — records it.
    public static func export(
        songs: [Song],
        tandaName: String,
        to fileURL: URL,
        savedAt: Date = Date(),
        comment: String? = nil,
        savedAgainstLibraryName: String? = AppPaths.currentLibraryName,
        orchestraSource: TagSource? = TandaConventions.orchestra,
        singerSource: TagSource? = TandaConventions.singer
    ) throws {

        let export =
            TandaMetadataExport(
                tandaName: tandaName,
                songs: songs,
                savedAt: savedAt,
                comment: comment,
                savedAgainstLibraryName: savedAgainstLibraryName,
                orchestraSource: orchestraSource,
                singerSource: singerSource
            )

        let doc =
            JSONValue.object([
                ("format", .string(export.format)),
                ("version", .number(String(export.version))),
                ("tandaName", .string(export.tandaName)),
                ("orchestraSource", .opt(export.orchestraSource?.rawValue)),
                ("singerSource", .opt(export.singerSource?.rawValue)),
                ("savedAgainstLibraryName", .opt(export.savedAgainstLibraryName)),
                ("savedAt", .string(
                    SongMetadataJSON.iso8601String(export.savedAt)
                )),
                ("comment", .opt(export.comment)),
                ("songs", .array(
                    export.songs.map(SongMetadataJSON.orderedValue)
                )),
            ])

        guard let data = doc.serialized().data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        try data.write(
            to: fileURL,
            options: .atomic
        )
    }


    /// Loads a previously saved Tanda JSON file.
    public static func load(
        from fileURL: URL
    ) throws -> TandaMetadataExport {

        let data =
            try Data(contentsOf: fileURL)

        let decoder =
            JSONDecoder()

        decoder.dateDecodingStrategy =
            .iso8601

        return try decoder.decode(
            TandaMetadataExport.self,
            from: data
        )
    }
}
