import XCTest
import Foundation

/// The columns shared by the Tracks and Tandas tables: canonical order and
/// widths, the user's own order/widths (kept in UserDefaults), header titles
/// and the text of each cell.
///
/// The test runner has its own UserDefaults domain. The keys these tests
/// touch are cleared before and after each test.
@MainActor
final class LibraryColumnDefaultsTests: XCTestCase {

    private let allNames = [
        "Title", "Orchestra", "Singer", "Album", "Genre", "Year",
        "Type", "SRate", "R128 Gain", "Duration", "Grouping", "Comment"
    ]

    private func prepareDefaults() {
        clearStoredLibraryColumnDefaults()
        addTeardownBlock {
            clearStoredLibraryColumnDefaults()
        }
    }

    private func fullSong() -> Song {
        var song = makeFullSong(id: 1)
        song.replayGain = -7.5
        return song
    }

    // MARK: - Canonical columns

    func testColumnNamesAndOrderAreStable() {
        // The names are also the UserDefaults keys of saved widths/orders.
        XCTAssertEqual(LibraryColumn.allCases.map(\.rawValue), allNames)
        XCTAssertEqual(LibraryColumnDefaults.ordered, LibraryColumn.allCases)
    }

    func testEveryColumnHasAPositiveDefaultWidth() {
        for column in LibraryColumn.allCases {
            XCTAssertGreaterThan(column.defaultWidth, 0, column.rawValue)
        }
    }

    func testDefaultWidths() {
        let expected: [String: CGFloat] = [
            "Title": 220, "Orchestra": 180, "Singer": 160, "Album": 220,
            "Genre": 100, "Year": 60, "Type": 60, "SRate": 90,
            "R128 Gain": 90, "Duration": 80, "Grouping": 160, "Comment": 260
        ]

        for column in LibraryColumn.allCases {
            XCTAssertEqual(column.defaultWidth, expected[column.rawValue], column.rawValue)
        }
    }

    func testWidthsListMatchesTheColumns() {
        XCTAssertEqual(LibraryColumnDefaults.widths.map { $0.0 }, allNames)
        XCTAssertEqual(
            LibraryColumnDefaults.widths.map { $0.1 },
            LibraryColumn.allCases.map(\.defaultWidth)
        )
    }

    // MARK: - currentWidth

    func testCurrentWidthIsTheDefaultWhenNeverResized() {
        prepareDefaults()

        for column in LibraryColumn.allCases {
            XCTAssertEqual(LibraryColumnDefaults.currentWidth(for: column), column.defaultWidth, column.rawValue)
        }
    }

    func testCurrentWidthUsesTheSavedWidth() {
        prepareDefaults()
        UserDefaults.standard.set(150.5, forKey: "LibraryTable_ColumnWidth_Title")

        XCTAssertEqual(LibraryColumnDefaults.currentWidth(for: .title), 150.5)
        XCTAssertEqual(LibraryColumnDefaults.currentWidth(for: .artist), LibraryColumn.artist.defaultWidth)
    }

    func testANonPositiveSavedWidthIsIgnored() {
        prepareDefaults()
        UserDefaults.standard.set(0.0, forKey: "LibraryTable_ColumnWidth_Title")
        UserDefaults.standard.set(-40.0, forKey: "LibraryTable_ColumnWidth_Genre")

        XCTAssertEqual(LibraryColumnDefaults.currentWidth(for: .title), LibraryColumn.title.defaultWidth)
        XCTAssertEqual(LibraryColumnDefaults.currentWidth(for: .genre), LibraryColumn.genre.defaultWidth)
    }

    // MARK: - currentOrder

    func testCurrentOrderIsTheCanonicalOneWhenNeverReordered() {
        prepareDefaults()

        XCTAssertEqual(LibraryColumnDefaults.currentOrder(), LibraryColumn.allCases)
    }

    func testCurrentOrderFollowsTheSavedOrderAndAppendsMissingColumns() {
        prepareDefaults()
        UserDefaults.standard.set(["Year", "Title", "Singer"], forKey: "LibraryTable_ColumnOrder")

        let order = LibraryColumnDefaults.currentOrder()

        XCTAssertEqual(Array(order.prefix(3)), [.year, .title, .albumArtist])
        XCTAssertEqual(
            Array(order.dropFirst(3)),
            [.artist, .album, .genre, .type, .sampleRate, .replayGain, .duration, .grouping, .comment],
            "missing columns follow in canonical order"
        )
        XCTAssertEqual(order.count, LibraryColumn.allCases.count)
    }

    func testUnknownNamesInTheSavedOrderAreIgnored() {
        prepareDefaults()
        // "Status" is the Tracks table's own leading column.
        UserDefaults.standard.set(["Status", "Genre", "Removed Column", "Title"], forKey: "LibraryTable_ColumnOrder")

        let order = LibraryColumnDefaults.currentOrder()

        XCTAssertEqual(Array(order.prefix(2)), [.genre, .title])
        XCTAssertEqual(order.count, LibraryColumn.allCases.count)
    }

    func testASingleSavedColumnComesFirstAndNothingIsDuplicatedOrLost() {
        prepareDefaults()
        UserDefaults.standard.set(["Title"], forKey: "LibraryTable_ColumnOrder")

        let order = LibraryColumnDefaults.currentOrder()

        XCTAssertEqual(order.first, .title)
        XCTAssertEqual(Set(order), Set(LibraryColumn.allCases))
        XCTAssertEqual(order.filter { $0 == .title }.count, 1)
    }

    func testAMalformedSavedOrderFallsBackToTheDefault() {
        prepareDefaults()
        UserDefaults.standard.set([1, 2, 3], forKey: "LibraryTable_ColumnOrder")

        XCTAssertEqual(LibraryColumnDefaults.currentOrder(), LibraryColumn.allCases)
    }

    func testCurrentColumnsCombineOrderAndWidths() {
        prepareDefaults()
        UserDefaults.standard.set(["Year", "Title"], forKey: "LibraryTable_ColumnOrder")
        UserDefaults.standard.set(75.0, forKey: "LibraryTable_ColumnWidth_Year")

        let columns = LibraryColumnDefaults.currentColumns()

        XCTAssertEqual(columns.count, LibraryColumn.allCases.count)
        XCTAssertEqual(columns[0].0, "Year")
        XCTAssertEqual(columns[0].1, 75)
        XCTAssertEqual(columns[1].0, "Title")
        XCTAssertEqual(columns[1].1, LibraryColumn.title.defaultWidth)
    }

    // MARK: - headerTitle

    func testOrchestraAndSingerHeadersNameTheirSourceField() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()

            XCTAssertEqual(LibraryColumnDefaults.headerTitle(for: "Orchestra", settings: settings), "Orchestra (Artist)")
            XCTAssertEqual(LibraryColumnDefaults.headerTitle(for: "Singer", settings: settings), "Singer (AlbumArtist)")

            settings.orchestraSource = .grouping
            settings.singerSource = .artist

            XCTAssertEqual(LibraryColumnDefaults.headerTitle(for: "Orchestra", settings: settings), "Orchestra (Grouping)")
            XCTAssertEqual(LibraryColumnDefaults.headerTitle(for: "Singer", settings: settings), "Singer (Artist)")
        }
    }

    func testOtherHeadersAreShownAsTheyAre() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()

            for name in allNames where name != "Orchestra" && name != "Singer" {
                XCTAssertEqual(LibraryColumnDefaults.headerTitle(for: name, settings: settings), name)
            }
        }
    }

    // MARK: - displayValue

    private func value(_ column: String, _ song: Song, settings: AppSettings) -> String {
        LibraryColumnDefaults.displayValue(for: column, song: song, settings: settings)
    }

    func testDisplayValuesOfAFullSong() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let song = fullSong()

            XCTAssertEqual(value("Title", song, settings: settings), "Poema")
            XCTAssertEqual(value("Orchestra", song, settings: settings), "Alpha Trio")
            XCTAssertEqual(value("Singer", song, settings: settings), "Singer X")
            XCTAssertEqual(value("Album", song, settings: settings), "Album One")
            XCTAssertEqual(value("Genre", song, settings: settings), "Tango")
            XCTAssertEqual(value("Year", song, settings: settings), "1940")
            XCTAssertEqual(value("Type", song, settings: settings), "FLAC")
            XCTAssertEqual(value("SRate", song, settings: settings), "44.1 kHz")
            XCTAssertEqual(value("R128 Gain", song, settings: settings), "-7.5 dB")
            XCTAssertEqual(value("Duration", song, settings: settings), "3:35")
            XCTAssertEqual(value("Grouping", song, settings: settings), "Group A")
            XCTAssertEqual(value("Comment", song, settings: settings), "remark")
        }
    }

    func testEveryColumnOfASongWithoutMetadataIsEmpty() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            let bare = makeSong(path: "/Music/bare.flac")

            for name in allNames {
                XCTAssertEqual(value(name, bare, settings: settings), "", name)
            }
        }
    }

    func testOrchestraAndSingerCellsFollowTheSettings() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            settings.orchestraSource = .albumArtist
            settings.singerSource = .grouping
            let song = fullSong()

            XCTAssertEqual(value("Orchestra", song, settings: settings), "Singer X")
            XCTAssertEqual(value("Singer", song, settings: settings), "Group A")
        }
    }

    func testSampleRateIsShownInKilohertzWithOneDecimal() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            var song = fullSong()

            for (rate, text) in [(44_100, "44.1 kHz"), (48_000, "48.0 kHz"), (96_000, "96.0 kHz")] {
                song.sampleRate = rate

                XCTAssertEqual(value("SRate", song, settings: settings), text, "\(rate)")
            }
        }
    }

    func testDurationIsShownAsMinutesAndTwoDigitSeconds() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            var song = fullSong()

            for (seconds, text) in [(0, "0:00"), (5, "0:05"), (59, "0:59"), (60, "1:00"), (65, "1:05"), (215, "3:35"), (3_600, "60:00")] {
                song.duration = seconds

                XCTAssertEqual(value("Duration", song, settings: settings), text, "\(seconds)")
            }
        }
    }

    func testReplayGainIsShownWithOneDecimal() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()
            var song = fullSong()

            for (gain, text) in [(-7.5, "-7.5 dB"), (0.0, "0.0 dB"), (3.14, "3.1 dB")] {
                song.replayGain = gain

                XCTAssertEqual(value("R128 Gain", song, settings: settings), text, "\(gain)")
            }
        }
    }

    func testAnUnknownColumnIsEmpty() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertEqual(value("Status", fullSong(), settings: AppSettings()), "")
        }
    }
}

/// Removes every UserDefaults key the column code reads. Free function (not a
/// method) so the teardown block does not capture the test case.
nonisolated private func clearStoredLibraryColumnDefaults() {
    let defaults = UserDefaults.standard

    defaults.removeObject(forKey: "LibraryTable_ColumnOrder")

    for name in [
        "Title", "Orchestra", "Singer", "Album", "Genre", "Year",
        "Type", "SRate", "R128 Gain", "Duration", "Grouping", "Comment"
    ] {
        defaults.removeObject(forKey: "LibraryTable_ColumnWidth_\(name)")
    }
}
