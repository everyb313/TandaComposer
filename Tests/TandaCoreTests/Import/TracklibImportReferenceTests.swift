import XCTest
import Foundation

/// The reference list of known orchestras and singers
/// (`tracklib_import_reference.json`).
///
/// In the test bundle `Bundle.main` is the test runner, which does not
/// contain that file, so `TracklibImportReferenceStore` runs on its built-in
/// empty fallback here. These tests therefore cover
/// - the fallback behavior (no data, but a visible `loadProblem`),
/// - the Codable model, and
/// - the integrity of the real JSON file, read from the test bundle.
///
/// The recognizer itself (matching rules) is covered by
/// `NameRecognizerTests` in `OPTIONAL_needs_3_edits/`.
@MainActor
final class TracklibImportReferenceTests: XCTestCase {

    // MARK: - Helpers

    /// The reference file as the test bundle sees it.
    ///
    /// Read from the test bundle (`Bundle(for:)`), NOT from the source tree:
    /// the test runner is not allowed to read protected folders such as
    /// ~/Desktop ("Operation not permitted"). The file gets into the test
    /// bundle because TandaCore is a synchronized folder of this target.
    /// If it is not there, the tests are skipped with a hint.
    private func loadReferenceFile() throws -> TracklibImportReference {
        let bundle = Bundle(for: TracklibImportReferenceTests.self)

        guard let url = bundle.url(
            forResource: "tracklib_import_reference",
            withExtension: "json"
        ) else {
            throw XCTSkip(
                "tracklib_import_reference.json is not in the test bundle "
                + "(TandaCoreTests > Build Phases > Copy Bundle Resources)"
            )
        }

        let data = try Data(contentsOf: url)

        return try JSONDecoder().decode(TracklibImportReference.self, from: data)
    }

    private func fold(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    // MARK: - Store without bundled data

    func testLoadProblemAndEmptyListsGoTogether() {
        if let problem = TracklibImportReferenceStore.loadProblem {
            XCTAssertFalse(problem.isEmpty)
            XCTAssertTrue(TracklibImportReferenceStore.orchestras.isEmpty)
            XCTAssertTrue(TracklibImportReferenceStore.singers.isEmpty)
        } else {
            XCTAssertFalse(TracklibImportReferenceStore.orchestras.isEmpty)
            XCTAssertFalse(TracklibImportReferenceStore.singers.isEmpty)
        }
    }

    func testWithoutDataNothingIsRecognized() throws {
        guard TracklibImportReferenceStore.loadProblem != nil else {
            throw XCTSkip("the reference data is available in this run")
        }

        XCTAssertTrue(TracklibImportReferenceStore.matches(in: "Biagi - Poema", kind: .orchestra).isEmpty)
        XCTAssertTrue(TracklibImportReferenceStore.matches(in: "Alberto Podesta", kind: .singer).isEmpty)
    }

    func testMatchingEmptyTextNeverCrashes() {
        XCTAssertTrue(TracklibImportReferenceStore.matches(in: "", kind: .orchestra).isEmpty)
        XCTAssertTrue(TracklibImportReferenceStore.matches(in: "", kind: .singer).isEmpty)
    }

    // MARK: - Model

    func testModelSurvivesACodableRoundTrip() throws {
        let original = TracklibImportReference(
            version: 3,
            description: "Test data",
            orchestras: [TracklibImportReferenceEntry(name: "Alpha", aliases: ["Alpha", "A. Alpha"])],
            singers: [TracklibImportReferenceEntry(name: "Singer X", aliases: [])]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TracklibImportReference.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDescriptionIsOptionalInTheFile() throws {
        let json = """
        {
          "version": 1,
          "orchestras": [{"name": "Alpha", "aliases": ["Alpha"]}],
          "singers": []
        }
        """

        let decoded = try JSONDecoder().decode(TracklibImportReference.self, from: Data(json.utf8))

        XCTAssertNil(decoded.description)
        XCTAssertEqual(decoded.orchestras.map(\.name), ["Alpha"])
        XCTAssertTrue(decoded.singers.isEmpty)
    }

    func testFileWithoutAliasesKeyIsRejected() {
        let json = """
        {"version": 1, "orchestras": [{"name": "Alpha"}], "singers": []}
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(TracklibImportReference.self, from: Data(json.utf8))
        )
    }

    // MARK: - The real JSON file

    func testReferenceFileDecodes() throws {
        let reference = try loadReferenceFile()

        XCTAssertGreaterThanOrEqual(reference.version, 1)
        XCTAssertFalse(reference.orchestras.isEmpty)
        XCTAssertFalse(reference.singers.isEmpty)
    }

    func testEveryEntryHasANameAndNoBlankAlias() throws {
        let reference = try loadReferenceFile()

        for (kind, entries) in [("orchestra", reference.orchestras), ("singer", reference.singers)] {
            for entry in entries {
                XCTAssertFalse(
                    entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "blank \(kind) name"
                )

                for alias in entry.aliases {
                    XCTAssertFalse(
                        alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "blank alias for \(kind) \(entry.name)"
                    )
                }
            }
        }
    }

    func testCanonicalNamesAreUniqueWithinEachList() throws {
        let reference = try loadReferenceFile()

        for (kind, entries) in [("orchestra", reference.orchestras), ("singer", reference.singers)] {
            var seen = Set<String>()

            for entry in entries {
                XCTAssertTrue(
                    seen.insert(fold(entry.name)).inserted,
                    "\(kind) listed twice: \(entry.name)"
                )
            }
        }
    }

    func testNoAliasIsSoShortThatItWouldMatchInsideEverything() throws {
        let reference = try loadReferenceFile()

        for entry in reference.orchestras + reference.singers {
            for spelling in [entry.name] + entry.aliases {
                XCTAssertGreaterThanOrEqual(
                    fold(spelling).count, 3,
                    "alias too short: \(spelling) (\(entry.name))"
                )
            }
        }
    }

    func testASpellingListedUnderTwoEntriesCanBeToldApart() throws {
        // The recognizer settles such a spelling by preferring the entry
        // whose own name is part of it. That only works if one of them is.
        let reference = try loadReferenceFile()

        for (kind, entries) in [("orchestra", reference.orchestras), ("singer", reference.singers)] {
            var owners: [String: [TracklibImportReferenceEntry]] = [:]

            for entry in entries {
                for spelling in Set(([entry.name] + entry.aliases).map(fold)) {
                    owners[spelling, default: []].append(entry)
                }
            }

            for (spelling, entriesWithIt) in owners where entriesWithIt.count > 1 {
                let namesInside = entriesWithIt.filter { spelling.contains(fold($0.name)) }

                XCTAssertEqual(
                    namesInside.count, 1,
                    "\(kind) spelling \"\(spelling)\" is shared by \(entriesWithIt.map(\.name)) and cannot be told apart"
                )
            }
        }
    }
}
