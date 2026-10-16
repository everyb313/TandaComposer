import XCTest
import Foundation
import SwiftUI

@MainActor
final class AppSettingsTests: XCTestCase {

    private func writeSettings(_ json: String, root: URL) throws {
        try json.write(to: root.appendingPathComponent("AppSettings.json"), atomically: true, encoding: .utf8)
    }

    // MARK: - Defaults

    func testDefaultsWithoutAFile() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()

            XCTAssertEqual(settings.appearanceMode, .auto)
            XCTAssertEqual(settings.setPaneWidth, 200)
            XCTAssertEqual(settings.libraryPaneWidth, 600)
            XCTAssertEqual(settings.smartlistsPaneWidth, 100)
            XCTAssertEqual(settings.orchestraSource, .artist)
            XCTAssertEqual(settings.singerSource, .albumArtist)
            XCTAssertTrue(settings.autoPickBestFile)
            XCTAssertEqual(settings.currentLibraryName, "Default")
        }
    }

    // MARK: - Save and load

    func testSavedValuesAreLoadedByANewInstance() throws {
        try withTemporaryAppRoot { _ in
            let first = AppSettings()
            first.appearanceMode = .dark
            first.setPaneWidth = 321
            first.libraryPaneWidth = 654.5
            first.smartlistsPaneWidth = 111
            first.orchestraSource = .grouping
            first.singerSource = .artist
            first.autoPickBestFile = false
            first.currentLibraryName = "Milongas"
            first.save()

            let second = AppSettings()

            XCTAssertEqual(second.appearanceMode, .dark)
            XCTAssertEqual(second.setPaneWidth, 321)
            XCTAssertEqual(second.libraryPaneWidth, 654.5)
            XCTAssertEqual(second.smartlistsPaneWidth, 111)
            XCTAssertEqual(second.orchestraSource, .grouping)
            XCTAssertEqual(second.singerSource, .artist)
            XCTAssertFalse(second.autoPickBestFile)
            XCTAssertEqual(second.currentLibraryName, "Milongas")
        }
    }

    func testSaveWritesTheDocumentedKeysToTheSettingsFile() throws {
        try withTemporaryAppRoot { root in
            AppSettings().save()

            let data = try Data(contentsOf: root.appendingPathComponent("AppSettings.json"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

            XCTAssertEqual(
                Set(object.keys),
                [
                    "setPaneWidth", "libraryPaneWidth", "smartlistsPaneWidth", "appearanceMode",
                    "orchestraSource", "singerSource", "autoPickBestFile", "currentLibraryName"
                ]
            )
            XCTAssertEqual(object["appearanceMode"] as? String, "auto")
            XCTAssertEqual(object["orchestraSource"] as? String, "artist")
            XCTAssertEqual(object["singerSource"] as? String, "albumArtist")
            XCTAssertEqual(object["currentLibraryName"] as? String, "Default")
        }
    }

    func testSaveCreatesMissingFolders() throws {
        try withTemporaryAppRoot { root in
            let nested = root.appendingPathComponent("not/yet/there", isDirectory: true)
            AppPaths.rootOverride = nested

            AppSettings().save()

            XCTAssertTrue(FileManager.default.fileExists(atPath: nested.appendingPathComponent("AppSettings.json").path))
        }
    }

    // MARK: - Reading existing files

    func testPartialFileKeepsDefaultsForMissingKeys() throws {
        try withTemporaryAppRoot { root in
            try writeSettings(#"{"setPaneWidth": 321}"#, root: root)

            let settings = AppSettings()

            XCTAssertEqual(settings.setPaneWidth, 321)
            XCTAssertEqual(settings.libraryPaneWidth, 600)
            XCTAssertEqual(settings.appearanceMode, .auto)
            XCTAssertTrue(settings.autoPickBestFile)
        }
    }

    func testInvalidValuesAreIgnored() throws {
        try withTemporaryAppRoot { root in
            try writeSettings(
                """
                {
                  "setPaneWidth": 0.5,
                  "libraryPaneWidth": -10,
                  "smartlistsPaneWidth": 1,
                  "appearanceMode": "sepia",
                  "orchestraSource": "genre",
                  "singerSource": "",
                  "currentLibraryName": ""
                }
                """,
                root: root
            )

            let settings = AppSettings()

            XCTAssertEqual(settings.setPaneWidth, 200, "widths of 1 or less are ignored")
            XCTAssertEqual(settings.libraryPaneWidth, 600)
            XCTAssertEqual(settings.smartlistsPaneWidth, 100)
            XCTAssertEqual(settings.appearanceMode, .auto)
            XCTAssertEqual(settings.orchestraSource, .artist)
            XCTAssertEqual(settings.singerSource, .albumArtist)
            XCTAssertEqual(settings.currentLibraryName, "Default")
        }
    }

    func testWidthJustAboveTheMinimumIsAccepted() throws {
        try withTemporaryAppRoot { root in
            try writeSettings(#"{"setPaneWidth": 1.5}"#, root: root)

            XCTAssertEqual(AppSettings().setPaneWidth, 1.5)
        }
    }

    func testCorruptFileFallsBackToDefaults() throws {
        try withTemporaryAppRoot { root in
            try writeSettings("this is not json", root: root)

            let settings = AppSettings()

            XCTAssertEqual(settings.setPaneWidth, 200)
            XCTAssertEqual(settings.appearanceMode, .auto)
        }
    }

    func testLoadingAlsoSetsTheActiveLibraryNameInAppPaths() throws {
        try withTemporaryAppRoot { root in
            try writeSettings(#"{"currentLibraryName": "Milongas"}"#, root: root)

            _ = AppSettings()

            XCTAssertEqual(AppPaths.currentLibraryName, "Milongas")
        }
    }

    // MARK: - Enums

    func testColorSchemeFollowsTheAppearanceMode() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()

            settings.appearanceMode = .light
            XCTAssertEqual(settings.colorScheme, .light)

            settings.appearanceMode = .dark
            XCTAssertEqual(settings.colorScheme, .dark)

            settings.appearanceMode = .auto
            XCTAssertNil(settings.colorScheme)
        }
    }

    /// These raw values are stored in AppSettings.json.
    func testRawValuesAreStable() {
        XCTAssertEqual(AppearanceMode.allCases.map(\.rawValue), ["light", "dark", "auto"])
        XCTAssertEqual(TagSource.allCases.map(\.rawValue), ["artist", "albumArtist", "grouping"])
    }
}
