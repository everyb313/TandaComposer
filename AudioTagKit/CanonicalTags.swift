//
//  CanonicalTags.swift
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

/// Format-independent view of the handful of tags audiotag4 can write.
/// Used by `copy-tags` (reads these off the source file) and by `dedup`
/// (fingerprints on title/artist).
public struct CanonicalTags {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var genre: String?
    public var track: String?
    public var year: String?
    public var grouping: String?
    public var comment: String?

    /// albumArtist and grouping are deliberately NOT carried into
    /// TagChanges — the writers (FLACWriter/ID3Writer/AIFFWriter/
    /// MP4TagWriter) don't support writing them yet, so these are
    /// read-only additions for now.
    public func asTagChanges() -> TagChanges {
        TagChanges(title: title, artist: artist, album: album, genre: genre, track: track, year: year, comment: comment)
    }

    public static func extract(from metadata: [String: Any]) -> CanonicalTags {
        var tags = CanonicalTags()

        if let vorbis = metadata["vorbisComments"] as? [String: String] {
            tags.title = vorbis["TITLE"]
            tags.artist = vorbis["ARTIST"]
            tags.album = vorbis["ALBUM"]
            // Real-world taggers disagree on the field name here — checked
            // in order of how common each spelling actually is.
            tags.albumArtist = vorbis["ALBUMARTIST"] ?? vorbis["ALBUM ARTIST"] ?? vorbis["ALBUM_ARTIST"]
            tags.genre = vorbis["GENRE"]
            tags.track = vorbis["TRACKNUMBER"]
            // "DATE" is the Vorbis-comment convention, but plenty of
            // FLAC taggers write a bare year under "YEAR" instead —
            // same reasoning as the albumArtist fallback above. Without
            // this, FLAC files tagged that way got a nil year while
            // AIFF's ID3 (TYER) mapping worked fine, so any smart
            // playlist rule on Year silently excluded every FLAC track.
            tags.year = vorbis["DATE"] ?? vorbis["YEAR"]
            tags.comment = vorbis["COMMENT"]
            tags.grouping = vorbis["GROUPING"]
            return tags
        }

        if let common = metadata["common"] as? [String: Any] {
            tags.title = common["title"] as? String
            tags.artist = common["artist"] as? String
            tags.album = common["albumName"] as? String
            tags.comment = common["description"] as? String
        }

        // Genre/track/year/albumArtist/grouping usually live in
        // format-specific metadata (ID3 or iTunes atoms), not
        // AVFoundation's commonMetadata — there is no AVMetadataCommonKey
        // for album artist at all, on any format, which is exactly why
        // this was missed originally.
        if let formatSpecific = metadata["formatSpecific"] as? [String: [String: Any]] {
            for (_, fields) in formatSpecific {
                if tags.genre == nil { tags.genre = (fields["\u{a9}gen"] as? String) ?? (fields["TCON"] as? String) }
                if tags.year == nil { tags.year = (fields["\u{a9}day"] as? String) ?? (fields["TYER"] as? String) }
                if tags.track == nil { tags.track = fields["TRCK"] as? String }
                // "aART" is iTunes/MP4's album-artist atom (distinct from
                // "\u{a9}ART", which is plain artist); TPE2 is ID3's.
                if tags.albumArtist == nil { tags.albumArtist = (fields["aART"] as? String) ?? (fields["TPE2"] as? String) }
                // "\u{a9}grp" is iTunes/MP4's grouping atom (untested, no
                // M4A sample file available yet); TIT1 is ID3's, confirmed
                // against a real JRiver-tagged AIFF (Chirusa.aif).
                if tags.grouping == nil { tags.grouping = (fields["\u{a9}grp"] as? String) ?? (fields["TIT1"] as? String) }
            }
        }

        return tags
    }
}
