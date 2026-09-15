//
//  BackupUtility.swift
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

enum BackupError: Error, CustomStringConvertible {
    case sourceNotFound(String)
    case copyFailed(String)

    var description: String {
        switch self {
        case .sourceNotFound(let path):
            return "Cannot back up — source file not found: \(path)"
        case .copyFailed(let reason):
            return "Backup failed: \(reason)"
        }
    }
}

/// Creates an exiftool-style "_original" backup before a file is modified.
///
/// This isn't wired to a command yet — audiotag2 is still read-only — but
/// it's the safety net any future write/strip/rename command should call
/// first, so it's included now rather than bolted on later as an afterthought.
enum BackupUtility {
    /// Naming matches exiftool's default exactly: "track.flac" backs up to
    /// "track.flac_original" (the full original filename, extension included,
    /// with "_original" appended — not a new extension).
    ///
    /// If a backup already exists, it is left untouched and its path is
    /// simply returned. This matters: exiftool never overwrites an existing
    /// "_original" file, because doing so on a second edit would destroy the
    /// one true original in favor of an already-modified copy.
    @discardableResult
    static func backupOriginalIfNeeded(for url: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw BackupError.sourceNotFound(url.path)
        }

        let backupURL = URL(fileURLWithPath: url.path + "_original")

        if fm.fileExists(atPath: backupURL.path) {
            return backupURL
        }

        do {
            try fm.copyItem(at: url, to: backupURL)
        } catch {
            throw BackupError.copyFailed(error.localizedDescription)
        }

        return backupURL
    }
}
