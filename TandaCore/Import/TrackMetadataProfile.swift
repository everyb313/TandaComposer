//
//  TrackMetadataProfile.swift
//
//  Copyright © 2026 Hagen Eckert.
//

import Foundation

/// The semantic metadata used by the foreign-library matcher.
///
/// Orchestra and singer are represented as candidate values rather than
/// as a single raw tag. Tango collections commonly put these concepts in
/// Artist, AlbumArtist, or Grouping.
public struct TrackMetadataProfile: Equatable {

    public let title: String?
    public let orchestraValues: [String]
    public let singerValues: [String]
    public let album: String?
    public let duration: Int?
    public let bpm: Double?
    public let key: String?
    public let filename: String?

    public init(
        title: String?,
        orchestraValues: [String],
        singerValues: [String],
        album: String?,
        duration: Int?,
        bpm: Double?,
        key: String?,
        filename: String?
    ) {
        self.title = title
        self.orchestraValues = orchestraValues
        self.singerValues = singerValues
        self.album = album
        self.duration = duration
        self.bpm = bpm
        self.key = key
        self.filename = filename
    }

    /// Builds the profile from a foreign track.
    ///
    /// The configured source is preferred, but all three raw fields remain
    /// available as fallbacks.
    public init(
        importedTrack: ImportedTrack,
        orchestraSource: TagSource = .artist,
        singerSource: TagSource = .albumArtist
    ) {
        let fields = RawTagFields(
            artist: importedTrack.artist,
            albumArtist: importedTrack.albumArtist,
            grouping: importedTrack.grouping
        )

        self.init(
            title: importedTrack.title,
            orchestraValues: Self.roleValues(
                preferred: fields.value(for: orchestraSource),
                fallbacks: fields.allValues
            ),
            singerValues: Self.roleValues(
                preferred: fields.value(for: singerSource),
                fallbacks: fields.allValues
            ),
            album: importedTrack.album,
            duration: importedTrack.duration,
            bpm: importedTrack.bpm,
            key: importedTrack.key,
            filename: importedTrack.filename
        )
    }

    /// Builds the same semantic profile for a current Library song.
    public init(
        song: Song,
        orchestraSource: TagSource = .artist,
        singerSource: TagSource = .albumArtist
    ) {
        let fields = RawTagFields(
            artist: song.artist,
            albumArtist: song.albumArtist,
            grouping: song.grouping
        )

        self.init(
            title: song.title,
            orchestraValues: Self.roleValues(
                preferred: fields.value(for: orchestraSource),
                fallbacks: fields.allValues
            ),
            singerValues: Self.roleValues(
                preferred: fields.value(for: singerSource),
                fallbacks: fields.allValues
            ),
            album: song.album,
            duration: song.duration,
            bpm: song.bpm,
            key: song.key,
            filename: song.filename
        )
    }

    private static func roleValues(
        preferred: String?,
        fallbacks: [String?]
    ) -> [String] {
        var result: [String] = []

        for value in [preferred] + fallbacks {
            guard let value else {
                continue
            }

            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !trimmed.isEmpty else {
                continue
            }

            if !result.contains(
                where: { TrackTextNormalizer.equals($0, trimmed) }
            ) {
                result.append(trimmed)
            }
        }

        return result
    }

    private struct RawTagFields {

        let artist: String?
        let albumArtist: String?
        let grouping: String?

        var allValues: [String?] {
            [
                artist,
                albumArtist,
                grouping
            ]
        }

        func value(for source: TagSource) -> String? {
            switch source {
            case .artist:
                return artist

            case .albumArtist:
                return albumArtist

            case .grouping:
                return grouping
            }
        }
    }
}

/// Conservative normalization for matching.
///
/// It intentionally does not perform aggressive fuzzy substitutions.
/// A false positive is worse than asking the user to choose between
/// two candidates.
public enum TrackTextNormalizer {

    public static func normalize(
        _ value: String?
    ) -> String? {

        guard let value else {
            return nil
        }

        let folded = value
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ],
                locale: .current
            )

        // D’Arienzo / D'Arienzo / D`Arienzo are the same name.
        let unified = folded
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{00B4}", with: "'")
            .replacingOccurrences(of: "`", with: "'")

        let collapsed = unified
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return collapsed.isEmpty ? nil : collapsed
    }

    public static func normalizeFilename(
        _ value: String?
    ) -> String? {

        guard let value else {
            return nil
        }

        let name = URL(fileURLWithPath: value)
            .deletingPathExtension()
            .lastPathComponent

        return normalize(name)
    }

    public static func equals(
        _ lhs: String?,
        _ rhs: String?
    ) -> Bool {

        guard let lhs = normalize(lhs),
              let rhs = normalize(rhs)
        else {
            return false
        }

        return lhs == rhs
    }
}
