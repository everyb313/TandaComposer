import XCTest
import Foundation

@MainActor
final class SmartListFilterTests: XCTestCase {

    // MARK: - Fixtures

    private var poema: Song { makeSong(
        path: "/Music/poema.flac",
        title: "Poema",
        artist: "Carlos Di Sarli",
        albumArtist: "Roberto Rufino",
        genre: "Tango",
        year: 1940
    ) }

    private var cumparsita: Song { makeSong(
        path: "/Music/cumparsita.flac",
        title: "La Cumparsita",
        artist: "Enrique Rodr\u{00ED}guez",
        albumArtist: "Armando Moreno",
        genre: "Tango",
        year: 1937
    ) }

    private var bahia: Song { makeSong(
        path: "/Music/bahia.flac",
        title: "Bahia Blanca",
        artist: "Carlos Di Sarli",
        genre: "Instrumental"
    ) }

    private var corazon: Song { makeSong(
        path: "/Music/corazon.flac",
        title: "Coraz\u{00F3}n",
        artist: "Alpha Trio",
        genre: "Vals",
        grouping: "Group A",
        year: 1950
    ) }

    private var library: [Song] { [poema, cumparsita, bahia, corazon] }

    private func condition(
        _ field: SmartlistField,
        _ op: SmartlistOperator,
        _ value: String,
        _ secondValue: String? = nil
    ) -> SmartlistCondition {
        SmartlistCondition(field: field, op: op, value: value, secondValue: secondValue)
    }

    private func titles(
        _ conditions: [SmartlistCondition],
        mode: SmartlistMatchMode = .all,
        orchestraSource: TagSource = .artist,
        singerSource: TagSource = .albumArtist
    ) -> [String?] {
        let ruleSet = SmartListRuleSet(name: "Test", matchMode: mode, conditions: conditions)
        return SmartListFilter.apply(
            ruleSet,
            to: library,
            orchestraSource: orchestraSource,
            singerSource: singerSource
        ).map(\.title)
    }

    // MARK: - Empty rule set

    func testNoConditionsReturnsAllSongsInOrder() {
        XCTAssertEqual(
            titles([]),
            ["Poema", "La Cumparsita", "Bahia Blanca", "Coraz\u{00F3}n"]
        )
    }

    // MARK: - Text fields

    func testContainsIsCaseInsensitive() {
        XCTAssertEqual(titles([condition(.orchestra, .contains, "di sarli")]), ["Poema", "Bahia Blanca"])
    }

    func testContainsIgnoresDiacriticsInBothDirections() {
        XCTAssertEqual(titles([condition(.orchestra, .contains, "rodriguez")]), ["La Cumparsita"])
        XCTAssertEqual(titles([condition(.songName, .contains, "corazon")]), ["Coraz\u{00F3}n"])
        XCTAssertEqual(titles([condition(.orchestra, .contains, "Rodr\u{00ED}guez")]), ["La Cumparsita"])
    }

    func testIsEqualIsCaseInsensitiveButNeedsTheWholeValue() {
        XCTAssertEqual(titles([condition(.genre, .isEqual, "tango")]), ["Poema", "La Cumparsita"])
        XCTAssertEqual(titles([condition(.orchestra, .isEqual, "Carlos")]), [])
    }

    func testIsNotEqual() {
        XCTAssertEqual(
            titles([condition(.genre, .isNotEqual, "Tango")]),
            ["Bahia Blanca", "Coraz\u{00F3}n"]
        )
    }

    func testContainsNot() {
        XCTAssertEqual(
            titles([condition(.orchestra, .containsNot, "Sarli")]),
            ["La Cumparsita", "Coraz\u{00F3}n"]
        )
    }

    func testEmptyNeedleMatchesEverythingForContainsAndNothingForContainsNot() {
        XCTAssertEqual(titles([condition(.grouping, .contains, "")]).count, 4)
        XCTAssertEqual(titles([condition(.grouping, .containsNot, "")]).count, 0)
    }

    func testMissingTextCountsAsEmptyText() {
        // Only "Bahia Blanca" and "Corazon" have no singer.
        XCTAssertEqual(
            titles([condition(.singer, .isEqual, "")]),
            ["Bahia Blanca", "Coraz\u{00F3}n"]
        )
        XCTAssertEqual(titles([condition(.singer, .contains, "rufino")]), ["Poema"])
    }

    func testEveryTextFieldReadsItsOwnSongProperty() {
        XCTAssertEqual(titles([condition(.songName, .contains, "cumparsita")]), ["La Cumparsita"])
        XCTAssertEqual(titles([condition(.orchestra, .contains, "alpha")]), ["Coraz\u{00F3}n"])
        XCTAssertEqual(titles([condition(.singer, .contains, "moreno")]), ["La Cumparsita"])
        XCTAssertEqual(titles([condition(.genre, .contains, "instrumental")]), ["Bahia Blanca"])
        XCTAssertEqual(titles([condition(.grouping, .contains, "group")]), ["Coraz\u{00F3}n"])
    }

    func testRangeOperatorsNeverMatchTextFields() {
        XCTAssertEqual(titles([condition(.orchestra, .isBetween, "A", "Z")]), [])
        XCTAssertEqual(titles([condition(.orchestra, .isNotBetween, "A", "Z")]), [])
    }

    // MARK: - Year

    func testYearIsEqual() {
        XCTAssertEqual(titles([condition(.year, .isEqual, "1937")]), ["La Cumparsita"])
    }

    func testYearIsNotEqualSkipsSongsWithoutYear() {
        XCTAssertEqual(
            titles([condition(.year, .isNotEqual, "1937")]),
            ["Poema", "Coraz\u{00F3}n"]
        )
    }

    func testYearBetweenIncludesBothBounds() {
        XCTAssertEqual(
            titles([condition(.year, .isBetween, "1937", "1940")]),
            ["Poema", "La Cumparsita"]
        )
    }

    func testYearNotBetweenSkipsSongsWithoutYear() {
        XCTAssertEqual(
            titles([condition(.year, .isNotBetween, "1937", "1940")]),
            ["Coraz\u{00F3}n"]
        )
    }

    func testUnparsableYearValuesMatchNothing() {
        XCTAssertEqual(titles([condition(.year, .isEqual, "abc")]), [])
        XCTAssertEqual(titles([condition(.year, .isNotEqual, "abc")]), [])
        XCTAssertEqual(titles([condition(.year, .isBetween, "1937", "abc")]), [])
    }

    func testBetweenWithoutUpperBoundMatchesNothing() {
        XCTAssertEqual(titles([condition(.year, .isBetween, "1937")]), [])
    }

    func testTextOperatorsNeverMatchTheYearField() {
        XCTAssertEqual(titles([condition(.year, .contains, "19")]), [])
        XCTAssertEqual(titles([condition(.year, .containsNot, "19")]), [])
    }

    // MARK: - Match mode

    func testAllConditionsMustMatch() {
        XCTAssertEqual(
            titles([
                condition(.orchestra, .contains, "Sarli"),
                condition(.genre, .isEqual, "Tango")
            ], mode: .all),
            ["Poema"]
        )
    }

    func testAnyConditionIsEnough() {
        XCTAssertEqual(
            titles([
                condition(.orchestra, .contains, "Alpha"),
                condition(.year, .isEqual, "1937")
            ], mode: .any),
            ["La Cumparsita", "Coraz\u{00F3}n"]
        )
    }

    func testSingleConditionBehavesTheSameInBothModes() {
        let single = [condition(.genre, .isEqual, "Vals")]

        XCTAssertEqual(titles(single, mode: .all), titles(single, mode: .any))
    }

    func testContradictingConditionsInAllModeMatchNothing() {
        XCTAssertEqual(
            titles([
                condition(.genre, .isEqual, "Tango"),
                condition(.genre, .isEqual, "Vals")
            ], mode: .all),
            []
        )
    }

    /// Orchestra/Singer follow TagSource (AppSettings), not fixed Artist/AlbumArtist columns.
    func testOrchestraAndSingerRespectTagSourceRemapping() {
        // Default library: artist = orchestra, albumArtist = singer.
        // Swap sources → "rufino" matches orchestra; "di sarli" matches singer.
        XCTAssertEqual(
            titles(
                [condition(.orchestra, .contains, "rufino")],
                orchestraSource: .albumArtist,
                singerSource: .artist
            ),
            ["Poema"]
        )
        XCTAssertEqual(
            titles(
                [condition(.singer, .contains, "di sarli")],
                orchestraSource: .albumArtist,
                singerSource: .artist
            ),
            ["Poema", "Bahia Blanca"]
        )
    }

}

// MARK: - Rule set model

@MainActor
final class SmartListRuleSetTests: XCTestCase {

    func testOnlyYearIsNumeric() {
        for field in SmartlistField.allCases {
            XCTAssertEqual(field.isNumeric, field == .year, "\(field)")
        }
    }

    func testValidOperatorsDependOnTheFieldKind() {
        XCTAssertEqual(
            SmartlistOperator.validOperators(for: .year),
            [.isEqual, .isNotEqual, .isBetween, .isNotBetween]
        )
        XCTAssertEqual(
            SmartlistOperator.validOperators(for: .orchestra),
            [.isEqual, .isNotEqual, .contains, .containsNot]
        )
    }

    func testDisplayNamesUseTheTangoVocabulary() {
        XCTAssertEqual(SmartlistField.orchestra.displayName, "Orchestra")
        XCTAssertEqual(SmartlistField.singer.displayName, "Singer")
        XCTAssertEqual(SmartlistField.songName.displayName, "Title")
    }

    /// These raw values are stored in the Smartlist files on disk.
    func testRawValuesAreStable() {
        XCTAssertEqual(SmartlistField.allCases.map(\.rawValue),
                       ["songName", "orchestra", "singer", "genre", "year", "grouping"])
        XCTAssertEqual(SmartlistOperator.allCases.map(\.rawValue),
                       ["isEqual", "isNotEqual", "isBetween", "isNotBetween", "contains", "containsNot"])
        XCTAssertEqual(SmartlistMatchMode.allCases.map(\.rawValue), ["all", "any"])
    }

    func testCodableRoundTrip() throws {
        let original = SmartListRuleSet(
            name: "Di Sarli 1940s",
            matchMode: .any,
            conditions: [
                SmartlistCondition(field: .orchestra, op: .contains, value: "Sarli", secondValue: nil),
                SmartlistCondition(field: .year, op: .isBetween, value: "1940", secondValue: "1949")
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SmartListRuleSet.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDecodesAFileInTheStoredFormat() throws {
        let json = """
        {
          "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "name": "Test",
          "matchMode": "any",
          "conditions": [
            {
              "id": "A621E1F8-C36C-495A-93FC-0C247A3E6E5F",
              "field": "year",
              "op": "isBetween",
              "value": "1937",
              "secondValue": "1940"
            },
            {
              "id": "B621E1F8-C36C-495A-93FC-0C247A3E6E5F",
              "field": "orchestra",
              "op": "contains",
              "value": "Sarli"
            }
          ]
        }
        """

        let ruleSet = try JSONDecoder().decode(SmartListRuleSet.self, from: Data(json.utf8))

        XCTAssertEqual(ruleSet.name, "Test")
        XCTAssertEqual(ruleSet.matchMode, .any)
        XCTAssertEqual(ruleSet.conditions.count, 2)
        XCTAssertEqual(ruleSet.conditions[0].field, .year)
        XCTAssertEqual(ruleSet.conditions[0].op, .isBetween)
        XCTAssertEqual(ruleSet.conditions[0].secondValue, "1940")
        XCTAssertNil(ruleSet.conditions[1].secondValue)
    }

    func testNewRuleSetDefaultsToAllMatchingWithoutConditions() {
        let ruleSet = SmartListRuleSet(name: "New")

        XCTAssertEqual(ruleSet.matchMode, .all)
        XCTAssertTrue(ruleSet.conditions.isEmpty)
    }
}
