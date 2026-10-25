import XCTest
import Foundation

/// Small value types and computed properties that no other test touches:
/// appearance modes, tag-source identity, version strings, rescan phases and
/// a Tanda's identity.
@MainActor
final class SmallModelTests: XCTestCase {

    // MARK: - AppearanceMode

    func testAppearanceModesHaveStableIDsAndReadableNames() {
        XCTAssertEqual(AppearanceMode.allCases.map(\.id), ["light", "dark", "auto"])
        XCTAssertEqual(AppearanceMode.light.displayName, "Light")
        XCTAssertEqual(AppearanceMode.dark.displayName, "Dark")
        XCTAssertEqual(AppearanceMode.auto.displayName, "Auto")
    }

    // MARK: - TagSource

    func testTagSourceIDsAreTheRawValuesStoredInTheSettingsFile() {
        XCTAssertEqual(TagSource.allCases.map(\.id), ["artist", "albumArtist", "grouping"])
    }

    func testTagSourceDisplayNames() {
        XCTAssertEqual(TagSource.artist.displayName, "Artist")
        XCTAssertEqual(TagSource.albumArtist.displayName, "AlbumArtist")
        XCTAssertEqual(TagSource.grouping.displayName, "Grouping")
    }

    // MARK: - Version strings

    func testVersionAndBuildAreNeverEmpty() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()

            // The test runner has its own Info.plist, so only the shape is
            // checked; the fallbacks are "0.1.0" and "1".
            XCTAssertFalse(settings.appVersion.isEmpty)
            XCTAssertFalse(settings.buildNumber.isEmpty)
        }
    }

    // MARK: - RescanPhase

    func testRescanPhaseLabels() {
        XCTAssertEqual(
            RescanPhase.checkingKnownFiles.label,
            "Checking missing and updated references"
        )
        XCTAssertEqual(
            RescanPhase.checkingForNewFiles.label,
            "Checking for relocated and newly added files"
        )
    }

    // MARK: - Tanda

    func testATandaIsIdentifiedByTheFileItWasLoadedFrom() {
        let url = URL(fileURLWithPath: "/Tandas/Alpha Trio/Singer X/Alpha Trio_Tango_Singer X.json")
        let songs = makeSongs(3)

        let tanda = Tanda(
            name: "Alpha Trio_Tango_Singer X",
            songs: songs,
            comment: "",
            sourceFolder: "Alpha Trio/Singer X",
            sourceURL: url,
            savedAgainstLibraryName: nil
        )

        XCTAssertEqual(tanda.id, url)
    }

    func testTwoTandasWithTheSameNameInDifferentFoldersHaveDifferentIDs() {
        func tanda(in folder: String) -> Tanda {
            Tanda(
                name: "Same name",
                songs: makeSongs(3),
                comment: "",
                sourceFolder: folder,
                sourceURL: URL(fileURLWithPath: "/Tandas/\(folder)/Same name.json"),
                savedAgainstLibraryName: nil
            )
        }

        XCTAssertNotEqual(tanda(in: "A").id, tanda(in: "B").id)
    }
}
