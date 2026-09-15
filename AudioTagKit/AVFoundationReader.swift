//
//  AVFoundationReader.swift
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
import AVFoundation
import CoreMedia

/// General-purpose fallback reader built on AVFoundation.
/// Handles MP3 (ID3), M4A/AAC/ALAC (iTunes-style atoms), and anything
/// else AVAsset understands out of the box.
struct AVFoundationReader: MetadataReader {

    static func canHandle(url: URL) -> Bool {
        // Fallback reader — claims anything not already handled upstream.
        true
    }

    static func read(url: URL) async throws -> [String: Any] {
        let asset = AVURLAsset(url: url)
        var result: [String: Any] = [:]
        var common: [String: Any] = [:]
        var formatSpecific: [String: [String: Any]] = [:]
        let isMP3 = FormatSniffer.detect(url: url) == .mp3

        // Duration
        let duration = try await asset.load(.duration)
        result["durationSeconds"] = CMTimeGetSeconds(duration)

        // Sample rate / channels / bit depth — AVFoundation's metadata
        // items never carry stream-level technical properties, only tag
        // data, so this comes from the audio track's format description
        // instead. (Previously missing entirely for MP3/M4A — FLAC/AIFF
        // already had their own equivalent via hand-parsed headers.)
        if let streamInfo = try await Self.readAudioStreamInfo(asset: asset) {
            result["streamInfo"] = streamInfo
        }

        // Common metadata (title, artist, album, artwork presence, etc.)
        let commonItems = try await asset.load(.commonMetadata)
        for item in commonItems {
            guard let key = item.commonKey?.rawValue else { continue }
            if let value = try await item.load(.value) {
                common[key] = describableValue(value)
            }
        }
        if !common.isEmpty { result["common"] = common }

        if isMP3 {
            // MP3's ID3v2 tag is re-parsed directly with our own
            // ID3FrameCodec rather than through AVFoundation's metadata
            // API. AVFoundation dumps each item under its bare 4-char
            // frame ID with no per-item disambiguation, which silently
            // collapses multiple TXXX/COMM frames — very common in
            // practice (ReplayGain, R128 loudness analysis, custom
            // fields) — down to whichever one happened to be processed
            // last. Already solved correctly for AIFF's embedded ID3
            // chunk; this reuses the exact same logic for standalone MP3.
            if let id3Bucket = try? Self.readID3Directly(url: url), !id3Bucket.isEmpty {
                formatSpecific["ID3"] = id3Bucket
            }
        } else {
            // Format-specific containers for everything else: iTunes,
            // QuickTime user data, etc. (MP3/ID3 is handled above instead,
            // for the reason noted there — no evidence of the same
            // same-key-collision problem affecting these other formats.)
            let formats = try await asset.load(.availableMetadataFormats)
            for format in formats {
                let items = try await asset.loadMetadata(for: format)
                var bucket: [String: Any] = [:]
                for item in items {
                    let keyString: String
                    if let s = item.key as? String {
                        keyString = s
                    } else if let n = item.key as? NSNumber {
                        keyString = n.stringValue
                    } else {
                        continue
                    }
                    if let value = try await item.load(.value) {
                        bucket[keyString] = describableValue(value)
                    }
                }
                if !bucket.isEmpty {
                    formatSpecific[format.rawValue] = bucket
                }
            }
        }
        if !formatSpecific.isEmpty { result["formatSpecific"] = formatSpecific }

        result["format"] = url.pathExtension.uppercased()
        return result
    }

    /// Reads the MP3's actual ID3v2 tag bytes directly (not the whole
    /// file — just the header, then exactly the tag's declared size) and
    /// decodes every frame via ID3FrameCodec, surfacing all of them —
    /// same generic-passthrough approach AIFFReader already uses.
    private static func readID3Directly(url: URL) throws -> [String: Any] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }

        let header = handle.readData(ofLength: 10)
        guard header.count == 10, header.prefix(3).elementsEqual("ID3".utf8) else { return [:] }

        let bodySize = ID3FrameCodec.syncsafeDecode(header.subdata(in: 6..<10))
        try handle.seek(toOffset: 0)
        let tagData = handle.readData(ofLength: 10 + bodySize)

        let frames = ID3FrameCodec.parseTag(tagData)
        var fields: [String: Any] = [:]

        for f in frames {
            switch f.id {
            case "APIC":
                continue // artwork is already surfaced via commonMetadata's artwork key
            case "TXXX":
                // A file can carry many TXXX frames side by side (ReplayGain,
                // loudness analysis, tool name, ...) — keyed by description
                // so they don't collide under one "TXXX" entry.
                let (description, value) = ID3FrameCodec.decodeUserTextFrame(f.content)
                fields[description.isEmpty ? "TXXX" : "TXXX:\(description)"] = value
            case "COMM":
                // Same collision risk as TXXX — a real comment can sit
                // alongside automated iTunNORM/iTunSMPB-style COMM frames.
                let (description, value) = ID3FrameCodec.decodeCommentFrame(f.content)
                fields[description.isEmpty ? "COMM" : "COMM:\(description)"] = value
            case "TDRC":
                // v2.4's unified date frame, normalized to the same "TYER"
                // key CanonicalTags.year already checks — matches
                // AIFFReader's convention exactly, so MP3 gets year
                // support without any change needed in CanonicalTags.
                fields["TYER"] = ID3FrameCodec.decodeTextValue(f.content)
            case "TYER":
                if fields["TYER"] == nil { fields["TYER"] = ID3FrameCodec.decodeTextValue(f.content) } // older v2.3 files; TDRC takes priority if both present
            default:
                if f.id.hasPrefix("T") {
                    fields[f.id] = ID3FrameCodec.decodeTextValue(f.content)
                } else {
                    // Non-text, non-picture frame not specifically decoded
                    // (e.g. PRIV, UFID) — note presence/size rather than
                    // silently dropping it or dumping raw bytes.
                    fields[f.id] = "<binary, \(f.content.count) bytes>"
                }
            }
        }

        return fields
    }

    /// Sample rate, channel count, and (where meaningful) bit depth from
    /// the first audio track's format description.
    private static func readAudioStreamInfo(asset: AVURLAsset) async throws -> [String: Any]? {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        var info: [String: Any] = [
            "sampleRate": Int(basicDescription.pointee.mSampleRate.rounded()),
            "channels": Int(basicDescription.pointee.mChannelsPerFrame)
        ]

        // Only meaningful for uncompressed/lossless formats (e.g. ALAC) —
        // MP3/AAC are compressed and have no fixed per-sample bit depth,
        // so this is omitted rather than reporting a number that doesn't mean anything.
        if basicDescription.pointee.mBitsPerChannel > 0 {
            info["bitsPerSample"] = Int(basicDescription.pointee.mBitsPerChannel)
        }

        return info
    }

    /// AVMetadataItem values can be NSString, NSNumber, NSData (artwork), NSDate, etc.
    /// Normalize to something that prints/serializes cleanly.
    private static func describableValue(_ value: Any) -> Any {
        switch value {
        case let data as Data:
            return "<binary data, \(data.count) bytes>"
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        default:
            return value
        }
    }
}
