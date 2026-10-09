//
//  SongMetadataReader.swift
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

// MARK: - Song metadata reading
//
// Turns an audio file on disk into a `Song` (tags, duration, sample
// rate, gain, hash, filesystem attributes). Used by LibraryScanner
// (import / rescan) and, via `LibraryScanner.readSong`, by the
// Setlist's external-file drop handler.

enum SongMetadataReader {

    // Shared tag-reading logic: reused by SetlistView's external-file
    // drop handler (dragging audio files in from Finder) so there is no
    // second, drift-prone copy of it.
    static func readSong(at url: URL) async throws -> Song {
        let metadata = try await AudioMetadataKit.read(url: url)
        let tags = CanonicalTags.extract(from: metadata)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

        // Duration: FLAC/AIFF previously never surfaced this (their
        // readers parsed sample rate/channels but skipped the
        // total-sample-count field needed for duration) — fixed upstream
        // in AudioTagKit's FLACReader/AIFFReader, so "durationSeconds" now
        // arrives here consistently across all four formats. Update your
        // AudioTagKit copy for this to actually take effect.
        let duration =
            (metadata["durationSeconds"] as? Double)
                .map {
                    Int(
                        $0.rounded()
                    )
                }

        // SHA-256 of the complete file contents.
        //
        // This is calculated when the file is read for import. For an
        // existing library track, the hash is deliberately retained by
        // the upsert logic above until the future rescan implementation
        // decides that the file has changed.
        let fileHash =
            try await FileHasher.sha256(
                fileURL:
                    url
            )

        // Filesystem attributes captured for the future rescan's
        // "did this file actually change?" fast check — must be the
        // REAL on-disk values, not the Song struct's own Date()/0
        // defaults (which previously slipped through here uncaught:
        // every freshly-read Song silently got fileModificationDate-
        // AtScan = "now" and fileSizeAtScan = 0, regardless of the
        // file's real modification date/size, since neither was ever
        // assigned in this initializer call below).
        let modificationDateAtScan =
            attributes[.modificationDate] as? Date
                ?? Date()

        let sizeAtScan =
            attributes[.size] as? Int64
                ?? 0

        let scannedAt =
            Date()

        return Song(
            id:
                nil,
            filename:
                url.lastPathComponent,
            path:
                url.path,
            normalizedPath:
                PathNormalizer.normalize(url),
            title:
                tags.title,
            artist:
                tags.artist,
            albumArtist:
                tags.albumArtist,
            genre:
                tags.genre,
            grouping:
                tags.grouping,
            year:
                Self.extractYear(
                    from:
                        tags.year
                ),
            comment:
                tags.comment,
            fileType:
                url.pathExtension.uppercased(),
            duration:
                duration,
            sampleRate:
                extractSampleRate(
                    from:
                        metadata
                ),
            replayGain:
                extractReplayGain(
                    from:
                        metadata
                ),
            album:
                tags.album,
            key:
                nil, // see doc comment on Song.key
            bpm:
                extractBPM(
                    from:
                        metadata
                ),
            fileSize:
                attributes[.size] as? Int64,
            lastModified:
                (attributes[.modificationDate] as? Date)
                    .map {
                        Int(
                            $0.timeIntervalSince1970
                        )
                    },
            addedToLibrary:
                scannedAt,
            lastLibraryScan:
                scannedAt,
            fileModificationDateAtScan:
                modificationDateAtScan,
            fileSizeAtScan:
                sizeAtScan,
            fileHash:
                fileHash
        )
    }


    /// Best-effort BPM lookup across whichever field happens to carry it —
    /// CanonicalTags doesn't cover BPM, so this reaches into the raw
    /// metadata dictionary AudioMetadataKit.read already returns.
    private static func extractBPM(
        from metadata:
            [String: Any]
    ) -> Double? {

        if let vorbis =
            metadata["vorbisComments"]
                as? [String: String],
           let raw =
            vorbis["BPM"] {

            return Double(
                raw
            )
        }


        if let formatSpecific =
            metadata["formatSpecific"]
                as? [String: [String: Any]] {

            for (_, fields) in formatSpecific {

                if let raw =
                    fields["TBPM"]
                        as? String,
                   let value =
                    Double(
                        raw
                    ) {

                    return value
                }
            }
        }


        return nil
    }


    /// Sample rate lookup. Confirmed against AudioTagKit's actual FLACReader source: it's
    /// nested under "streamInfo" (a dict FLACReader.parseStreamInfo builds from the FLAC
    /// STREAMINFO block), not top-level as originally guessed. Other format readers
    /// (MP3/M4A/AIFF) haven't been checked yet — the top-level and formatSpecific fallbacks
    /// below are kept in case one of them surfaces it differently; tighten this once verified
    /// against each reader's actual source, the way FLAC now is.
    private static func extractSampleRate(
        from metadata:
            [String: Any]
    ) -> Int? {

        if let streamInfo =
            metadata["streamInfo"]
                as? [String: Any] {

            if let rate =
                streamInfo["sampleRate"]
                    as? Int {

                return rate
            }

            if let rate =
                streamInfo["sampleRate"]
                    as? Double {

                return Int(
                    rate.rounded()
                )
            }
        }


        if let rate =
            metadata["sampleRate"]
                as? Int {

            return rate
        }


        if let rate =
            metadata["sampleRate"]
                as? Double {

            return Int(
                rate.rounded()
            )
        }


        if let formatSpecific =
            metadata["formatSpecific"]
                as? [String: [String: Any]] {

            for (_, fields) in formatSpecific {

                if let rate =
                    fields["sampleRate"]
                        as? Int {

                    return rate
                }

                if let rate =
                    fields["sampleRate"]
                        as? Double {

                    return Int(
                        rate.rounded()
                    )
                }
            }
        }


        return nil
    }


    /// R128/ReplayGain track-gain lookup, in dB. Confirmed against AudioTagKit's actual
    /// AIFFReader source: ID3 TXXX user-text frames are surfaced as `"TXXX:<description>"`
    /// (e.g. `"TXXX:REPLAYGAIN_TRACK_GAIN"`) inside `formatSpecific["ID3"]`, not as a plain
    /// `"REPLAYGAIN_TRACK_GAIN"` key — the original exact-match version never found it
    /// because of that prefix. Matching by substring instead sidesteps the prefix (and
    /// MP3's AVFoundation-based reader too, in case it surfaces TXXX differently — not yet
    /// checked). FLAC's Vorbis comments still use a plain, unprefixed key, checked separately.
    private static func extractReplayGain(
        from metadata:
            [String: Any]
    ) -> Double? {

        let candidateNames = [
            "R128_TRACK_GAIN",
            "REPLAYGAIN_TRACK_GAIN"
        ]


        func parse(
            _ raw:
                String
        ) -> Double? {

            let trimmed =
                raw
                    .trimmingCharacters(
                        in:
                            .whitespaces
                    )
                    .replacingOccurrences(
                        of:
                            "dB",
                        with:
                            "",
                        options:
                            .caseInsensitive
                    )
                    .trimmingCharacters(
                        in:
                            .whitespaces
                    )

            return Double(
                trimmed
            )
        }


        if let vorbis =
            metadata["vorbisComments"]
                as? [String: String] {

            for name in candidateNames {

                if let raw =
                    vorbis[name],
                   let value =
                    parse(
                        raw
                    ) {

                    return value
                }
            }
        }


        if let formatSpecific =
            metadata["formatSpecific"]
                as? [String: [String: Any]] {

            for (_, fields) in formatSpecific {

                for (key, rawValue) in fields {

                    guard
                        let raw =
                            rawValue as? String
                    else {
                        continue
                    }


                    let upperKey =
                        key.uppercased()


                    if candidateNames.contains(
                        where: {
                            upperKey.contains(
                                $0
                            )
                        }
                    ),
                       let value =
                        parse(
                            raw
                        ) {

                        return value
                    }
                }
            }
        }


        return nil
    }


    /// Parses a plain year out of whatever CanonicalTags.year contains.
    /// That field can hold a bare year ("1956") or a full ID3v2.4/Vorbis
    /// DATE timestamp ("1956-03-15T00:00:00") depending on the tagger —
    /// only the leading 4 digits are used. Deliberately conservative:
    /// anything that isn't 4 plain digits, or falls outside a plausible
    /// recording-year range, parses to nil rather than storing a guess.
    /// (Not yet checked here: MP3 files using ID3's TDRC frame instead of
    /// TYER don't populate CanonicalTags.year at all today — a separate,
    /// known AudioTagKit gap, out of scope for now since MP3 isn't a
    /// current priority.)
    private static func extractYear(
        from rawYear:
            String?
    ) -> Int? {

        guard
            let rawYear,
            rawYear.count >= 4
        else {
            return nil
        }


        let prefix =
            rawYear.prefix(
                4
            )


        guard
            prefix.allSatisfy(
                \.isNumber
            ),
            let year =
                Int(
                    prefix
                )
        else {
            return nil
        }


        guard
            year > 1860 &&
            year <= 2100
        else {
            return nil
        }


        return year
    }
}
