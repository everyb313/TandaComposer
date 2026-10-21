import XCTest
import Foundation
import GRDB

/// End-to-end tests of import and rescan with real files in a temporary
/// folder. The files are hand-built FLACs (see `makeFLACData`); every test
/// uses its own in-memory database.
@MainActor
final class LibraryScannerTests: XCTestCase {

    // MARK: - Helpers

    private func makeScanner() throws -> (scanner: LibraryScanner, manager: DatabaseManager) {
        let manager = try DatabaseManager()
        return (LibraryScanner(db: manager), manager)
    }

    /// A fresh music folder with the real (`/private/var/...`) path, because
    /// the folder scan reports files that way.
    private func makeMusicFolder(_ name: String = "Music") throws -> URL {
        let parent = canonicalURL(try makeTemporaryDirectory())
        let folder = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes a FLAC below `folder`; `path` may contain subfolders.
    @discardableResult
    private func writeFLAC(
        _ path: String,
        in folder: URL,
        title: String,
        audioBytes: Int = 16,
        extraTags: [String: String] = [:]
    ) throws -> URL {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var tags = ["TITLE": title, "ARTIST": "Alpha Trio"]
        tags.merge(extraTags) { _, new in new }
        try makeFLACData(tags: tags, audioBytes: audioBytes).write(to: url)
        return url
    }

    private func allSongs(_ manager: DatabaseManager) throws -> [Song] {
        try manager.dbQueue.read { db in
            try Song.order(Column("path")).fetchAll(db)
        }
    }

    private func allSources(_ manager: DatabaseManager) throws -> [ImportSource] {
        try manager.dbQueue.read { db in
            try ImportSource.fetchAll(db)
        }
    }

    /// Three imported files: a.flac, Sub/b.flac, Sub/Deep/c.flac.
    private func importedLibrary() async throws -> (
        scanner: LibraryScanner,
        manager: DatabaseManager,
        folder: URL,
        files: [URL]
    ) {
        let (scanner, manager) = try makeScanner()
        let folder = try makeMusicFolder()
        let files = [
            try writeFLAC("a.flac", in: folder, title: "A", audioBytes: 100),
            try writeFLAC("Sub/b.flac", in: folder, title: "B", audioBytes: 200),
            try writeFLAC("Sub/Deep/c.flac", in: folder, title: "C", audioBytes: 300)
        ]
        try await scanner.importFolder(folder)
        return (scanner, manager, folder, files)
    }

    // MARK: - Import

    func testImportReadsAllAudioFilesRecursively() async throws {
        let (scanner, manager) = try makeScanner()
        let folder = try makeMusicFolder()
        try writeFLAC("a.flac", in: folder, title: "A")
        try writeFLAC("Sub/b.flac", in: folder, title: "B")
        try writeFLAC("Sub/Deep/c.FLAC", in: folder, title: "C")

        try await scanner.importFolder(folder)

        let titles = try allSongs(manager).compactMap(\.title)
        XCTAssertEqual(Set(titles), ["A", "B", "C"])
        XCTAssertEqual(titles.count, 3)
        XCTAssertFalse(scanner.isScanning)
        XCTAssertEqual(scanner.totalCount, 3)
    }

    func testImportIgnoresOtherAndHiddenFiles() async throws {
        let (scanner, manager) = try makeScanner()
        let folder = try makeMusicFolder()
        try writeFLAC("good.flac", in: folder, title: "Good")
        try writeFLAC(".hidden.flac", in: folder, title: "Hidden")
        try "notes".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "image".write(to: folder.appendingPathComponent("cover.jpg"), atomically: true, encoding: .utf8)

        try await scanner.importFolder(folder)

        XCTAssertEqual(try allSongs(manager).map(\.title), ["Good"])
    }

    func testImportStoresTheTagsAndTheScanFacts() async throws {
        let (scanner, manager) = try makeScanner()
        let folder = try makeMusicFolder()
        let file = try writeFLAC(
            "poema.flac",
            in: folder,
            title: "Poema",
            extraTags: ["ALBUMARTIST": "Singer X", "GENRE": "Tango", "DATE": "1940"]
        )

        try await scanner.importFolder(folder)

        let song = try XCTUnwrap(try allSongs(manager).first)
        XCTAssertNotNil(song.id)
        XCTAssertEqual(song.title, "Poema")
        XCTAssertEqual(song.albumArtist, "Singer X")
        XCTAssertEqual(song.genre, "Tango")
        XCTAssertEqual(song.year, 1940)
        XCTAssertEqual(song.duration, 200)
        XCTAssertEqual(song.path, file.path)
        XCTAssertEqual(song.fileHash?.count, 64)
        XCTAssertEqual(song.fileSizeAtScan, song.fileSize)
        XCTAssertGreaterThan(song.fileSizeAtScan, 0)
    }

    func testImportRemembersTheFolderAsAnImportSource() async throws {
        let (scanner, manager) = try makeScanner()
        let folder = try makeMusicFolder()
        try writeFLAC("a.flac", in: folder, title: "A")

        try await scanner.importFolder(folder)

        let sources = try allSources(manager)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.path, folder.path)
    }

    func testImportOfAnEmptyFolderChangesNothing() async throws {
        let (scanner, manager) = try makeScanner()
        let folder = try makeMusicFolder()

        try await scanner.importFolder(folder)

        XCTAssertTrue(try allSongs(manager).isEmpty)
        XCTAssertTrue(try allSources(manager).isEmpty, "no source for a folder that gave no songs")
        XCTAssertFalse(scanner.isScanning)
    }

    func testImportingTheSameFolderAgainUpdatesInsteadOfDuplicating() async throws {
        let (scanner, manager) = try makeScanner()
        let folder = try makeMusicFolder()
        let file = try writeFLAC("a.flac", in: folder, title: "Old Title")
        try await scanner.importFolder(folder)
        let firstID = try XCTUnwrap(try allSongs(manager).first?.id)

        try writeFLAC("a.flac", in: folder, title: "New Title", audioBytes: 500)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try await scanner.importFolder(folder)

        let songs = try allSongs(manager)
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs.first?.title, "New Title")
        XCTAssertEqual(songs.first?.id, firstID, "the row is updated in place")
    }

    func testUnreadableFilesAreReportedButTheGoodOnesAreKept() async throws {
        let (scanner, manager) = try makeScanner()
        let folder = try makeMusicFolder()
        try writeFLAC("good.flac", in: folder, title: "Good")
        try Data(Array("fLaC".utf8) + [0x00, 0x00]).write(to: folder.appendingPathComponent("bad.flac"))

        do {
            try await scanner.importFolder(folder)
            XCTFail("expected partialFailure")
        } catch ImportError.partialFailure(let failed) {
            XCTAssertEqual(failed.map { $0.url.lastPathComponent }, ["bad.flac"])
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(try allSongs(manager).map(\.title), ["Good"])
        XCTAssertFalse(scanner.isScanning)
    }

    // MARK: - Rescan: nothing changed

    func testRescanOfAnUntouchedLibraryFindsNothing() async throws {
        let (scanner, _, _, _) = try await importedLibrary()

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.unchangedCount, 3)
        XCTAssertEqual(summary.unchangedSongsToRefresh.count, 3)
        XCTAssertEqual(summary.updatedCount, 0)
        XCTAssertEqual(summary.missingCount, 0)
        XCTAssertEqual(summary.newlyImportedCount, 0)
        XCTAssertEqual(summary.relocatedCount, 0)
        XCTAssertTrue(summary.failedReads.isEmpty)
        XCTAssertFalse(summary.hasChangesToApply)
        XCTAssertFalse(scanner.isScanning)
        XCTAssertNil(scanner.currentPhase)
    }

    func testRescanWithoutAnySourceAndSongsIsEmpty() async throws {
        let (scanner, _) = try makeScanner()

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.unchangedCount, 0)
        XCTAssertFalse(summary.hasChangesToApply)
    }

    // MARK: - Rescan: changes

    func testADeletedFileIsReportedAsMissing() async throws {
        let (scanner, _, _, files) = try await importedLibrary()
        try FileManager.default.removeItem(at: files[1])

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.missingSongs.map(\.title), ["B"])
        XCTAssertEqual(summary.unchangedCount, 2)
        XCTAssertFalse(summary.hasChangesToApply, "missing files alone are not a change to apply")
    }

    func testAChangedFileIsReadAgainAndKeepsIDAndAddedDate() async throws {
        let (scanner, manager, folder, files) = try await importedLibrary()
        let original = try XCTUnwrap(try allSongs(manager).first { $0.title == "A" })
        try writeFLAC("a.flac", in: folder, title: "A changed", audioBytes: 999)
        XCTAssertEqual(files[0].lastPathComponent, "a.flac")

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.updatedCount, 1)
        let updated = try XCTUnwrap(summary.updatedSongs.first)
        XCTAssertEqual(updated.title, "A changed")
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.addedToLibrary, original.addedToLibrary)
        XCTAssertNotEqual(updated.fileHash, original.fileHash)
        XCTAssertEqual(summary.unchangedCount, 2)
        XCTAssertTrue(summary.hasChangesToApply)
    }

    func testAFileWithANewModificationDateIsReadAgain() async throws {
        let (scanner, _, _, files) = try await importedLibrary()
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(100)],
            ofItemAtPath: files[2].path
        )

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.updatedSongs.map(\.title), ["C"])
        XCTAssertEqual(summary.unchangedCount, 2)
    }

    func testAChangedFileThatCannotBeReadIsReportedAsFailed() async throws {
        let (scanner, _, _, files) = try await importedLibrary()
        try Data(Array("fLaC".utf8) + [0x00, 0x00, 0x00]).write(to: files[0])

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.updatedCount, 0)
        XCTAssertEqual(summary.failedReads.map { $0.url.path }, [files[0].path])
        XCTAssertEqual(summary.unchangedCount, 2)
    }

    func testANewFileInAKnownFolderIsFound() async throws {
        let (scanner, _, folder, _) = try await importedLibrary()
        try writeFLAC("Sub/d.flac", in: folder, title: "D", audioBytes: 400)

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.newlyImportedSongs.map(\.title), ["D"])
        XCTAssertNil(summary.newlyImportedSongs.first?.id, "not stored until applyRescan")
        XCTAssertEqual(summary.unchangedCount, 3)
        XCTAssertTrue(summary.hasChangesToApply)
    }

    func testAMovedFileIsRecognizedByItsContentAndNotImportedAsNew() async throws {
        let (scanner, manager, folder, files) = try await importedLibrary()
        let original = try XCTUnwrap(try allSongs(manager).first { $0.title == "A" })
        let newURL = folder.appendingPathComponent("Moved/renamed.flac")
        try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: files[0], to: newURL)

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.relocatedCount, 1)
        let relocation = try XCTUnwrap(summary.relocatedTracks.first)
        XCTAssertEqual(relocation.oldPath, files[0].path)
        XCTAssertEqual(relocation.song.path, newURL.path)
        XCTAssertEqual(relocation.song.normalizedPath, PathNormalizer.normalize(newURL))
        XCTAssertEqual(relocation.song.id, original.id)
        XCTAssertEqual(summary.newlyImportedCount, 0)
        XCTAssertTrue(summary.hasChangesToApply)
    }

    func testACopyOfAMissingFileCountsAsItsNewLocation() async throws {
        let (scanner, manager, folder, files) = try await importedLibrary()
        let original = try XCTUnwrap(try allSongs(manager).first { $0.title == "A" })
        let copy = folder.appendingPathComponent("copy-of-a.flac")
        try FileManager.default.copyItem(at: files[0], to: copy)
        try FileManager.default.removeItem(at: files[0])

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.relocatedTracks.first?.song.id, original.id)
        XCTAssertEqual(summary.newlyImportedCount, 0)
    }

    // MARK: - applyRescan

    func testApplyRescanStoresEverythingAndTheNextRescanIsQuiet() async throws {
        let (scanner, manager, folder, files) = try await importedLibrary()

        // A changed, B deleted, C moved, D new.
        try writeFLAC("a.flac", in: folder, title: "A changed", audioBytes: 999)
        try FileManager.default.removeItem(at: files[1])
        let movedURL = folder.appendingPathComponent("Moved/c.flac")
        try FileManager.default.createDirectory(at: movedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: files[2], to: movedURL)
        try writeFLAC("d.flac", in: folder, title: "D", audioBytes: 400)

        let summary = try await scanner.rescanLibrary()
        try await scanner.applyRescan(summary)

        let songs = try allSongs(manager)
        XCTAssertEqual(Set(songs.compactMap(\.title)), ["A changed", "B", "C", "D"], "B stays: missing files are not deleted")
        XCTAssertEqual(songs.first { $0.title == "C" }?.path, movedURL.path)
        XCTAssertTrue(songs.allSatisfy { $0.id != nil })

        let second = try await scanner.rescanLibrary()
        XCTAssertEqual(second.unchangedCount, 3, "A, C and D")
        XCTAssertEqual(second.missingSongs.map(\.title), ["B"])
        XCTAssertEqual(second.updatedCount, 0)
        XCTAssertEqual(second.newlyImportedCount, 0)
        XCTAssertEqual(second.relocatedCount, 0)
        XCTAssertFalse(second.hasChangesToApply)
    }

    func testApplyRescanOfAnEmptySummaryIsHarmless() async throws {
        let (scanner, manager, _, _) = try await importedLibrary()

        try await scanner.applyRescan(RescanSummary())

        XCTAssertEqual(try allSongs(manager).count, 3)
    }

    // MARK: - Scope

    private func twoFolders() async throws -> (
        scanner: LibraryScanner,
        manager: DatabaseManager,
        first: URL,
        second: URL,
        secondFiles: [URL]
    ) {
        let (scanner, manager) = try makeScanner()
        let parent = canonicalURL(try makeTemporaryDirectory())
        let first = parent.appendingPathComponent("Tango", isDirectory: true)
        let second = parent.appendingPathComponent("Vals", isDirectory: true)
        let a = try writeFLAC("a.flac", in: first, title: "A", audioBytes: 100)
        let b = try writeFLAC("b.flac", in: second, title: "B", audioBytes: 200)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        try await scanner.importFolder(first)
        try await scanner.importFolder(second)
        return (scanner, manager, first, second, [b])
    }

    private func source(for folder: URL, in manager: DatabaseManager) throws -> ImportSource {
        try XCTUnwrap(try allSources(manager).first { $0.path == folder.path })
    }

    func testRescanWithoutScopeLooksAtAllSources() async throws {
        let (scanner, manager, _, second, files) = try await twoFolders()
        try FileManager.default.removeItem(at: files[0])
        try writeFLAC("new.flac", in: second, title: "New", audioBytes: 300)
        XCTAssertEqual(try allSources(manager).count, 2)

        let summary = try await scanner.rescanLibrary()

        XCTAssertEqual(summary.missingSongs.map(\.title), ["B"])
        XCTAssertEqual(summary.newlyImportedSongs.map(\.title), ["New"])
        XCTAssertEqual(summary.unchangedCount, 1)
    }

    func testRescanWithAScopeOnlyLooksAtThatFolder() async throws {
        let (scanner, manager, first, second, files) = try await twoFolders()
        try FileManager.default.removeItem(at: files[0])

        let outside = try await scanner.rescanLibrary(scope: try source(for: first, in: manager))
        XCTAssertEqual(outside.missingCount, 0)
        XCTAssertEqual(outside.unchangedCount, 1)

        let inside = try await scanner.rescanLibrary(scope: try source(for: second, in: manager))
        XCTAssertEqual(inside.missingSongs.map(\.title), ["B"])
    }

    /// KNOWN ISSUE: the scope is matched with a plain `hasPrefix` on the
    /// path, so the scope ".../Tango" also covers ".../Tango2/...". A
    /// missing file in Tango2 is then reported when only Tango is rescanned.
    /// (`LibraryStore.songCount(underImportSourcePath:)` handles this
    /// correctly with a trailing slash.) `XCTExpectFailure` keeps the suite
    /// green; once the prefix check is fixed this test fails with
    /// "expected failure not seen": remove the wrapper then.
    func testScopeShouldNotCoverSiblingFoldersWithTheSamePrefix() async throws {
        let (scanner, manager) = try makeScanner()
        let parent = canonicalURL(try makeTemporaryDirectory())
        let tango = parent.appendingPathComponent("Tango", isDirectory: true)
        let tango2 = parent.appendingPathComponent("Tango2", isDirectory: true)
        try writeFLAC("a.flac", in: tango, title: "A", audioBytes: 100)
        let b = try writeFLAC("b.flac", in: tango2, title: "B", audioBytes: 200)
        try await scanner.importFolder(tango)
        try await scanner.importFolder(tango2)
        try FileManager.default.removeItem(at: b)

        let summary = try await scanner.rescanLibrary(scope: try source(for: tango, in: manager))

        XCTExpectFailure("scope uses hasPrefix without a path separator") {
            XCTAssertEqual(summary.missingCount, 0)
        }
    }
}
