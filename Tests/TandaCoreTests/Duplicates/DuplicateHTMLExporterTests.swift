import XCTest
import Foundation

@MainActor
final class DuplicateHTMLExporterTests: XCTestCase {

    private typealias Exporter = DuplicateHTMLExporter

    private let dash = "\u{2014}"

    // MARK: - Helpers

    private func song(
        _ id: Int64,
        path: String,
        title: String? = nil,
        artist: String? = nil,
        albumArtist: String? = nil,
        year: Int? = nil,
        sampleRate: Int? = nil,
        fileType: String? = nil
    ) -> Song {
        var song = makeSong(id: id, path: path, title: title, artist: artist, albumArtist: albumArtist, year: year)
        song.sampleRate = sampleRate
        song.fileType = fileType
        return song
    }

    private func cluster(_ key: String, _ songs: [Song]) -> DuplicateCluster {
        DuplicateCluster(key: key, songs: songs)
    }

    private func page(
        clusters: [DuplicateCluster],
        level: DuplicateLevel,
        libraryName: String = "Default",
        library: [Song] = []
    ) throws -> String {
        let url = try makeTemporaryDirectory().appendingPathComponent("report.html")
        try Exporter.export(clusters: clusters, level: level, libraryName: libraryName, librarySongs: library, to: url)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - sourceClassForPath

    func testTangoTimeTravelIsRecognizedInAllSpellings() {
        for path in [
            "/Music/Tango Time Travel/a.flac",
            "/Music/TANGO TIME TRAVEL/a.flac",
            "/Music/TangoTime Travel/a.flac",
            "/Music/tango_time_travel/a.flac"
        ] {
            XCTAssertEqual(Exporter.sourceClassForPath(path), "source-ttt", path)
        }
    }

    func testTangoTunesIsRecognizedInAllSpellings() {
        for path in ["/Music/Tango Tunes/a.flac", "/Music/TangoTunes/a.flac", "/Music/TANGO TUNES/a.flac"] {
            XCTAssertEqual(Exporter.sourceClassForPath(path), "source-tt", path)
        }
    }

    func testAStandaloneTTCountsAsTangoTunes() {
        for path in ["/Music/TT/a.flac", "/Music/tt_hits/a.flac", "/Music/Best of tt/a.flac", "TT - Album/a.flac", "/x/a.tt"] {
            XCTAssertEqual(Exporter.sourceClassForPath(path), "source-tt", path)
        }
    }

    func testTTInsideAWordIsNotASource() {
        for path in ["/Music/Butter/a.flac", "/Music/Attitude/a.flac", "/Music/tt1/a.flac", "/Music/a1tt/a.flac", "/Music/Mattis/a.flac"] {
            XCTAssertEqual(Exporter.sourceClassForPath(path), "", path)
        }
    }

    func testTangoTimeTravelWinsOverTT() {
        XCTAssertEqual(Exporter.sourceClassForPath("/Music/Tango Time Travel/TT/a.flac"), "source-ttt")
    }

    func testOrdinaryAndEmptyPathsHaveNoSourceClass() {
        XCTAssertEqual(Exporter.sourceClassForPath("/Music/Tango/a.flac"), "")
        XCTAssertEqual(Exporter.sourceClassForPath(""), "")
        XCTAssertEqual(Exporter.sourceClassForPath("t"), "")
    }

    // MARK: - sampleRateText

    func testSampleRatesAreShownInKilohertz() {
        XCTAssertEqual(Exporter.sampleRateText(nil), "")
        XCTAssertEqual(Exporter.sampleRateText(44_100), "44.1k")
        XCTAssertEqual(Exporter.sampleRateText(48_000), "48k")
        XCTAssertEqual(Exporter.sampleRateText(96_000), "96k")
        XCTAssertEqual(Exporter.sampleRateText(88_200), "88.2k")
        XCTAssertEqual(Exporter.sampleRateText(192_000), "192k")
        XCTAssertEqual(Exporter.sampleRateText(0), "0k")
    }

    // MARK: - escapeHTML

    func testEscapeHTML() {
        XCTAssertEqual(Exporter.escapeHTML("Tom & Jerry"), "Tom &amp; Jerry")
        XCTAssertEqual(Exporter.escapeHTML("<b>"), "&lt;b&gt;")
        XCTAssertEqual(Exporter.escapeHTML("say \"hi\""), "say &quot;hi&quot;")
        XCTAssertEqual(Exporter.escapeHTML("it's"), "it&#39;s")
        XCTAssertEqual(Exporter.escapeHTML("Caf\u{00E9} \u{1F3B6}"), "Caf\u{00E9} \u{1F3B6}")
        XCTAssertEqual(Exporter.escapeHTML(""), "")
    }

    func testEscapeHTMLDoesNotEscapeTwice() {
        XCTAssertEqual(Exporter.escapeHTML("&lt;"), "&amp;lt;", "ampersands are replaced first, once")
    }

    // MARK: - Folder helpers

    func testFolderBasenameAndParentFolder() {
        XCTAssertEqual(Exporter.folderBasename("/Music/Tango/Di Sarli"), "Di Sarli")
        XCTAssertEqual(Exporter.folderBasename("/Music/Tango/"), "Tango")
        XCTAssertEqual(Exporter.parentFolder(of: "/Music/A/x.flac"), "/Music/A")
        XCTAssertEqual(Exporter.parentFolder(of: "/x.flac"), "/")
    }

    func testFolderMetaIsSortedAndJoined() {
        XCTAssertEqual(
            Exporter.folderMeta(sampleRates: ["96k", "44.1k"], fileTypes: ["MP3", "FLAC"]),
            "44.1k, 96k \u{00B7} FLAC, MP3"
        )
        XCTAssertEqual(Exporter.folderMeta(sampleRates: [], fileTypes: []), " \u{00B7} ")
    }

    func testCombinedFieldShowsBothValuesOnlyWhenTheyDiffer() {
        XCTAssertEqual(Exporter.combinedField("Alpha", "Alpha"), "Alpha")
        XCTAssertEqual(Exporter.combinedField("Alpha", "Beta"), "Alpha / Beta")
        XCTAssertEqual(Exporter.combinedField("Alpha", nil), "Alpha / \(dash)")
        XCTAssertEqual(Exporter.combinedField("", "Beta"), "\(dash) / Beta")
        XCTAssertEqual(Exporter.combinedField(nil, nil), dash)
        XCTAssertEqual(Exporter.combinedField("", nil), dash)
    }

    func testComparisonFoldersAreUniqueAndSortedIgnoringCase() {
        let songs = [
            song(1, path: "/Music/b/1.flac"),
            song(2, path: "/Music/A/2.flac"),
            song(3, path: "/Music/b/3.flac")
        ]

        XCTAssertEqual(Exporter.comparisonFolders(in: cluster("k", songs)), ["/Music/A", "/Music/b"])
    }

    // MARK: - makeFolderBlocks

    private func twoFolderFixture() -> (clusters: [DuplicateCluster], library: [Song]) {
        let a1 = song(1, path: "/Music/A/1.flac", title: "Poema", artist: "Di Sarli", albumArtist: "Rufino", year: 1940, sampleRate: 44_100, fileType: "FLAC")
        let b1 = song(2, path: "/Music/B/1.mp3", title: "Poema", artist: "Di Sarli", albumArtist: "Rufino", year: 1941, sampleRate: 48_000, fileType: "MP3")
        let a2 = song(3, path: "/Music/A/2.flac", title: "Corazon", artist: "Di Sarli", albumArtist: "Rufino", year: 1940, sampleRate: 44_100, fileType: "FLAC")
        let b2 = song(4, path: "/Music/B/2.mp3", title: "Corazon", artist: "Di Sarli", albumArtist: nil, year: 1940, sampleRate: 48_000, fileType: "MP3")
        let clusters = [cluster("poema", [a1, b1]), cluster("corazon", [a2, b2])]
        let library = [a1, a2, b1, b2, song(5, path: "/Music/A/3.flac"), song(6, path: "/Music/A2/4.flac")]
        return (clusters, library)
    }

    func testFoldersThatShareClustersFormOneBlock() {
        let fixture = twoFolderFixture()

        let blocks = Exporter.makeFolderBlocks(clusters: fixture.clusters, librarySongs: fixture.library)

        XCTAssertEqual(blocks.count, 1)
        let block = blocks[0]
        XCTAssertEqual(block.id, "pair-0")
        XCTAssertEqual(block.folderA, "/Music/A")
        XCTAssertEqual(block.folderB, "/Music/B")
        XCTAssertEqual(block.folderNameA, "A")
        XCTAssertEqual(block.folderNameB, "B")
        XCTAssertEqual(block.metaA, "44.1k \u{00B7} FLAC")
        XCTAssertEqual(block.metaB, "48k \u{00B7} MP3")
    }

    func testTrackCountsComeFromTheLibraryAndRespectFolderBoundaries() {
        let fixture = twoFolderFixture()

        let block = Exporter.makeFolderBlocks(clusters: fixture.clusters, librarySongs: fixture.library)[0]

        XCTAssertEqual(block.trackCountA, 3, "A has 1.flac, 2.flac, 3.flac; A2 is another folder")
        XCTAssertEqual(block.trackCountB, 2)
    }

    func testRowsCombineBothSongsAndAreSortedByTitle() {
        let fixture = twoFolderFixture()

        let rows = Exporter.makeFolderBlocks(clusters: fixture.clusters, librarySongs: fixture.library)[0].rows

        XCTAssertEqual(rows.map(\.title), ["Corazon", "Poema"])
        XCTAssertEqual(rows[1].year, "1940 / 1941")
        XCTAssertEqual(rows[0].year, "1940")
        XCTAssertEqual(rows[1].sampleRate, "44.1k / 48k")
        XCTAssertEqual(rows[1].fileType, "FLAC / MP3")
        XCTAssertEqual(rows[1].filenameA, "1.flac")
        XCTAssertEqual(rows[1].filenameB, "1.mp3")
        XCTAssertEqual(rows[0].albumArtist, "Rufino / \(dash)")
        XCTAssertEqual(rows[0].artist, "Di Sarli")
    }

    func testClustersWithoutExactlyTwoFoldersAreSkipped() {
        let sameFolder = cluster("one", [song(1, path: "/Music/A/1.flac"), song(2, path: "/Music/A/2.flac")])
        let threeFolders = cluster("three", [
            song(3, path: "/Music/A/3.flac"),
            song(4, path: "/Music/B/3.flac"),
            song(5, path: "/Music/C/3.flac")
        ])

        let blocks = Exporter.makeFolderBlocks(clusters: [sameFolder, threeFolders], librarySongs: [])

        XCTAssertTrue(blocks.isEmpty)
    }

    func testBlocksAreSortedByRowCountThenFolderNames() {
        func pair(_ folderA: String, _ folderB: String, count: Int, base: Int64) -> [DuplicateCluster] {
            (0..<count).map { index in
                let id = base + Int64(index) * 2
                return cluster(
                    "\(folderA)-\(folderB)-\(index)",
                    [song(id, path: "\(folderA)/\(index).flac", title: "T\(index)"), song(id + 1, path: "\(folderB)/\(index).flac", title: "T\(index)")]
                )
            }
        }
        let clusters = pair("/M/c", "/M/d", count: 1, base: 100)
            + pair("/M/a", "/M/b", count: 3, base: 200)
            + pair("/M/a", "/M/e", count: 1, base: 300)

        let blocks = Exporter.makeFolderBlocks(clusters: clusters, librarySongs: [])

        XCTAssertEqual(blocks.map(\.rows.count), [3, 1, 1])
        XCTAssertEqual(blocks.map(\.folderA), ["/M/a", "/M/a", "/M/c"])
        XCTAssertEqual(blocks.map(\.folderB), ["/M/b", "/M/e", "/M/d"])
        XCTAssertEqual(blocks.map(\.id), ["pair-0", "pair-1", "pair-2"])
    }

    // MARK: - renderFolderComparison

    func testComparisonWithoutBlocksSaysSo() {
        let html = Exporter.renderFolderComparison(clusters: [], level: .songArtistAlbumArtist, librarySongs: [])

        XCTAssertTrue(html.contains("Folder Comparison \(dash) Level 3"))
        XCTAssertTrue(html.contains("No folder comparisons available."))
        XCTAssertFalse(html.contains("<table>"))
    }

    func testComparisonShowsSummaryTableAndDetailBlocks() {
        let fixture = twoFolderFixture()

        let html = Exporter.renderFolderComparison(clusters: fixture.clusters, level: .songArtistAlbumArtistAlbum, librarySongs: fixture.library)

        XCTAssertTrue(html.contains("Folder Comparison \(dash) Level 4"))
        XCTAssertTrue(html.contains("<th>Common Tracks</th>"))
        XCTAssertTrue(html.contains("href=\"#pair-0\""))
        XCTAssertTrue(html.contains("id=\"pair-0\""))
        XCTAssertTrue(html.contains("Subfolder A \u{00B7} 3 track(s)"))
        XCTAssertTrue(html.contains("Subfolder B \u{00B7} 2 track(s)"))
        XCTAssertTrue(html.contains("2 common track(s)"))
        XCTAssertTrue(html.contains("/Music/A"))
        XCTAssertTrue(html.contains("44.1k \u{00B7} FLAC"))
        XCTAssertTrue(html.contains("1.flac"))
        XCTAssertTrue(html.contains("1.mp3"))
    }

    func testComparisonEscapesFolderNames() {
        let a = song(1, path: "/Music/A & B/1.flac", title: "T")
        let b = song(2, path: "/Music/<C>/1.flac", title: "T")

        let html = Exporter.renderFolderComparison(clusters: [cluster("k", [a, b])], level: .songArtistAlbumArtist, librarySongs: [])

        XCTAssertTrue(html.contains("/Music/A &amp; B"))
        XCTAssertTrue(html.contains("/Music/&lt;C&gt;"))
        XCTAssertFalse(html.contains("<C>"))
    }

    // MARK: - Whole report

    private func reportFixture() -> [DuplicateCluster] {
        [
            cluster("tom", [
                song(1, path: "/Music/Tango Tunes/a.flac", title: "Tom & Jerry", artist: "Alpha Trio", albumArtist: "Singer X", year: 1940, sampleRate: 44_100, fileType: "FLAC"),
                song(2, path: "/Music/Other/a.flac", title: nil, artist: nil)
            ]),
            cluster("poema", [
                song(3, path: "/Music/A/p.flac", title: "Poema"),
                song(4, path: "/Music/B/p.flac", title: "Poema")
            ])
        ]
    }

    func testReportHeaderShowsLibraryLevelAndClusterCount() throws {
        let level = DuplicateLevel.songArtist

        let html = try page(clusters: reportFixture(), level: level, libraryName: "My & Lib")

        XCTAssertTrue(html.contains("<title>My &amp; Lib - Duplicate Report Level 2</title>"))
        XCTAssertTrue(html.contains("<h1>Duplicate Report</h1>"))
        XCTAssertTrue(html.contains("<strong>My &amp; Lib</strong>"))
        XCTAssertTrue(html.contains("<strong>\(Exporter.escapeHTML(level.title))</strong>"))
        XCTAssertTrue(html.contains("<strong>2</strong>"))
    }

    func testEveryClusterGetsANumberedTable() throws {
        let html = try page(clusters: reportFixture(), level: .songName)

        XCTAssertTrue(html.contains("Cluster 1"))
        XCTAssertTrue(html.contains("Cluster 2"))
        XCTAssertFalse(html.contains("Cluster 3"))
        for header in ["Song", "Artist", "Album Artist", "Grouping", "Year", "Album", "Type", "SRate", "Path"] {
            XCTAssertTrue(html.contains("<th>\(header)</th>"), header)
        }
    }

    func testRowsShowEscapedFieldsAndFormattedSampleRates() throws {
        let html = try page(clusters: reportFixture(), level: .songName)

        XCTAssertTrue(html.contains("<td>Tom &amp; Jerry</td>"))
        XCTAssertTrue(html.contains("<td>Alpha Trio</td>"))
        XCTAssertTrue(html.contains("<td>Singer X</td>"))
        XCTAssertTrue(html.contains("<td>1940</td>"))
        XCTAssertTrue(html.contains("<td>FLAC</td>"))
        XCTAssertTrue(html.contains("<td>44.1k</td>"))
        XCTAssertFalse(html.contains("Tom & Jerry"))
    }

    func testAMissingTitleIsShownAsTheFileNameAndMissingFieldsAreEmpty() throws {
        let html = try page(clusters: reportFixture(), level: .songName)

        XCTAssertTrue(html.contains("<td>a.flac</td>"))
        XCTAssertTrue(html.contains("<td></td>"))
    }

    func testPathCellsCarryTheSourceClass() throws {
        let html = try page(clusters: reportFixture(), level: .songName)

        XCTAssertTrue(html.contains("<td class=\"path source-tt\">/Music/Tango Tunes/a.flac</td>"))
        XCTAssertTrue(html.contains("<td class=\"path \">/Music/Other/a.flac</td>"))
    }

    func testFolderComparisonOnlyAppearsForLevelsThreeAndFour() throws {
        for level in [DuplicateLevel.songName, .songArtist] {
            let html = try page(clusters: reportFixture(), level: level)
            XCTAssertFalse(html.contains("class=\"folder-comparison\""), "level \(level.rawValue)")
        }
        for level in [DuplicateLevel.songArtistAlbumArtist, .songArtistAlbumArtistAlbum] {
            let html = try page(clusters: reportFixture(), level: level)
            XCTAssertTrue(html.contains("class=\"folder-comparison\""), "level \(level.rawValue)")
            XCTAssertTrue(html.contains("Folder Comparison \(dash) Level \(level.rawValue)"))
        }
    }

    func testAnEmptyReportIsStillAValidDocument() throws {
        let html = try page(clusters: [], level: .songName)

        XCTAssertTrue(html.contains("<strong>0</strong>"))
        XCTAssertFalse(html.contains("Cluster 1"))
        XCTAssertTrue(html.contains("</html>"))
    }

    func testExportToAMissingFolderThrows() throws {
        let url = try makeTemporaryDirectory().appendingPathComponent("no/such/folder/report.html")

        XCTAssertThrowsError(
            try Exporter.export(clusters: [], level: .songName, libraryName: "X", librarySongs: [], to: url)
        )
    }
}
