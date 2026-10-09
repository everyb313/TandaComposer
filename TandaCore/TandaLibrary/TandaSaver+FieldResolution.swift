//
//  TandaSaver+FieldResolution.swift
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

// MARK: - Tanda Saver: field resolution (Orchestra / Singer / artist)

extension TandaSaver {

    // MARK: Field Resolution

    static func resolvedFields(
        for songs:
            [Song],
        settings:
            AppSettings
    ) -> ResolvedFields {

        ResolvedFields(

            artist:
                resolvedArtistField(
                    songs.map {
                        $0.resolvedOrchestra(using: settings)
                    }
                ),

            genre:
                resolvedField(
                    songs.map {
                        $0.genre
                    },
                    unknownFallback:
                        "Unknown Genre",
                    variousFallback:
                        "VariousGenres"
                ),

            albumArtist:
                resolvedField(
                    songs.map {
                        $0.resolvedSinger(using: settings)
                    },
                    unknownFallback:
                        // Also used as the Tandas/<Artist>/<...>/
                        // subfolder name (see ensureTandaFolder) —
                        // no special-casing there, so this value
                        // must itself already be filesystem-safe.
                        "unknownOrchestra",
                    variousFallback:
                        "VariousSingers"
                )
        )
    }


    // MARK: Artist Resolution
    //
    // Comparison remains case- and diacritic-insensitive.
    // The original artist string is returned unchanged.
    //
    // This is ONLY for determining whether all tracks have the
    // same artist.

    private static func resolvedArtistField(
        _ values:
            [String?]
    ) -> String {

        let cleanedValues =
            values.compactMap {
                value -> String? in

                let trimmed =
                    value?.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ) ?? ""

                return trimmed.isEmpty
                    ? nil
                    : trimmed
            }


        guard
            !cleanedValues.isEmpty
        else {

            return "Unknown Orchestra"
        }


        let normalizedValues =
            Set(
                cleanedValues.map {
                    normalizedArtistForComparison($0)
                }
            )


        // All artists are considered equal for Tanda generation.
        //
        // IMPORTANT:
        // Return the ORIGINAL artist string.
        // Normalization is applied only when creating the
        // filesystem folder and filename.
        if normalizedValues.count == 1 {

            return cleanedValues[0]
        }


        return "VariousOrchestras"
    }


    // MARK: Artist Comparison Normalization

    /// Used for comparing Artist (Orchestra) values, and also reused
    /// by `resolvedField` for Singer/AlbumArtist and Genre
    /// comparison (see "Generic Field Resolution" below).
    ///
    /// Case and diacritics are ignored here.
    ///
    ///     "Carlos Di Sarli"
    ///     "Carlos Dí Sarli"
    ///
    /// are therefore considered identical.

    static func normalizedArtistForComparison(
        _ artist:
            String
    ) -> String {

        artist
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .folding(
                options:
                    [
                        .caseInsensitive,
                        .diacriticInsensitive
                    ],
                locale:
                    Locale(
                        identifier:
                            "es_ES"
                    )
            )
            .precomposedStringWithCanonicalMapping
    }


    // MARK: Generic Field Resolution
    //
    // Comparison is case- and diacritic-insensitive (same rule as
    // Artist Comparison Normalization above), so e.g. "Podestá" and
    // "Podesta", or "Tango" and "tango", are treated as the same
    // value instead of triggering the various* fallback. The
    // ORIGINAL string (first occurrence) is returned when all
    // values match, exactly like `resolvedArtistField`.

    private static func resolvedField(
        _ values:
            [String?],
        unknownFallback:
            String,
        variousFallback:
            String
    ) -> String {

        let cleanedValues =
            values.compactMap {
                value -> String? in

                let trimmed =
                    value?.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ) ?? ""

                return trimmed.isEmpty
                    ? nil
                    : trimmed
            }


        guard
            !cleanedValues.isEmpty
        else {

            return unknownFallback
        }


        let normalizedValues =
            Set(
                cleanedValues.map {
                    normalizedArtistForComparison($0)
                }
            )


        if normalizedValues.count == 1 {

            return cleanedValues[0]
        }


        return variousFallback
    }
}
