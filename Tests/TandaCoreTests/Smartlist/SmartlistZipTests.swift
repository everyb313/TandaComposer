//
//  SmartlistZipTests.swift
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

/// Tools → Export / Import → "Smartlists (ZIP)…".
final class SmartlistZipTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore() throws -> SmartlistStore {
        let root = canonicalURL(try makeTemporaryDirectory())
            .appendingPathComponent("Smartlists", isDirectory: true)

        return SmartlistStore(rootURLOverride: root)
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

    // MARK: - Free file name (the index counts up)

    func testAFreeNameIsKeptAsIs() throws {
        let dir = try makeTemporaryDirectory()
        let wanted = dir.appendingPathComponent("Smartlists.zip")

        XCTAssertEqual(SmartlistZip.firstFreeURL(for: wanted), wanted)
    }

    func testATakenNameGetsTheNextFreeNumber() throws {
        let dir = try makeTemporaryDirectory()
        let wanted = dir.appendingPathComponent("Smartlists.zip")

        _ = try writeData(Data("x".utf8), in: dir, named: "Smartlists.zip")
        XCTAssertEqual(SmartlistZip.firstFreeURL(for: wanted).lastPathComponent, "Smartlists_2.zip")

        _ = try writeData(Data("x".utf8), in: dir, named: "Smartlists_2.zip")
        XCTAssertEqual(SmartlistZip.firstFreeURL(for: wanted).lastPathComponent, "Smartlists_3.zip")
    }

    func testANameThatAlreadyEndsInANumberContinuesFromThere() throws {
        let dir = try makeTemporaryDirectory()
        _ = try writeData(Data("x".utf8), in: dir, named: "Smartlists_2.zip")

        let chosen = dir.appendingPathComponent("Smartlists_2.zip")

        XCTAssertEqual(SmartlistZip.firstFreeURL(for: chosen).lastPathComponent, "Smartlists_3.zip")
    }

    func testTheExtensionIsAlwaysZip() throws {
        let dir = try makeTemporaryDirectory()

        XCTAssertEqual(
            SmartlistZip.firstFreeURL(for: dir.appendingPathComponent("Smartlists")).lastPathComponent,
            "Smartlists.zip"
        )
    }

    // MARK: - Export and import

    func testExportAndImportMoveTheWholeTreeIntoImported() throws {
        let source = try makeStore()
        let folder = try source.createFolder(named: "F")
        try source.createRuleSet(named: "Top")
        try source.createRuleSet(named: "Inside", in: folder)
        let zip = try makeTemporaryDirectory().appendingPathComponent("Smartlists.zip")

        try SmartlistZip.export(copyTree: { try source.exportAll(to: $0) }, to: zip)

        let names = try fileNames(in: zip)
        XCTAssertTrue(names.contains("Smartlists/Top.json"), "\(names)")
        XCTAssertTrue(names.contains("Smartlists/F/Inside.json"), "\(names)")

        let target = try makeStore()
        XCTAssertFalse(target.importedFolderExists)

        try SmartlistZip.importTree(from: zip) { try target.importAll(from: $0) }

        XCTAssertTrue(target.importedFolderExists)
        let imported = try XCTUnwrap(target.root.children.first { $0.name == "Imported" })
        XCTAssertEqual(Set(imported.children.map(\.name)), ["F", "Top"],
                       "the ZIP's own top-level folder is not added as a level")
        let importedFolder = try XCTUnwrap(imported.children.first { $0.name == "F" })
        XCTAssertEqual(importedFolder.children.map(\.name), ["Inside"])
    }

    func testAZipWithoutSmartlistsChangesNothing() throws {
        let dir = try makeTemporaryDirectory()
        let folder = dir.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try writeData(Data("hello".utf8), in: folder, named: "notes.txt")
        let zip = dir.appendingPathComponent("Other.zip")
        try TandaLibraryExporter.zip(folder: folder, to: zip)

        let target = try makeStore()
        var bodyWasCalled = false

        XCTAssertThrowsError(try SmartlistZip.importTree(from: zip) { _ in bodyWasCalled = true }) { error in
            guard case SmartlistZipError.noSmartlistsInZip = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        XCTAssertFalse(bodyWasCalled)
        XCTAssertFalse(target.importedFolderExists, "a wrong ZIP must not touch the Imported folder")
    }

    func testTwoExportsOfTheSameNameDoNotOverwriteEachOther() throws {
        let store = try makeStore()
        try store.createRuleSet(named: "One")
        let dir = try makeTemporaryDirectory()
        let wanted = dir.appendingPathComponent("Smartlists.zip")

        let first = SmartlistZip.firstFreeURL(for: wanted)
        try SmartlistZip.export(copyTree: { try store.exportAll(to: $0) }, to: first)

        try store.createRuleSet(named: "Two")
        let second = SmartlistZip.firstFreeURL(for: wanted)
        try SmartlistZip.export(copyTree: { try store.exportAll(to: $0) }, to: second)

        XCTAssertEqual(first.lastPathComponent, "Smartlists.zip")
        XCTAssertEqual(second.lastPathComponent, "Smartlists_2.zip")
        XCTAssertFalse(try fileNames(in: first).contains("Smartlists/Two.json"))
        XCTAssertTrue(try fileNames(in: second).contains("Smartlists/Two.json"))
    }
}
