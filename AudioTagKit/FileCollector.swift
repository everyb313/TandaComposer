//
//  FileCollector.swift
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

/// Extensions this tool recognizes as audio files — exposed publicly since
/// a GUI file picker or drag-drop validator would want the same list
/// rather than duplicating it.
public let supportedExtensions: Set<String> = ["flac", "mp3", "m4a", "aac", "alac", "m4b", "m4p", "aiff", "aif", "aifc"]

/// Expands a mix of file paths and directory paths into a flat,
/// deduplicated, sorted list of audio file URLs. Shared by any
/// subcommand that accepts a batch of inputs (`read`, `dedup`).
public enum FileCollector {
    /// - Parameter recursive: if true, directories are walked fully;
    ///   if false, only a directory's immediate contents are used
    ///   (mirroring exiftool's default vs. `-r` behavior).
    public static func collect(from inputPaths: [String], recursive: Bool) throws -> [URL] {
        let fm = FileManager.default
        var results: Set<URL> = []

        for path in inputPaths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false

            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                FileHandle.standardError.write("Not found, skipping: \(path)\n".data(using: .utf8)!)
                continue
            }

            if isDirectory.boolValue {
                if recursive {
                    if let enumerator = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        for case let fileURL as URL in enumerator {
                            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                                results.insert(fileURL)
                            }
                        }
                    }
                } else {
                    if let contents = try? fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) {
                        for fileURL in contents
                        where supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                            results.insert(fileURL)
                        }
                    }
                }
            } else {
                results.insert(url)
            }
        }

        return results.sorted { $0.path < $1.path }
    }
}
