import XCTest
import Foundation

final class OutputFormatterP2Tests: XCTestCase {
    private func sampleResults() -> [FileMetadataResult] {
        [
            FileMetadataResult(path: "/music/one.flac", rows: [
                MetadataRow(group: "Common", key: "title", value: "A, \"B\"\nC"),
                MetadataRow(group: "Common", key: "artist", value: "Zoë & Co <Live>")
            ])
        ]
    }

    func testJSONOutputIsValidAndPreservesSpecialCharacters() throws {
        let output = try OutputFormatter.json(sampleResults(), grouped: true)
        let data = try XCTUnwrap(output.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: String]])
        XCTAssertEqual(object["/music/one.flac"]?["Common:title"], "A, \"B\"\nC")
        XCTAssertEqual(object["/music/one.flac"]?["Common:artist"], "Zoë & Co <Live>")
    }

    func testCSVQuotesCommasQuotesAndNewlines() {
        let output = OutputFormatter.csv(sampleResults(), grouped: true)
        XCTAssertTrue(output.hasPrefix("file,group,key,value\n"))
        XCTAssertTrue(output.contains("\"A, \"\"B\"\"\nC\""))
        XCTAssertTrue(output.contains("\"Zoë & Co <Live>\"") == false,
                      "Angle brackets do not require CSV quoting.")
    }

    func testXMLAttributeValuesAreEscaped() throws {
        let output = OutputFormatter.xml(sampleResults(), grouped: true)
        XCTAssertTrue(output.contains("path=\"/music/one.flac\""))
        XCTAssertTrue(output.contains("key=\"title\""))
        XCTAssertTrue(output.contains("value=\"A, &quot;B&quot;\nC\""))
        XCTAssertTrue(output.contains("Zoë &amp; Co &lt;Live&gt;"))
    }

    func testPlainOutputSupportsGroupedAndUngroupedLabels() {
        let results = sampleResults()
        let grouped = OutputFormatter.plain(results, grouped: true)
        let ungrouped = OutputFormatter.plain(results, grouped: false)
        XCTAssertTrue(grouped.contains("Common:title: A, \"B\""))
        XCTAssertTrue(ungrouped.contains("title: A, \"B\""))
        XCTAssertFalse(ungrouped.contains("Common:title:"))
    }

    func testJSONUngroupedKeysOmitGroupPrefix() throws {
        let output = try OutputFormatter.json(sampleResults(), grouped: false)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: [String: String]])
        XCTAssertEqual(object["/music/one.flac"]?["title"], "A, \"B\"\nC")
        XCTAssertNil(object["/music/one.flac"]?["Common:title"])
    }
}
