import XCTest
import Foundation
import GRDB

/// Everything here runs against in-memory databases or files in a
/// temporary directory. Nothing touches `~/.TandaComposer`.
@MainActor
final class DatabaseManagerTests: XCTestCase {

    // MARK: - Helpers

    @discardableResult
    private func insert(_ song: Song, into manager: DatabaseManager) throws -> Song {
        // GRDB 7: `insert` does not update the id of a `PersistableRecord`;
        // `inserted` returns the copy with the new row id.
        try manager.dbQueue.write { db in
            try song.inserted(db)
        }
    }

    private func songCount(_ manager: DatabaseManager) throws -> Int {
        try manager.dbQueue.read { db in
            try Song.fetchCount(db)
        }
    }

    private func tableNames(_ manager: DatabaseManager) throws -> Set<String> {
        try manager.dbQueue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
    }

    private func libraryPath(in directory: URL, named name: String = "Library.sqlite") -> String {
        directory.appendingPathComponent(name).path
    }

    // MARK: - Schema

    func testInMemoryDatabaseHasTheCurrentTables() throws {
        let manager = try DatabaseManager()
        let names = try tableNames(manager)

        XCTAssertTrue(names.isSuperset(of: ["songs", "import_sources"]))
        XCTAssertFalse(names.contains("playlists"), "dead schema must stay gone")
        XCTAssertFalse(names.contains("playlist_songs"), "dead schema must stay gone")
    }

    func testSongsTableMatchesTheSongModel() throws {
        let manager = try DatabaseManager()

        let columns = try manager.dbQueue.read { db in
            try db.columns(in: "songs").map(\.name)
        }

        let expected: Set<String> = [
            "id", "filename", "path", "normalizedPath", "title", "artist", "albumArtist",
            "genre", "grouping", "year", "comment", "fileType", "duration", "sampleRate",
            "replayGain", "album", "key", "bpm", "fileSize", "lastModified",
            "addedToLibrary", "lastLibraryScan", "fileModificationDateAtScan",
            "fileSizeAtScan", "fileHash"
        ]
        XCTAssertEqual(Set(columns), expected)
        XCTAssertEqual(columns.count, expected.count, "no duplicate columns")
    }

    // MARK: - Records

    func testSongRoundTripsThroughTheDatabase() throws {
        let manager = try DatabaseManager()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let song = Song(
            id: nil,
            filename: "poema.flac",
            path: "/Music/poema.flac",
            normalizedPath: "/Music/poema.flac",
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
            addedToLibrary: date,
            lastLibraryScan: date,
            fileModificationDateAtScan: date,
            fileSizeAtScan: 12_345_678,
            fileHash: "abc123"
        )

        let inserted = try insert(song, into: manager)
        let id = try XCTUnwrap(inserted.id, "insert must report the new row id")

        let fetched = try manager.dbQueue.read { db in
            try Song.fetchOne(db, key: id)
        }

        XCTAssertEqual(fetched, inserted)
    }

    func testSongWithOnlyRequiredFieldsRoundTrips() throws {
        let manager = try DatabaseManager()
        let inserted = try insert(makeSong(path: "/Music/a.flac"), into: manager)
        let id = try XCTUnwrap(inserted.id)

        let fetched = try manager.dbQueue.read { db in
            try Song.fetchOne(db, key: id)
        }

        XCTAssertEqual(fetched?.path, "/Music/a.flac")
        XCTAssertNil(fetched?.title)
        XCTAssertNil(fetched?.year)
    }

    func testPathMustBeUnique() throws {
        let manager = try DatabaseManager()
        try insert(makeSong(path: "/Music/a.flac"), into: manager)

        XCTAssertThrowsError(try insert(makeSong(path: "/Music/a.flac"), into: manager))
        XCTAssertEqual(try songCount(manager), 1)
    }

    func testNormalizedPathIsOnlyIndexedNotUnique() throws {
        let manager = try DatabaseManager()
        var first = makeSong(path: "/Music/a.flac")
        var second = makeSong(path: "/Music/b.flac")
        first.normalizedPath = "/Music/same.flac"
        second.normalizedPath = "/Music/same.flac"

        try insert(first, into: manager)
        try insert(second, into: manager)

        XCTAssertEqual(try songCount(manager), 2)
    }

    func testImportSourceRoundTrips() throws {
        let manager = try DatabaseManager()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let source = ImportSource(
            path: "/Volumes/Music/Tango",
            volumeUUID: "UUID-1",
            volumeName: "Music",
            importedAt: date
        )

        let stored = try manager.dbQueue.write { db in
            try source.inserted(db)
        }
        let id = try XCTUnwrap(stored.id)

        let fetched = try manager.dbQueue.read { db in
            try ImportSource.fetchOne(db, key: id)
        }

        XCTAssertEqual(fetched, stored)
    }

    // MARK: - Files: create and open

    func testCreateEmptyLibraryCreatesAFileWithTheSchema() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir)

        try DatabaseManager.createEmptyLibrary(at: path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let reopened = try DatabaseManager(path: path)
        XCTAssertTrue(try tableNames(reopened).isSuperset(of: ["songs", "import_sources"]))
        XCTAssertEqual(try songCount(reopened), 0)
    }

    func testCreateEmptyLibraryCreatesMissingFolders() throws {
        let dir = try makeTemporaryDirectory()
        let path = dir.appendingPathComponent("a/b/c/Library.sqlite").path

        try DatabaseManager.createEmptyLibrary(at: path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testCreateEmptyLibraryRefusesToOverwriteAndLeavesTheFileAlone() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir)
        let original = Data("precious".utf8)
        FileManager.default.createFile(atPath: path, contents: original)

        do {
            try DatabaseManager.createEmptyLibrary(at: path)
            XCTFail("expected destinationAlreadyExists")
        } catch DatabaseManagerError.destinationAlreadyExists(let reported) {
            XCTAssertEqual(reported, path)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), original)
    }

    func testOpeningAMissingFileThrowsFileNotFound() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir, named: "nope.sqlite")

        do {
            _ = try DatabaseManager(path: path)
            XCTFail("expected fileNotFound")
        } catch DatabaseManagerError.fileNotFound(let reported) {
            XCTAssertEqual(reported, path)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "opening must not create the file")
    }

    func testOpeningAForeignDatabaseThrowsInvalidLibraryAndDoesNotModifyIt() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir, named: "foreign.sqlite")
        do {
            let foreign = try DatabaseQueue(path: path)
            try foreign.write { db in
                try db.execute(sql: "CREATE TABLE other (id INTEGER PRIMARY KEY)")
            }
        }

        do {
            _ = try DatabaseManager(path: path)
            XCTFail("expected invalidLibrary")
        } catch DatabaseManagerError.invalidLibrary {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let check = try DatabaseQueue(path: path)
        let hasSongs = try check.read { db in try db.tableExists("songs") }
        XCTAssertFalse(hasSongs, "a foreign database must not get the TandaComposer schema")
    }

    func testReopeningALibraryKeepsItsData() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir)
        try DatabaseManager.createEmptyLibrary(at: path)

        do {
            let first = try DatabaseManager(path: path)
            try insert(makeSong(path: "/Music/a.flac", title: "A"), into: first)
        }

        let second = try DatabaseManager(path: path)
        let titles = try second.dbQueue.read { db in
            try Song.fetchAll(db).map(\.title)
        }
        XCTAssertEqual(titles, ["A"])
    }

    // MARK: - Switching

    func testSwitchDatabaseChangesTheDataSource() throws {
        let dir = try makeTemporaryDirectory()
        let otherPath = libraryPath(in: dir, named: "Other.sqlite")
        try DatabaseManager.createEmptyLibrary(at: otherPath)
        do {
            let other = try DatabaseManager(path: otherPath)
            try insert(makeSong(path: "/Music/b.flac", title: "B"), into: other)
        }

        let manager = try DatabaseManager()
        try insert(makeSong(path: "/Music/a.flac", title: "A"), into: manager)

        try manager.switchDatabase(to: otherPath)

        let titles = try manager.dbQueue.read { db in try Song.fetchAll(db).map(\.title) }
        XCTAssertEqual(titles, ["B"])
    }

    func testFailedSwitchKeepsTheCurrentDatabase() throws {
        let dir = try makeTemporaryDirectory()
        let manager = try DatabaseManager()
        try insert(makeSong(path: "/Music/a.flac", title: "A"), into: manager)

        XCTAssertThrowsError(try manager.switchDatabase(to: libraryPath(in: dir, named: "missing.sqlite")))

        XCTAssertEqual(try songCount(manager), 1)
    }

    func testFailedSwitchToAForeignDatabaseKeepsTheCurrentDatabase() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir, named: "foreign.sqlite")
        do {
            let foreign = try DatabaseQueue(path: path)
            try foreign.write { db in try db.execute(sql: "CREATE TABLE other (id INTEGER)") }
        }
        let manager = try DatabaseManager()
        try insert(makeSong(path: "/Music/a.flac"), into: manager)

        XCTAssertThrowsError(try manager.switchDatabase(to: path))

        XCTAssertEqual(try songCount(manager), 1)
    }

    func testDetachForExternalReplaceUsesAnEmptyDatabaseUntilSwitchedBack() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir)
        try DatabaseManager.createEmptyLibrary(at: path)
        let manager = try DatabaseManager(path: path)
        try insert(makeSong(path: "/Music/a.flac"), into: manager)

        try manager.detachForExternalReplace()
        XCTAssertEqual(try songCount(manager), 0)

        try manager.switchDatabase(to: path)
        XCTAssertEqual(try songCount(manager), 1)
    }

    func testSwitchToInMemoryGivesAnEmptyDatabaseWithSchema() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir)
        try DatabaseManager.createEmptyLibrary(at: path)
        let manager = try DatabaseManager(path: path)
        try insert(makeSong(path: "/Music/a.flac"), into: manager)

        try manager.switchToInMemory()

        XCTAssertEqual(try songCount(manager), 0)
        XCTAssertTrue(try tableNames(manager).contains("songs"))
    }

    func testCreateAndSwitchToEmptyLibraryWritesFutureDataToTheNewFile() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir)
        let manager = try DatabaseManager()
        try insert(makeSong(path: "/Music/old.flac"), into: manager)

        try manager.createAndSwitchToEmptyLibrary(at: path)
        XCTAssertEqual(try songCount(manager), 0)

        try insert(makeSong(path: "/Music/new.flac", title: "New"), into: manager)

        let reopened = try DatabaseManager(path: path)
        let titles = try reopened.dbQueue.read { db in try Song.fetchAll(db).map(\.title) }
        XCTAssertEqual(titles, ["New"])
    }

    // MARK: - Vacuum

    func testVacuumKeepsTheRemainingData() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir)
        try DatabaseManager.createEmptyLibrary(at: path)
        let manager = try DatabaseManager(path: path)
        let inserted = try (0..<3).map {
            try insert(makeSong(path: "/Music/\($0).flac", title: "T\($0)"), into: manager)
        }
        let keepID = try XCTUnwrap(inserted[0].id)

        try manager.dbQueue.write { db in
            _ = try Song.filter(Column("id") != keepID).deleteAll(db)
        }
        try manager.vacuum()

        let titles = try manager.dbQueue.read { db in try Song.fetchAll(db).map(\.title) }
        XCTAssertEqual(titles, ["T0"])
    }

    func testStaticVacuumWorksOnAQueue() throws {
        let dir = try makeTemporaryDirectory()
        let path = libraryPath(in: dir)
        try DatabaseManager.createEmptyLibrary(at: path)
        let manager = try DatabaseManager(path: path)
        try insert(makeSong(path: "/Music/a.flac"), into: manager)

        XCTAssertNoThrow(try DatabaseManager.vacuum(on: manager.dbQueue))
        XCTAssertEqual(try songCount(manager), 1)
    }

    // MARK: - Errors

    func testErrorDescriptionsMentionThePath() {
        XCTAssertTrue(DatabaseManagerError.fileNotFound("/x/y.sqlite").errorDescription?.contains("/x/y.sqlite") == true)
        XCTAssertTrue(DatabaseManagerError.destinationAlreadyExists("/x/z.sqlite").errorDescription?.contains("/x/z.sqlite") == true)
        XCTAssertNotNil(DatabaseManagerError.invalidLibrary.errorDescription)
    }
}
