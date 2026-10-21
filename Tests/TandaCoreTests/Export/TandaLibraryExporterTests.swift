import XCTest
import Foundation

/// Exports all saved Tandas as text files or playlists, optionally zipped.
/// `withTemporaryAppRoot(realPath: true)` is used because the exporter
/// compares the paths of the folder scan with the Tandas folder by prefix.
@MainActor
final class TandaLibraryExporterTests: XCTestCase {

    // MARK: - Helpers

    private func tandaSongs(_ count: Int = 3, firstID: Int64 = 1) -> [Song] {
        (0..<count).map { offset in
            let id = firstID + Int64(offset)
            return makeSong(
                id: id,
                path: "/Music/\(id).flac",
                title: "T\(id)",
                artist: "Alpha Trio",
                albumArtist: "Singer X",
                duration: 200
            )
        }
    }

    @discardableResult
    private func writeTanda(
        _ name: String,
        in subfolder: String? = nil,
        songs: [Song],
        comment: String? = nil,
        savedAgainst: String? = "Default"
    ) throws -> URL {
        var folder = AppPaths.tandasFolder
        if let subfolder {
            folder = folder.appendingPathComponent(subfolder, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("json")
        try TandaMetadataExporter.export(
            songs: songs,
            tandaName: name,
            to: url,
            comment: comment,
            savedAgainstLibraryName: savedAgainst
        )
        return url
    }

    private func export(
        to staging: URL,
        format: TandaExportFormat = .text,
        orchestra: TagSource = .artist,
        singer: TagSource = .albumArtist,
        live: [Song] = [],
        missing: Set<Int64> = []
    ) throws -> TandaExportSummary {
        var byID: [Int64: Song] = [:]
        var byPath: [String: Song] = [:]
        for song in live {
            if let id = song.id {
                byID[id] = song
            }
            byPath[song.normalizedPath] = song
        }
        return try TandaLibraryExporter.export(
            to: staging,
            format: format,
            orchestraSource: orchestra,
            singerSource: singer,
            songsByID: byID,
            songsByPath: byPath,
            missingSongIDs: missing
        )
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Nothing to export

    func testWithoutATandasFolderTheSummaryIsEmpty() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let staging = try makeTemporaryDirectory()

            let summary = try export(to: staging)

            XCTAssertEqual(summary.tandaCount, 0)
            XCTAssertEqual(summary.folderCount, 0)
            XCTAssertEqual(summary.trackCount, 0)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
        }
    }

    func testFormatsKnowTheirFileExtensions() {
        XCTAssertEqual(TandaExportFormat.text.fileExtension, "txt")
        XCTAssertEqual(TandaExportFormat.m3u8.fileExtension, "m3u8")
    }

    // MARK: - Text format

    func testTextFileHasHeaderCommentAndNumberedTracks() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let songs = tandaSongs()
            try writeTanda("Set A", in: "Di Sarli/1940s", songs: songs, comment: "Line 1\nLine 2")
            let staging = try makeTemporaryDirectory()

            _ = try export(to: staging, live: songs)

            XCTAssertEqual(
                try text(staging.appendingPathComponent("Di Sarli/1940s/Set A.txt")),
                """
                # Tanda: Set A
                # Comment: Line 1 / Line 2
                1. Alpha Trio - T1 (Singer: Singer X)
                2. Alpha Trio - T2 (Singer: Singer X)
                3. Alpha Trio - T3 (Singer: Singer X)

                """
            )
        }
    }

    func testASingerThatEqualsTheOrchestraIsNotRepeated() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let songs = tandaSongs()
            try writeTanda("Set A", songs: songs)
            let staging = try makeTemporaryDirectory()

            _ = try export(to: staging, singer: .artist, live: songs)

            let content = try text(staging.appendingPathComponent("Set A.txt"))
            XCTAssertTrue(content.contains("1. Alpha Trio - T1\n"))
            XCTAssertFalse(content.contains("(Singer:"))
        }
    }

    func testTheTagSourcesDecideOrchestraAndSinger() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let songs = (1...3).map { id -> Song in
                var song = makeSong(id: Int64(id), path: "/Music/\(id).flac", title: "T\(id)", artist: "Wrong", albumArtist: "Wrong Too")
                song.grouping = "Group \(id)"
                return song
            }
            try writeTanda("Set A", songs: songs)
            let staging = try makeTemporaryDirectory()

            _ = try export(to: staging, orchestra: .grouping, singer: .artist, live: songs)

            let content = try text(staging.appendingPathComponent("Set A.txt"))
            XCTAssertTrue(content.contains("1. Group 1 - T1 (Singer: Wrong)\n"))
        }
    }

    func testMissingTagsAreLeftOutAndTitlesFallBackToTheFileName() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let songs = [
                makeSong(id: 101, path: "/Music/a.flac", title: "Only Title"),
                makeSong(id: 102, path: "/Music/7.flac", artist: "Alpha"),
                makeSong(id: 103, path: "/Music/9.flac"),
                makeSong(id: 104, path: "/Music/b.flac", title: "  Song \n  One  ", artist: " Alpha \n Trio ")
            ]
            try writeTanda("Odd", songs: songs)          // none of them is in the library
            let staging = try makeTemporaryDirectory()

            _ = try export(to: staging)

            XCTAssertEqual(
                try text(staging.appendingPathComponent("Odd.txt")),
                """
                # Tanda: Odd
                1. Only Title
                2. Alpha - 7
                3. 9
                4. Alpha Trio - Song One

                """
            )
        }
    }

    func testCommentLinesAreJoinedAndBlankCommentsAreSkipped() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let songs = tandaSongs()
            try writeTanda("Blank", songs: songs, comment: "  \n \n")
            try writeTanda("None", songs: songs, comment: nil)
            try writeTanda("Gaps", songs: songs, comment: "First\n\n  Second  \n")
            let staging = try makeTemporaryDirectory()

            _ = try export(to: staging, live: songs)

            XCTAssertFalse(try text(staging.appendingPathComponent("Blank.txt")).contains("# Comment"))
            XCTAssertFalse(try text(staging.appendingPathComponent("None.txt")).contains("# Comment"))
            XCTAssertTrue(try text(staging.appendingPathComponent("Gaps.txt")).contains("# Comment: First / Second\n"))
        }
    }

    // MARK: - M3U8 format

    func testM3U8UsesFileNamesAndTheOrchestraAsArtist() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let songs = tandaSongs()
            try writeTanda("Set A", in: "Di Sarli", songs: songs)
            let staging = try makeTemporaryDirectory()

            _ = try export(to: staging, format: .m3u8, live: songs)

            XCTAssertEqual(
                try text(staging.appendingPathComponent("Di Sarli/Set A.m3u8")),
                "#EXTM3U\n"
                + "#EXTINF:200,Alpha Trio - T1\n1.flac\n"
                + "#EXTINF:200,Alpha Trio - T2\n2.flac\n"
                + "#EXTINF:200,Alpha Trio - T3\n3.flac\n"
            )
        }
    }

    func testM3U8TakesTheArtistFromTheChosenOrchestraTag() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            var song = makeSong(id: 1, path: "/Music/1.flac", title: "T1", artist: "Wrong", duration: 100)
            song.grouping = "Right"
            let songs = [song, makeSong(id: 2, path: "/Music/2.flac", title: "T2", duration: 100), makeSong(id: 3, path: "/Music/3.flac", title: "T3", duration: 100)]
            try writeTanda("Set A", songs: songs)
            let staging = try makeTemporaryDirectory()

            _ = try export(to: staging, format: .m3u8, orchestra: .grouping, live: songs)

            let content = try text(staging.appendingPathComponent("Set A.m3u8"))
            XCTAssertTrue(content.contains("#EXTINF:100,Right - T1\n1.flac\n"))
            XCTAssertTrue(content.contains("#EXTINF:100,T2\n2.flac\n"), "no grouping, so only the title")
        }
    }

    // MARK: - Summary

    func testSummaryCountsTandasFoldersAndTracks() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let songs = tandaSongs(4)
            try writeTanda("Root", songs: songs)
            try writeTanda("One", in: "Di Sarli", songs: songs)
            try writeTanda("Two", in: "Di Sarli", songs: Array(songs.prefix(3)))
            try writeTanda("Three", in: "D'Arienzo/1930s", songs: Array(songs.prefix(3)))
            let staging = try makeTemporaryDirectory()

            let summary = try export(to: staging, live: songs)

            XCTAssertEqual(summary.tandaCount, 4)
            XCTAssertEqual(summary.folderCount, 2, "root files do not count as a folder")
            XCTAssertEqual(summary.trackCount, 4 + 4 + 3 + 3)
            XCTAssertEqual(summary.notInLibraryCount, 0)
            XCTAssertEqual(summary.missingFileCount, 0)
            XCTAssertTrue(summary.unreadableFiles.isEmpty)
        }
    }

    func testLiveLibraryDataReplacesTheSavedData() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let saved = [
                makeSong(id: 1, path: "/Old/1.flac", title: "Old Title", artist: "Old Orchestra"),
                makeSong(id: 2, path: "/Music/2.flac", title: "T2", artist: "Alpha Trio"),
                makeSong(id: 3, path: "/Music/3.flac", title: "T3", artist: "Alpha Trio")
            ]
            try writeTanda("Set A", songs: saved)
            let live = [
                makeSong(id: 1, path: "/New/1.flac", title: "New Title", artist: "New Orchestra"),
                saved[1],
                saved[2]
            ]
            let staging = try makeTemporaryDirectory()

            _ = try export(to: staging, live: live)

            let content = try text(staging.appendingPathComponent("Set A.txt"))
            XCTAssertTrue(content.contains("1. New Orchestra - New Title\n"))
            XCTAssertFalse(content.contains("Old Title"))
        }
    }

    func testMissingFilesAndSongsOutsideTheLibraryAreCountedButStillExported() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let saved = tandaSongs(3)
            try writeTanda("Set A", songs: saved)
            let live = [saved[0], saved[1]]                 // song 3 is not in the library
            let staging = try makeTemporaryDirectory()

            let summary = try export(to: staging, live: live, missing: [2])

            XCTAssertEqual(summary.missingFileCount, 1)
            XCTAssertEqual(summary.notInLibraryCount, 1)
            XCTAssertEqual(summary.trackCount, 3)
            XCTAssertTrue(try text(staging.appendingPathComponent("Set A.txt")).contains("3. Alpha Trio - T3"))
        }
    }

    func testIDsOfAnotherLibraryAreNotTrusted() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let saved = (1...3).map { makeSong(id: Int64($0), path: "/Music/\($0).flac", title: "Saved \($0)", artist: "Alpha Trio") }
            try writeTanda("Imported", songs: saved, savedAgainst: "Other")
            // Same ids, but other files; the real ones are found by path.
            let live = (1...3).flatMap { id -> [Song] in
                [
                    makeSong(id: Int64(id), path: "/Else/\(id).flac", title: "Wrong \(id)", artist: "Alpha Trio"),
                    makeSong(id: Int64(id) + 10, path: "/Music/\(id).flac", title: "Right \(id)", artist: "Alpha Trio")
                ]
            }
            let staging = try makeTemporaryDirectory()

            _ = try export(to: staging, live: live)

            let content = try text(staging.appendingPathComponent("Imported.txt"))
            XCTAssertTrue(content.contains("Right 1"))
            XCTAssertFalse(content.contains("Wrong"))
        }
    }

    func testUnreadableFilesAreReportedWithTheirFolderAndSkipped() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            try writeTanda("Good", songs: tandaSongs())
            try FileManager.default.createDirectory(at: AppPaths.tandasFolder.appendingPathComponent("Sub"), withIntermediateDirectories: true)
            try "garbage".write(to: AppPaths.tandasFolder.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
            try "garbage".write(to: AppPaths.tandasFolder.appendingPathComponent("Sub/broken2.json"), atomically: true, encoding: .utf8)
            let staging = try makeTemporaryDirectory()

            let summary = try export(to: staging, live: tandaSongs())

            XCTAssertEqual(summary.tandaCount, 1)
            XCTAssertEqual(Set(summary.unreadableFiles), ["broken.json", "Sub/broken2.json"])
        }
    }

    func testOtherFilesInTheTandasFolderAreIgnored() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            try writeTanda("Good", songs: tandaSongs())
            try "notes".write(to: AppPaths.tandasFolder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
            let staging = try makeTemporaryDirectory()

            let summary = try export(to: staging, live: tandaSongs())

            XCTAssertEqual(summary.tandaCount, 1)
            XCTAssertTrue(summary.unreadableFiles.isEmpty)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), ["Good.txt"])
        }
    }

    func testExportReplacesFilesFromAPreviousRun() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let songs = tandaSongs()
            let url = try writeTanda("Set A", songs: songs, comment: "first")
            let staging = try makeTemporaryDirectory()
            _ = try export(to: staging, live: songs)

            try FileManager.default.removeItem(at: url)
            try writeTanda("Set A", songs: songs, comment: "second")
            _ = try export(to: staging, live: songs)

            let content = try text(staging.appendingPathComponent("Set A.txt"))
            XCTAssertTrue(content.contains("# Comment: second"))
            XCTAssertFalse(content.contains("first"))
        }
    }

    func testAStagingFolderThatCannotBeCreatedThrows() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            try writeTanda("Set A", songs: tandaSongs())
            let blocker = try writeText("a file, not a folder", in: try makeTemporaryDirectory(), named: "blocker")

            XCTAssertThrowsError(try export(to: blocker.appendingPathComponent("staging"), live: tandaSongs()))
        }
    }

    // MARK: - Zip

    func testZipAndImportRoundTrip() throws {
        try withTemporaryAppRoot(realPath: true) { _ in
            let songs = tandaSongs()
            try writeTanda("Set A", in: "Di Sarli/1940s", songs: songs, comment: "Line 1\nLine 2")
            let staging = try makeTemporaryDirectory().appendingPathComponent("Tandas", isDirectory: true)
            _ = try export(to: staging, live: songs)
            let zipURL = try makeTemporaryDirectory().appendingPathComponent("shared.zip")

            try TandaLibraryExporter.zip(folder: staging, to: zipURL)
            let scan = try TandaZipImporter.read(zipURL: zipURL)

            let tanda = try XCTUnwrap(scan.tandas.first)
            XCTAssertEqual(scan.tandas.count, 1)
            XCTAssertEqual(tanda.folder, "Di Sarli")
            XCTAssertEqual(tanda.subfolder, "1940s")
            XCTAssertEqual(tanda.name, "Set A")
            XCTAssertEqual(tanda.comment, "Line 1 / Line 2")
            XCTAssertEqual(tanda.tracks.map(\.title), ["T1", "T2", "T3"])
            XCTAssertEqual(tanda.tracks.map(\.artist), ["Alpha Trio", "Alpha Trio", "Alpha Trio"])
            XCTAssertEqual(tanda.tracks.map(\.singer), ["Singer X", "Singer X", "Singer X"])
        }
    }

    func testZipReplacesAnExistingFile() throws {
        let folder = try makeTemporaryDirectory().appendingPathComponent("Tandas", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "content".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let zipURL = try makeTemporaryDirectory().appendingPathComponent("shared.zip")
        try Data("old".utf8).write(to: zipURL)

        try TandaLibraryExporter.zip(folder: folder, to: zipURL)

        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int64)
        XCTAssertGreaterThan(size, 3)
    }

    func testZipOfAMissingFolderFails() throws {
        let dir = try makeTemporaryDirectory()

        do {
            try TandaLibraryExporter.zip(folder: dir.appendingPathComponent("nope"), to: dir.appendingPathComponent("x.zip"))
            XCTFail("expected zipFailed")
        } catch TandaExportError.zipFailed(let message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testErrorDescription() {
        XCTAssertEqual(
            TandaExportError.zipFailed("disk full").errorDescription,
            "The ZIP file could not be created: disk full"
        )
    }
}
