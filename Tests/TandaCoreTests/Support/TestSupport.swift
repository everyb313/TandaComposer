import XCTest
import Foundation

// Shared helpers for the TandaCoreTests target.
//
// The target uses MainActor as default isolation (like the app), so these
// helpers and all test classes are MainActor-isolated. Tests avoid
// overriding setUp/tearDown; temporary files are cleaned up with
// `addTeardownBlock` instead.

extension XCTestCase {

    /// A fresh, empty directory that is removed again after the test.
    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TandaCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            _ = try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    /// Writes `text` as UTF-8 into `directory/name` and returns the file URL.
    func writeText(_ text: String, in directory: URL, named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes raw bytes into `directory/name` and returns the file URL.
    func writeData(_ data: Data, in directory: URL, named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

/// Minimal `Song` for tests. Only the fields the tested code looks at.
func makeSong(
    path: String,
    title: String? = nil,
    artist: String? = nil,
    albumArtist: String? = nil,
    genre: String? = nil,
    grouping: String? = nil,
    year: Int? = nil,
    duration: Int? = nil,
    album: String? = nil
) -> Song {
    Song(
        filename: URL(fileURLWithPath: path).lastPathComponent,
        path: path,
        normalizedPath: PathNormalizer.normalize(path),
        title: title,
        artist: artist,
        albumArtist: albumArtist,
        genre: genre,
        grouping: grouping,
        year: year,
        duration: duration,
        album: album
    )
}

/// Polls `condition` until it is true or `timeout` seconds have passed.
/// For state that a store updates asynchronously (e.g. after a detached task).
func waitUntil(
    timeout: TimeInterval = 3,
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}
