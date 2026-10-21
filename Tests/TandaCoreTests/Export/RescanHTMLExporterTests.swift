import XCTest
import Foundation

@MainActor
final class RescanHTMLExporterTests: XCTestCase {

    // MARK: - Helpers

    private func html(
        _ summary: RescanSummary,
        libraryName: String = "Default"
    ) throws -> String {
        let dir = try makeTemporaryDirectory()
        let url = dir.appendingPathComponent("report.html")
        try RescanHTMLExporter.export(summary: summary, libraryName: libraryName, to: url)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func song(_ path: String, title: String? = nil, artist: String? = nil, albumArtist: String? = nil) -> Song {
        makeSong(path: path, title: title, artist: artist, albumArtist: albumArtist)
    }

    private func firstIndex(of text: String, in html: String) -> String.Index? {
        html.range(of: text)?.lowerBound
    }

    /// True if `label` is followed by `value` inside the summary tiles,
    /// whatever the whitespace in between.
    private func hasSummaryItem(_ label: String, _ value: Int, in html: String) -> Bool {
        let pattern = "\(label)\\s*</span>\\s*<span class=\"summary-value\">\\s*\(value)\\s*</span>"
        return html.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Document

    func testIsACompleteHTMLDocument() throws {
        let page = try html(RescanSummary())

        XCTAssertTrue(page.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(page.contains("<title>TandaComposer Rescan Report</title>"))
        XCTAssertTrue(page.contains("<h1>TandaComposer Rescan Report</h1>"))
        XCTAssertTrue(page.contains("</body>"))
        XCTAssertTrue(page.contains("</html>"))
    }

    func testTheLibraryNameIsShownAndEscaped() throws {
        let page = try html(RescanSummary(), libraryName: "Fast & <Loud>")

        XCTAssertTrue(page.contains("<strong>Fast &amp; &lt;Loud&gt;</strong>"))
        XCTAssertFalse(page.contains("<Loud>"))
    }

    // MARK: - Summary tiles

    func testSummaryTilesShowAllCounts() throws {
        var summary = RescanSummary()
        summary.unchangedCount = 17
        summary.updatedSongs = [song("/Music/u1.flac"), song("/Music/u2.flac")]
        summary.missingSongs = [song("/Music/m1.flac")]
        summary.relocatedTracks = [RelocatedTrack(oldPath: "/Old/r.flac", song: song("/New/r.flac"))]
        summary.newlyImportedSongs = [song("/Music/n1.flac"), song("/Music/n2.flac"), song("/Music/n3.flac")]
        summary.failedReads = [(URL(fileURLWithPath: "/Music/bad.flac"), NSError(domain: "T", code: 1))]

        let page = try html(summary)

        XCTAssertTrue(hasSummaryItem("Unchanged", 17, in: page))
        XCTAssertTrue(hasSummaryItem("Updated", 2, in: page))
        XCTAssertTrue(hasSummaryItem("Missing", 1, in: page))
        XCTAssertTrue(hasSummaryItem("Relocated", 1, in: page))
        XCTAssertTrue(hasSummaryItem("Newly Imported", 3, in: page))
        XCTAssertTrue(hasSummaryItem("Failed", 1, in: page))
    }

    func testAnEmptySummaryShowsZeros() throws {
        let page = try html(RescanSummary())

        for label in ["Unchanged", "Updated", "Missing", "Relocated", "Newly Imported", "Failed"] {
            XCTAssertTrue(hasSummaryItem(label, 0, in: page), label)
        }
    }

    // MARK: - Sections

    func testEverySectionShowsItsCountAndAnEmptyMarker() throws {
        let page = try html(RescanSummary())

        for title in ["Missing (0)", "Updated (0)", "Relocated (0)", "Newly Imported (0)", "Failed To Read (0)"] {
            XCTAssertTrue(page.contains(title), title)
        }
        XCTAssertEqual(page.components(separatedBy: "section-empty\">").count - 1, 5)
        XCTAssertFalse(page.contains("<table>"), "no tables without rows")
    }

    func testSectionsAppearInTheDocumentedOrder() throws {
        var summary = RescanSummary()
        summary.missingSongs = [song("/Music/m.flac")]
        summary.updatedSongs = [song("/Music/u.flac")]
        summary.relocatedTracks = [RelocatedTrack(oldPath: "/Old/r.flac", song: song("/New/r.flac"))]
        summary.newlyImportedSongs = [song("/Music/n.flac")]
        summary.failedReads = [(URL(fileURLWithPath: "/Music/bad.flac"), NSError(domain: "T", code: 1))]

        let page = try html(summary)

        let positions = ["Missing (1)", "Updated (1)", "Relocated (1)", "Newly Imported (1)", "Failed To Read (1)"]
            .compactMap { firstIndex(of: $0, in: page) }
        XCTAssertEqual(positions.count, 5)
        XCTAssertEqual(positions, positions.sorted())
    }

    func testSectionsHaveTheirColorClasses() throws {
        let page = try html(RescanSummary())

        for cssClass in ["section-missing", "section-updated", "section-relocated", "section-new", "section-failed"] {
            XCTAssertTrue(page.contains("class=\"section \(cssClass)\""), cssClass)
        }
    }

    // MARK: - Rows

    func testSongRowsShowTitleArtistAlbumArtistAndPath() throws {
        var summary = RescanSummary()
        summary.missingSongs = [
            song("/Music/a.flac", title: "Poema", artist: "Alpha Trio", albumArtist: "Singer X"),
            song("/Music/no-tags.flac")
        ]

        let page = try html(summary)

        XCTAssertTrue(page.contains("Poema"))
        XCTAssertTrue(page.contains("Alpha Trio"))
        XCTAssertTrue(page.contains("Singer X"))
        XCTAssertTrue(page.contains("/Music/a.flac"))
        XCTAssertTrue(page.contains("no-tags.flac"), "a missing title is replaced by the file name")

        // The stylesheet comment contains a dash too, so compare with an empty report.
        let baseline = try html(RescanSummary())
        func dashes(_ text: String) -> Int { text.components(separatedBy: "\u{2014}").count - 1 }
        XCTAssertEqual(dashes(page) - dashes(baseline), 2, "missing artist and album artist show a dash")
        XCTAssertTrue(page.contains("<th>Album Artist</th>"))
    }

    func testRowsAreEscaped() throws {
        var summary = RescanSummary()
        summary.updatedSongs = [song("/Music/A & B/<x>.flac", title: "Tom & \"Jerry\"", artist: "It's <b>bold</b>")]

        let page = try html(summary)

        XCTAssertTrue(page.contains("/Music/A &amp; B/&lt;x&gt;.flac"))
        XCTAssertTrue(page.contains("Tom &amp; &quot;Jerry&quot;"))
        XCTAssertTrue(page.contains("It&#39;s &lt;b&gt;bold&lt;/b&gt;"))
        XCTAssertFalse(page.contains("<x>"))
        XCTAssertFalse(page.contains("<b>bold</b>"))
    }

    func testRelocatedRowsShowOldAndNewPath() throws {
        var summary = RescanSummary()
        summary.relocatedTracks = [
            RelocatedTrack(oldPath: "/Old/a & b.flac", song: song("/New/a & b.flac", title: "Poema"))
        ]

        let page = try html(summary)

        XCTAssertTrue(page.contains("<th>Old Path</th>"))
        XCTAssertTrue(page.contains("<th>New Path</th>"))
        XCTAssertTrue(page.contains("/Old/a &amp; b.flac"))
        XCTAssertTrue(page.contains("/New/a &amp; b.flac"))
        XCTAssertTrue(page.contains("Poema"))
    }

    func testFailedRowsShowThePathAndTheEscapedErrorText() throws {
        var summary = RescanSummary()
        let error = NSError(domain: "T", code: 1, userInfo: [NSLocalizedDescriptionKey: "Boom <bad> & worse"])
        summary.failedReads = [(URL(fileURLWithPath: "/Music/bad.flac"), error)]

        let page = try html(summary)

        XCTAssertTrue(page.contains("/Music/bad.flac"))
        XCTAssertTrue(page.contains("Boom &lt;bad&gt; &amp; worse"))
        XCTAssertFalse(page.contains("<bad>"))
    }

    func testEveryRowOfASectionIsListed() throws {
        var summary = RescanSummary()
        summary.newlyImportedSongs = (1...25).map { song("/Music/new\($0).flac", title: "New \($0)") }

        let page = try html(summary)

        XCTAssertTrue(page.contains("Newly Imported (25)"))
        for number in [1, 13, 25] {
            XCTAssertTrue(page.contains("New \(number)"), "row \(number)")
        }
    }

    // MARK: - Writing

    func testExportToAMissingFolderThrows() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appendingPathComponent("no/such/folder/report.html")

        XCTAssertThrowsError(try RescanHTMLExporter.export(summary: RescanSummary(), libraryName: "X", to: url))
    }

    func testExportReplacesAnExistingReport() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appendingPathComponent("report.html")
        try "old report".write(to: url, atomically: true, encoding: .utf8)

        try RescanHTMLExporter.export(summary: RescanSummary(), libraryName: "X", to: url)

        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("old report"))
    }
}
