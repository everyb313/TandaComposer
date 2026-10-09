//
//  TandaSaver+Naming.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 25.08.26.
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

// MARK: - Tanda Saver: naming (suggested name, normalization, safe filenames)

extension TandaSaver {

    // MARK: Suggested Name
    //
    // <normalized Artist>_<normalized Genre>_<normalized AlbumArtist>
    //
    // IMPORTANT:
    // Diacritics are removed, but capitalization is preserved.
    //
    // Example:
    //
    //     Carlos Dí Sarli
    //     Tángo
    //     Carlos Di Sarli
    //
    // becomes:
    //
    //     Carlos Di Sarli_Tango_Carlos Di Sarli

    static func suggestedName(
        fields:
            ResolvedFields,
        availableIn folder:
            URL,
        excluding excludedURL:
            URL? = nil
    ) -> String {

        let base =
            [
                normalizedFileNameComponent(
                    commaTruncated(
                        fields.artist
                    )
                ),

                normalizedFileNameComponent(
                    fields.genre
                ),

                normalizedFileNameComponent(
                    commaTruncated(
                        fields.albumArtist
                    )
                ),
            ]
            .joined(
                separator:
                    "_"
            )


        return firstAvailableName(
            base:
                base,
            in:
                folder,
            excluding:
                excludedURL
        )
    }


    // MARK: Filename / Folder Normalization
    //
    // THIS is the important part for Save.
    //
    // Unlike normalizedArtistForComparison(),
    // this function DOES NOT use .caseInsensitive.
    //
    // Therefore:
    //
    //     Rodríguez -> Rodriguez
    //     Tángo     -> Tango
    //     Carlos Dí Sarli -> Carlos Di Sarli
    //
    // while:
    //
    //     TANGO -> TANGO
    //     tango -> tango
    //     Tango -> Tango
    //
    // The original capitalization is preserved.

    static func normalizedFileNameComponent(
        _ value:
            String
    ) -> String {

        let normalized =
            value
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .folding(
                    options:
                        [
                            .diacriticInsensitive
                        ],
                    locale:
                        Locale(
                            identifier:
                                "es_ES"
                        )
                )
                .precomposedStringWithCanonicalMapping


        return safeFileName(
            normalized
        )
    }


    // MARK: First Available Name

    /// `base` itself if `<base>.json` doesn't exist yet in `folder`;
    /// otherwise `<base>_2`, `<base>_3`, ... — the first ordinal whose
    /// file doesn't already exist.
    ///
    /// `excludedURL`, when given, is never treated as an existing
    /// collision — used by `resolvedLocation(for:settings:excluding:)`
    /// so a Tanda whose songs haven't actually changed doesn't
    /// collide with ITS OWN current file and get offered a pointless
    /// "_2" rename.

    private static func firstAvailableName(
        base:
            String,
        in folder:
            URL,
        excluding excludedURL:
            URL? = nil
    ) -> String {

        let excludedPath =
            excludedURL?.standardizedFileURL.path

        func exists(
            _ name:
                String
        ) -> Bool {

            let candidate =
                folder
                    .appendingPathComponent(
                        name,
                        isDirectory:
                            false
                    )
                    .appendingPathExtension(
                        "json"
                    )

            if candidate.standardizedFileURL.path
                == excludedPath {

                return false
            }

            return FileManager.default.fileExists(
                atPath:
                    candidate.path
            )
        }


        guard exists(base) else {

            return base
        }


        var ordinal = 2

        while exists(
            "\(base)_\(ordinal)"
        ) {

            ordinal += 1
        }


        return "\(base)_\(ordinal)"
    }


    // MARK: Safe Filename

    private static func safeFileName(
        _ name:
            String
    ) -> String {

        let trimmed =
            name.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )


        if trimmed.isEmpty {

            return "Untitled Tanda"
        }


        return trimmed
            .replacingOccurrences(
                of:
                    "/",
                with:
                    "-"
            )
            .replacingOccurrences(
                of:
                    ":",
                with:
                    "-"
            )
    }
}
