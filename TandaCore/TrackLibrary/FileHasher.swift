//
//  FileHasher.swift
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
import CryptoKit

// MARK: - SHA-256
//
// Full-file content hash used by import and rescan (move detection).

enum FileHasher {

    /// Calculates the SHA-256 hash of the complete file contents and
    /// returns it as a lowercase hexadecimal string.
    /// Hashes the file's full contents off the calling thread.
    ///
    /// Reading + hashing a large file (esp. over slow external/network
    /// media) can take seconds — running it inline on whatever actor
    /// called `readSong` (e.g. a drag-and-drop drop handler that hops
    /// straight back to @MainActor) used to freeze the UI for that
    /// whole duration. `Task.detached` guarantees this always runs on
    /// a background thread, no matter the caller's isolation.
    static func sha256(
        fileURL:
            URL
    ) async throws -> String {

        try await Task.detached(
            priority:
                .utility
        ) {

            try sha256Sync(
                fileURL:
                    fileURL
            )

        }.value
    }


    nonisolated private static func sha256Sync(
        fileURL:
            URL
    ) throws -> String {

        let handle =
            try FileHandle(
                forReadingFrom:
                    fileURL
            )

        defer {
            try? handle.close()
        }


        var hasher =
            SHA256()


        while true {

            let data =
                try handle.read(
                    upToCount:
                        1_048_576
                )


            guard
                let data
            else {
                break
            }


            if data.isEmpty {
                break
            }


            hasher.update(
                data:
                    data
            )
        }


        let digest =
            hasher.finalize()


        return digest
            .map {
                String(
                    format:
                        "%02x",
                    $0
                )
            }
            .joined()
    }
}
