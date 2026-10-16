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
    id: Int64? = nil,
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
        id: id,
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


/// A date without fractional seconds. The JSON files store dates as
/// ISO-8601 strings, which are exact to the second only.
let wholeSecondDate = Date(timeIntervalSince1970: 1_700_000_000)

/// A `Song` with every field filled, using whole-second dates so it survives
/// a JSON or database round trip unchanged.
func makeFullSong(id: Int64? = nil, path: String = "/Music/poema.flac") -> Song {
    Song(
        id: id,
        filename: URL(fileURLWithPath: path).lastPathComponent,
        path: path,
        normalizedPath: PathNormalizer.normalize(path),
        title: "Poema",
        artist: "Alpha Trio",
        albumArtist: "Singer X",
        genre: "Tango",
        grouping: "Group A",
        year: 1940,
        comment: "remark",
        fileType: "FLAC",
        duration: 215,
        sampleRate: 44100,
        replayGain: -7.25,
        album: "Album One",
        key: "Am",
        bpm: 111.5,
        fileSize: 12_345_678,
        lastModified: 1_700_000_000,
        addedToLibrary: wholeSecondDate,
        lastLibraryScan: wholeSecondDate,
        fileModificationDateAtScan: wholeSecondDate,
        fileSizeAtScan: 12_345_678,
        fileHash: "abc123"
    )
}

/// `count` simple songs with ids 1...count, titles "T1"..., artists "A1"...
func makeSongs(_ count: Int) -> [Song] {
    (0..<count).map { index in
        let number = index + 1
        return makeSong(
            id: Int64(number),
            path: "/Music/\(number).flac",
            title: "T\(number)",
            artist: "A\(number)"
        )
    }
}

extension XCTestCase {

    /// Runs `body` with `AppPaths` redirected to a fresh temporary folder
    /// (library name reset to the default) and restores the previous state
    /// afterwards.
    ///
    /// SAFETY: if the redirect does not take effect, the test is skipped
    /// instead of running against the real `~/.TandaComposer`.
    func withTemporaryAppRoot(_ body: (URL) throws -> Void) throws {
        // Canonical path (/private/var/... instead of /var/...), so URLs that the
        // file system hands back compare equal to the ones the code built.
        let root = try makeTemporaryDirectory().resolvingSymlinksInPath()

        let previousRoot = AppPaths.rootOverride
        let previousLibraryName = AppPaths.currentLibraryName
        AppPaths.rootOverride = root
        AppPaths.currentLibraryName = AppPaths.defaultLibraryName
        defer {
            AppPaths.rootOverride = previousRoot
            AppPaths.currentLibraryName = previousLibraryName
        }

        guard AppPaths.root.standardizedFileURL.path == root.standardizedFileURL.path else {
            throw XCTSkip("AppPaths.rootOverride has no effect; refusing to touch real data")
        }

        try body(root)
    }
}

/// Compares two file URLs by their standardized path.
func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
}
