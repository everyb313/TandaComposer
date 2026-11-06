//
//  TandaLibraryJSONExporterTests.swift
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

import XCTest
import Foundation

/// Tools → Export → "TandaLibrary (JSON-ZIP)…": the Tandas folder as it
/// is, one header insertion for files that predate the convention.
@MainActor
final class TandaLibraryJSONExporterTests: XCTestCase {

    // MARK: - Helpers

    private func songs(_ count: Int) -> [Song] {
        (1...count).map {
            makeSong(id: Int64($0), path: "/Music/\($0).flac", title: "T\($0)")
        }
    }

    /// Writes a Tanda file with the normal writer.
    @discardableResult
    private func writeTanda(
        in root: URL,
        folder: String? = nil,
        name: String,
        orchestra: TagSource? = .artist,
        singer: TagSource? = .albumArtist
    ) throws -> URL {

        var directory = root
        if let folder {
            directory = root.appendingPathComponent(folder, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(name).appendingPathExtension("json")

        try TandaMetadataExporter.export(
            songs: songs(3),
            tandaName: name,
            to: url,
            savedAt: wholeSecondDate,
            comment: "c",
            savedAgainstLibraryName: "Lib",
            orchestraSource: orchestra,
            singerSource: singer
        )

        return url
    }

    /// A file as older versions wrote it: no convention keys at all.
    @discardableResult
    private func writeOldTanda(in root: URL, folder: String? = nil, name: String) throws -> URL {
        let url = try writeTanda(in: root, folder: folder, name: name, orchestra: nil, singer: nil)
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(
            of: #"[ \t]*"orchestraSource" : null,\n"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"[ \t]*"singerSource" : null,\n"#, with: "", options: .regularExpression)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func export(
        _ root: URL,
        into staging: URL? = nil,
        orchestra: TagSource = .artist,
        singer: TagSource = .albumArtist
    ) throws -> (summary: TandaLibraryJSONExporter.Summary, staging: URL) {
        let target = try staging ?? makeTemporaryDirectory().appendingPathComponent("Tandas", isDirectory: true)
        let summary = try TandaLibraryJSONExporter.export(
            to: target, orchestraSource: orchestra, singerSource: singer, tandasRoot: root
        )
        return (summary, target)
    }

    private func fileNames(in zip: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", zip.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    private func loadHeader(_ url: URL) throws -> TandaMetadataExport {
        try TandaMetadataExporter.load(from: url)
    }

    // MARK: - Copy as it is

    func testAFileThatRecordsTheConventionIsCopiedByteForByte() throws {
        let root = try makeTemporaryDirectory()
        let original = try writeTanda(in: root, name: "Calo_Tango")

        let result = try export(root)

        let copy = result.staging.appendingPathComponent("Calo_Tango.json")
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: original))
        XCTAssertEqual(result.summary.tandaCount, 1)
        XCTAssertEqual(result.summary.stampedCount, 0)
    }

    func testTheFolderStructureIsKept() throws {
        let root = try makeTemporaryDirectory()
        try writeTanda(in: root, name: "Top")
        try writeTanda(in: root, folder: "Biagi/Acuna", name: "Biagi_Tango_Acuna")

        let result = try export(root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.staging.appendingPathComponent("Top.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.staging.appendingPathComponent("Biagi/Acuna/Biagi_Tango_Acuna.json").path))
        XCTAssertEqual(result.summary.tandaCount, 2)
        XCTAssertEqual(result.summary.folderCount, 1)
    }

    // MARK: - Older files get the two header lines in the copy only

    func testAnOldFileGetsTheConventionInTheCopyAndTheOriginalStaysUntouched() throws {
        let root = try makeTemporaryDirectory()
        let original = try writeOldTanda(in: root, name: "Old")
        let before = try Data(contentsOf: original)
        XCTAssertNil(try loadHeader(original).orchestraSource, "test setup: an old file")

        let result = try export(root, orchestra: .grouping, singer: .artist)

        let copy = try loadHeader(result.staging.appendingPathComponent("Old.json"))
        XCTAssertEqual(copy.orchestraSource, .grouping)
        XCTAssertEqual(copy.singerSource, .artist)
        XCTAssertEqual(copy.songs.count, 3)
        XCTAssertEqual(result.summary.stampedCount, 1)
        XCTAssertEqual(try Data(contentsOf: original), before, "the original on disk is never touched")
    }

    func testNothingButTheTwoInsertedLinesChanges() throws {
        let root = try makeTemporaryDirectory()
        let original = try writeOldTanda(in: root, name: "Old")

        let result = try export(root)

        let copyText = try String(contentsOf: result.staging.appendingPathComponent("Old.json"), encoding: .utf8)
        let withoutInserted = copyText
            .replacingOccurrences(of: #"[ \t]*"orchestraSource" : "artist",\n"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]*"singerSource" : "albumArtist",\n"#, with: "", options: .regularExpression)

        XCTAssertEqual(withoutInserted, try String(contentsOf: original, encoding: .utf8))
    }

    func testTheInsertedLinesSitRightAfterTheTandaName() throws {
        let root = try makeTemporaryDirectory()
        try writeOldTanda(in: root, name: "Old")

        let result = try export(root)

        let text = try String(contentsOf: result.staging.appendingPathComponent("Old.json"), encoding: .utf8)
        let nameAt = try XCTUnwrap(text.range(of: "\"tandaName\""))
        let orchestraAt = try XCTUnwrap(text.range(of: "\"orchestraSource\""))
        let singerAt = try XCTUnwrap(text.range(of: "\"singerSource\""))
        let libraryAt = try XCTUnwrap(text.range(of: "\"savedAgainstLibraryName\""))

        XCTAssertLessThan(nameAt.lowerBound, orchestraAt.lowerBound)
        XCTAssertLessThan(orchestraAt.lowerBound, singerAt.lowerBound)
        XCTAssertLessThan(singerAt.lowerBound, libraryAt.lowerBound)
    }

    func testNullValuesAreFilledIn() throws {
        let root = try makeTemporaryDirectory()
        try writeTanda(in: root, name: "Unknown", orchestra: nil, singer: nil)   // written as null

        let result = try export(root, orchestra: .artist, singer: .albumArtist)

        let text = try String(contentsOf: result.staging.appendingPathComponent("Unknown.json"), encoding: .utf8)
        XCTAssertTrue(text.contains("\"orchestraSource\" : \"artist\""), text)
        XCTAssertFalse(text.contains("null,\n  \"singerSource\""), text)
        XCTAssertEqual(try loadHeader(result.staging.appendingPathComponent("Unknown.json")).singerSource, .albumArtist)
        XCTAssertEqual(result.summary.stampedCount, 1)
    }

    func testAValueThatIsAlreadyThereIsNeverReplaced() throws {
        let root = try makeTemporaryDirectory()
        // orchestra recorded (grouping), singer missing
        let url = try writeTanda(in: root, name: "Partial", orchestra: .grouping, singer: nil)
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: #"[ \t]*"singerSource" : null,\n"#, with: "", options: .regularExpression)
        try text.write(to: url, atomically: true, encoding: .utf8)

        let result = try export(root, orchestra: .artist, singer: .albumArtist)

        let copy = try loadHeader(result.staging.appendingPathComponent("Partial.json"))
        XCTAssertEqual(copy.orchestraSource, .grouping, "what the file says wins")
        XCTAssertEqual(copy.singerSource, .albumArtist)
    }

    // MARK: - Files that are not Tandas

    func testAFileThatIsNotATandaIsReportedAndNotCopied() throws {
        let root = try makeTemporaryDirectory()
        try writeTanda(in: root, folder: "Biagi", name: "Good")
        let folder = root.appendingPathComponent("Biagi", isDirectory: true)
        _ = try writeText("{}", in: folder, named: "bad.json")
        _ = try writeText("notes", in: folder, named: "readme.txt")

        let result = try export(root)

        XCTAssertEqual(result.summary.unreadableFiles, ["Biagi/bad.json"])
        XCTAssertEqual(result.summary.tandaCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.staging.appendingPathComponent("Biagi/bad.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.staging.appendingPathComponent("Biagi/readme.txt").path))
    }

    func testAMissingTandasFolderGivesAnEmptySummary() throws {
        let missing = try makeTemporaryDirectory().appendingPathComponent("NoTandas", isDirectory: true)

        let result = try export(missing)

        XCTAssertEqual(result.summary, TandaLibraryJSONExporter.Summary())
    }

    // MARK: - ZIP layout

    func testTheZipHasTandasAsItsTopLevelFolder() throws {
        let root = try makeTemporaryDirectory()
        try writeTanda(in: root, folder: "Biagi/Acuna", name: "T")
        let result = try export(root)
        let zip = try makeTemporaryDirectory().appendingPathComponent("TandaLibrary.zip")

        try TandaLibraryExporter.zip(folder: result.staging, to: zip)

        let names = try fileNames(in: zip)
        XCTAssertTrue(names.contains("Tandas/Biagi/Acuna/T.json"), "\(names)")
    }

    // MARK: - File name (the number counts up)

    func testAFreeNameIsKeptAsIs() throws {
        let dir = try makeTemporaryDirectory()
        let wanted = dir.appendingPathComponent("TandaLibrary 2026-11-05.zip")

        XCTAssertEqual(TandaLibraryJSONExporter.firstFreeURL(for: wanted), wanted)
    }

    func testATakenNameGetsTheNextFreeNumber() throws {
        let dir = try makeTemporaryDirectory()
        let wanted = dir.appendingPathComponent("TandaLibrary 2026-11-05.zip")

        _ = try writeData(Data("x".utf8), in: dir, named: "TandaLibrary 2026-11-05.zip")
        XCTAssertEqual(TandaLibraryJSONExporter.firstFreeURL(for: wanted).lastPathComponent, "TandaLibrary 2026-11-05_2.zip")

        _ = try writeData(Data("x".utf8), in: dir, named: "TandaLibrary 2026-11-05_2.zip")
        XCTAssertEqual(TandaLibraryJSONExporter.firstFreeURL(for: wanted).lastPathComponent, "TandaLibrary 2026-11-05_3.zip")
    }

    func testTheExtensionIsAlwaysZip() throws {
        let dir = try makeTemporaryDirectory()

        XCTAssertEqual(
            TandaLibraryJSONExporter.firstFreeURL(for: dir.appendingPathComponent("TandaLibrary")).lastPathComponent,
            "TandaLibrary.zip"
        )
    }
}
