//
//  MetadataReader.swift
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

enum MetadataError: Error, CustomStringConvertible {
    case invalidFile
    case unsupportedFormat
    case readFailed(String)

    var description: String {
        switch self {
        case .invalidFile: return "The file could not be parsed (invalid or corrupt)."
        case .unsupportedFormat: return "No reader available for this file format."
        case .readFailed(let reason): return "Failed to read metadata: \(reason)"
        }
    }
}

/// A single, format-specific metadata reader.
/// Conform to this for each container format (FLAC, MP3, M4A, etc.).
protocol MetadataReader {
    /// Quick check based on file extension / magic bytes — used for dispatch.
    static func canHandle(url: URL) -> Bool
    /// Extract all available metadata as a flat, JSON-serializable dictionary.
    static func read(url: URL) async throws -> [String: Any]
}

/// Top-level entry point: tries each registered reader in order and
/// returns the result from the first one that claims the file.
public enum AudioMetadataKit {
    /// Order matters: put more specific / hand-rolled readers first,
    /// with AVFoundation last as the general-purpose fallback.
    static let readers: [MetadataReader.Type] = [
        FLACReader.self,
        AIFFReader.self,
        AVFoundationReader.self
    ]

    public static func read(url: URL) async throws -> [String: Any] {
        for reader in readers where reader.canHandle(url: url) {
            return try await reader.read(url: url)
        }
        throw MetadataError.unsupportedFormat
    }
}
