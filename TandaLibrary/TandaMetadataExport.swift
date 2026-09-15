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

    public init(
        tandaName: String,
        songs: [Song],
        savedAt: Date = Date(),
        comment: String? = nil,
        savedAgainstLibraryName: String? = AppPaths.currentLibraryName
    ) {
        self.format = "TandaComposer Tanda"
        self.version = 1
        self.tandaName = tandaName
        self.savedAt = savedAt
        self.songs = songs
        self.comment = comment
        self.savedAgainstLibraryName = savedAgainstLibraryName
    }
}


// MARK: - Tanda exporter

public enum TandaMetadataExporter {

    /// Exports a Tanda as a self-contained JSON file.
    ///
    /// The order of `songs` is preserved exactly as supplied.
    public static func export(
        songs: [Song],
        tandaName: String,
        to fileURL: URL,
        savedAt: Date = Date(),
        comment: String? = nil,
        savedAgainstLibraryName: String? = AppPaths.currentLibraryName
    ) throws {

        let export =
            TandaMetadataExport(
                tandaName: tandaName,
                songs: songs,
                savedAt: savedAt,
                comment: comment,
                savedAgainstLibraryName: savedAgainstLibraryName
            )

        let doc =
            JSONValue.object([
                ("format", .string(export.format)),
                ("version", .number(String(export.version))),
                ("tandaName", .string(export.tandaName)),
                ("savedAt", .string(
                    SongMetadataJSON.iso8601String(export.savedAt)
                )),
                ("comment", .opt(export.comment)),
                ("savedAgainstLibraryName", .opt(export.savedAgainstLibraryName)),
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
