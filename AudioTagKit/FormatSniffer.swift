//
//  FormatSniffer.swift
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

public enum AudioFormat {
    case flac
    case mp3
    case mp4Family   // m4a / m4b / m4p / aac-in-mp4 / alac — all share the "ftyp" box
    case aiff        // aiff / aifc — IFF "FORM...AIFF"/"FORM...AIFC"
    case unknown
}

/// Detects the real container format from magic bytes rather than trusting
/// the file extension. This matters most for the write path, where we must
/// pick the exact writer (FLAC block rewriting vs ID3v2 vs MP4 passthrough
/// export) — getting it wrong there corrupts the file, not just mislabels it.
public enum FormatSniffer {
    public static func detect(url: URL) -> AudioFormat {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 12)
        guard header.count >= 4 else { return .unknown }

        if header.prefix(4).elementsEqual("fLaC".utf8) {
            return .flac
        }

        // AIFF/AIFC: "FORM" + 4-byte size + form type ("AIFF" or "AIFC").
        if header.count >= 12,
           header.prefix(4).elementsEqual("FORM".utf8),
           (header.subdata(in: 8..<12).elementsEqual("AIFF".utf8) || header.subdata(in: 8..<12).elementsEqual("AIFC".utf8)) {
            return .aiff
        }

        // MP4-family containers place the four-char box type "ftyp" at byte
        // offset 4 (after the 4-byte box size that precedes it).
        if header.count >= 8, header.subdata(in: 4..<8).elementsEqual("ftyp".utf8) {
            return .mp4Family
        }

        // MP3 with an ID3v2 tag prepended.
        if header.prefix(3).elementsEqual("ID3".utf8) {
            return .mp3
        }

        // MP3 with no ID3v2 tag: starts directly with an MPEG frame sync
        // (11 set bits: 0xFF followed by the top 3 bits of the next byte).
        if header.count >= 2 {
            let b0 = header[header.startIndex]
            let b1 = header[header.startIndex + 1]
            if b0 == 0xFF && (b1 & 0xE0) == 0xE0 {
                return .mp3
            }
        }

        return .unknown
    }
}
