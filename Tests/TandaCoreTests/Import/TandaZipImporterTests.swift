import XCTest
import Foundation

/// Builds real ZIP files with `/usr/bin/zip` and reads them with the
/// importer (which uses `/usr/bin/unzip`). Both ship with macOS.
@MainActor
final class TandaZipImporterTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a ZIP with the given relative paths and text contents.
    private func makeZip(_ files: [String: String]) throws -> URL {
        let work = try makeTemporaryDirectory()
        let content = work.appendingPathComponent("content", isDirectory: true)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)

        var topLevel = Set<String>()
        for (path, text) in files {
            let url = content.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
            topLevel.insert(path.split(separator: "/").first.map(String.init) ?? path)
        }

        let zip = work.appendingPathComponent("shared.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = content
        process.arguments = ["-qr", zip.path] + topLevel.sorted()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "zip failed")
        return zip
    }

    private func read(_ files: [String: String]) throws -> SharedTandaScan {
        try TandaZipImporter.read(zipURL: try makeZip(files))
    }

    private let threeTracks = "Alpha Trio - Song One\nAlpha Trio - Song Two\nAlpha Trio - Song Three\n"

    private func tanda(_ named: String, in scan: SharedTandaScan) throws -> SharedTanda {
        try XCTUnwrap(scan.tandas.first { $0.fileName == named }, "no Tanda file \(named)")
    }

    // MARK: - Folders

    func testFlatZipHasNoFolders() throws {
        let scan = try read(["Set A.txt": threeTracks])

        XCTAssertEqual(scan.tandas.count, 1)
        let tanda = try XCTUnwrap(scan.tandas.first)
        XCTAssertEqual(tanda.folder, "")
        XCTAssertEqual(tanda.subfolder, "")
        XCTAssertEqual(tanda.fileName, "Set A")
        XCTAssertEqual(tanda.name, "Set A")
        XCTAssertNil(tanda.comment)
        XCTAssertEqual(tanda.tracks.count, 3)
        XCTAssertTrue(scan.unreadable.isEmpty)
    }

    func testFirstFolderIsTheFolderAndTheRestIsTheSubfolder() throws {
        let scan = try read([
            "Di Sarli/Set B.txt": threeTracks,
            "Di Sarli/1940s/Set C.txt": threeTracks,
            "A/B/C/Set D.txt": threeTracks
        ])

        let b = try tanda("Set B", in: scan)
        XCTAssertEqual(b.folder, "Di Sarli")
        XCTAssertEqual(b.subfolder, "")

        let c = try tanda("Set C", in: scan)
        XCTAssertEqual(c.folder, "Di Sarli")
        XCTAssertEqual(c.subfolder, "1940s")

        let d = try tanda("Set D", in: scan)
        XCTAssertEqual(d.folder, "A")
        XCTAssertEqual(d.subfolder, "B/C")
    }

    func testATandasWrapperFolderIsRemoved() throws {
        let scan = try read([
            "Tandas/Di Sarli/Set B.txt": threeTracks,
            "Tandas/Set A.txt": threeTracks,
            "Tandas/Di Sarli/1940s/Set C.txt": threeTracks
        ])

        XCTAssertEqual(try tanda("Set A", in: scan).folder, "")
        XCTAssertEqual(try tanda("Set B", in: scan).folder, "Di Sarli")
        XCTAssertEqual(try tanda("Set C", in: scan).subfolder, "1940s")
    }

    func testTheWrapperNameIsMatchedIgnoringCase() throws {
        let scan = try read(["tandas/Di Sarli/Set B.txt": threeTracks])

        XCTAssertEqual(try tanda("Set B", in: scan).folder, "Di Sarli")
    }

    func testTandasIsOnlyAWrapperWhenEveryFileIsInsideIt() throws {
        let scan = try read([
            "Tandas/Set A.txt": threeTracks,
            "Other/Set B.txt": threeTracks
        ])

        XCTAssertEqual(try tanda("Set A", in: scan).folder, "Tandas")
        XCTAssertEqual(try tanda("Set B", in: scan).folder, "Other")
    }

    // MARK: - File types

    func testM3U8AndM3UFilesAreRead() throws {
        let list = "#EXTM3U\n/Music/a.flac\n/Music/b.flac\n/Music/c.flac\n"

        let scan = try read(["One.m3u8": list, "Two.m3u": list])

        XCTAssertEqual(scan.tandas.map(\.fileName), ["One", "Two"])
        XCTAssertEqual(scan.tandas[0].tracks.map(\.path), ["/Music/a.flac", "/Music/b.flac", "/Music/c.flac"])
        XCTAssertEqual(scan.tandas[0].name, "One", "playlists have no header; the file name is the name")
        XCTAssertNil(scan.tandas[0].comment)
    }

    func testExtensionsAreMatchedIgnoringCase() throws {
        let scan = try read(["Upper.TXT": threeTracks, "Mixed.M3u8": "/Music/a.flac\n"])

        XCTAssertEqual(Set(scan.tandas.map(\.fileName)), ["Upper", "Mixed"])
    }

    func testOtherFilesAreIgnored() throws {
        let scan = try read([
            "Good.txt": threeTracks,
            "cover.jpg": "not an image",
            "data.json": "{}",
            "readme.md": "# hi"
        ])

        XCTAssertEqual(scan.tandas.map(\.fileName), ["Good"])
        XCTAssertTrue(scan.unreadable.isEmpty, "foreign files are not reported either")
    }

    func testMacOSMetadataIsIgnored() throws {
        let scan = try read([
            "Good.txt": threeTracks,
            "._Good.txt": "binary resource fork",
            "__MACOSX/Good.txt": threeTracks,
            "__MACOSX/Folder/._Other.txt": "junk"
        ])

        XCTAssertEqual(scan.tandas.map(\.fileName), ["Good"])
        XCTAssertTrue(scan.unreadable.isEmpty)
    }

    // MARK: - Header lines

    func testTandaAndCommentHeaderLinesSetNameAndComment() throws {
        let text = """
        # Tanda: Di Sarli Fast
        # Comment: Good for the start of the evening
        Alpha Trio - Song One
        Alpha Trio - Song Two
        Alpha Trio - Song Three
        """

        let scan = try read(["file name.txt": text])

        let tanda = try XCTUnwrap(scan.tandas.first)
        XCTAssertEqual(tanda.name, "Di Sarli Fast")
        XCTAssertEqual(tanda.comment, "Good for the start of the evening")
        XCTAssertEqual(tanda.fileName, "file name", "the file name stays available for the target file")
        XCTAssertEqual(tanda.tracks.count, 3, "header lines are not tracks")
    }

    func testHeaderKeywordsIgnoreCaseAndExtraHashes() throws {
        let text = "## TANDA:   Loud Name  \n#comment: lower case\n" + threeTracks

        let tanda = try XCTUnwrap(try read(["x.txt": text]).tandas.first)

        XCTAssertEqual(tanda.name, "Loud Name")
        XCTAssertEqual(tanda.comment, "lower case")
    }

    func testEmptyHeaderValuesAreIgnored() throws {
        let text = "# Tanda:\n# Comment:   \n" + threeTracks

        let tanda = try XCTUnwrap(try read(["Fallback.txt": text]).tandas.first)

        XCTAssertEqual(tanda.name, "Fallback")
        XCTAssertNil(tanda.comment)
    }

    func testOrdinaryCommentLinesDoNotChangeTheName() throws {
        let text = "# just a remark\n# Tandas are great\n" + threeTracks

        let tanda = try XCTUnwrap(try read(["Plain.txt": text]).tandas.first)

        XCTAssertEqual(tanda.name, "Plain")
        XCTAssertNil(tanda.comment)
    }

    func testHeaderIsFoundAfterAByteOrderMark() throws {
        let work = try makeTemporaryDirectory()
        let content = work.appendingPathComponent("content", isDirectory: true)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        try Data(bom + Array(("# Tanda: With BOM\n" + threeTracks).utf8)).write(to: content.appendingPathComponent("b.txt"))
        let zip = work.appendingPathComponent("bom.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = content
        process.arguments = ["-qr", zip.path, "b.txt"]
        try process.run()
        process.waitUntilExit()

        let scan = try TandaZipImporter.read(zipURL: zip)

        XCTAssertEqual(scan.tandas.first?.name, "With BOM")
    }

    // MARK: - Unreadable files

    func testFilesWithoutAnyTrackAreReported() throws {
        let scan = try read([
            "Good.txt": threeTracks,
            "Empty.txt": "",
            "Folder/OnlyComments.txt": "# nothing here\n# really\n",
            "Blank.m3u8": "#EXTM3U\n\n"
        ])

        XCTAssertEqual(scan.tandas.map(\.fileName), ["Good"])
        XCTAssertEqual(Set(scan.unreadable), ["Empty.txt", "Folder/OnlyComments.txt", "Blank.m3u8"])
    }

    func testUnreadableFilesAreReportedWithTheirFullPathInTheZip() throws {
        let scan = try read(["Tandas/Di Sarli/Empty.txt": ""])

        XCTAssertEqual(scan.unreadable, ["Tandas/Di Sarli/Empty.txt"])
    }

    func testAZipWithoutTandasGivesAnEmptyScan() throws {
        let scan = try read(["picture.jpg": "x"])

        XCTAssertTrue(scan.tandas.isEmpty)
        XCTAssertTrue(scan.unreadable.isEmpty)
    }

    // MARK: - Order

    func testTandasAreSortedNaturallyWithinAndAcrossFolders() throws {
        let scan = try read([
            "B/Set 1.txt": threeTracks,
            "A/Set 10.txt": threeTracks,
            "A/Set 2.txt": threeTracks
        ])

        let order = scan.tandas.map { "\($0.folder)/\($0.fileName)" }

        XCTAssertEqual(order, ["A/Set 2", "A/Set 10", "B/Set 1"])
    }

    func testTracksKeepTheirOrderAndIndexes() throws {
        let scan = try read(["Set.txt": "Alpha Trio - One\nBeta Band - Two\nGamma Sextet - Three\n"])

        let tracks = try XCTUnwrap(scan.tandas.first).tracks
        XCTAssertEqual(tracks.map(\.title), ["One", "Two", "Three"])
        XCTAssertEqual(tracks.map(\.sourceIndex), [0, 1, 2])
    }

    // MARK: - Errors

    func testANonZipFileThrows() throws {
        let dir = try makeTemporaryDirectory()
        let notAZip = try writeText("this is not a zip", in: dir, named: "fake.zip")

        do {
            _ = try TandaZipImporter.read(zipURL: notAZip)
            XCTFail("expected unzipFailed")
        } catch TandaZipError.unzipFailed(let message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAMissingZipThrows() throws {
        let dir = try makeTemporaryDirectory()

        XCTAssertThrowsError(try TandaZipImporter.read(zipURL: dir.appendingPathComponent("nope.zip")))
    }

    func testErrorDescriptionMentionsTheProblem() {
        XCTAssertEqual(
            TandaZipError.unzipFailed("bad").errorDescription,
            "The ZIP file could not be opened: bad"
        )
    }
}
