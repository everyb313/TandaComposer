import XCTest
import Foundation

/// Additions to the rule-set model tests in `SmartListFilterTests.swift`
/// (valid operators, display names, raw values and the Codable round trip are
/// covered there).
@MainActor
final class SmartListModelTests: XCTestCase {

    func testMatchModeDisplayNames() {
        XCTAssertEqual(SmartlistMatchMode.all.displayName, "all")
        XCTAssertEqual(SmartlistMatchMode.any.displayName, "any")
    }

    func testOperatorDisplayNames() {
        XCTAssertEqual(SmartlistOperator.isEqual.displayName, "is")
        XCTAssertEqual(SmartlistOperator.isNotEqual.displayName, "is not")
        XCTAssertEqual(SmartlistOperator.isBetween.displayName, "is between")
        XCTAssertEqual(SmartlistOperator.isNotBetween.displayName, "is not between")
        XCTAssertEqual(SmartlistOperator.contains.displayName, "contains")
        XCTAssertEqual(SmartlistOperator.containsNot.displayName, "does not contain")
    }

    func testMatchModeRawValuesAreStableBecauseTheyAreStoredInUserFiles() {
        XCTAssertEqual(SmartlistMatchMode.allCases.map(\.rawValue), ["all", "any"])
    }

    func testIdentifiableIDsAreTheRawValues() {
        XCTAssertEqual(SmartlistField.year.id, "year")
        XCTAssertEqual(SmartlistOperator.isBetween.id, "isBetween")
        XCTAssertEqual(SmartlistMatchMode.any.id, "any")
    }

    func testUnknownFieldIsRejectedWhenDecoding() {
        let json = """
        {"id": "\(UUID().uuidString)", "field": "bpm", "op": "isEqual", "value": "1"}
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(SmartlistCondition.self, from: Data(json.utf8))
        )
    }

    func testUnknownOperatorIsRejectedWhenDecoding() {
        let json = """
        {"id": "\(UUID().uuidString)", "field": "year", "op": "startsWith", "value": "1"}
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(SmartlistCondition.self, from: Data(json.utf8))
        )
    }

    func testSecondValueIsOptionalInTheFile() throws {
        let json = """
        {"id": "\(UUID().uuidString)", "field": "genre", "op": "isEqual", "value": "Tango"}
        """

        let condition = try JSONDecoder().decode(SmartlistCondition.self, from: Data(json.utf8))

        XCTAssertNil(condition.secondValue)
        XCTAssertEqual(condition.value, "Tango")
    }

    func testNewRuleSetMatchesAllAndHasNoConditions() {
        let ruleSet = SmartListRuleSet(name: "New")

        XCTAssertEqual(ruleSet.name, "New")
        XCTAssertEqual(ruleSet.matchMode, .all)
        XCTAssertTrue(ruleSet.conditions.isEmpty)
    }

    func testEveryRuleSetHasItsOwnID() {
        XCTAssertNotEqual(SmartListRuleSet(name: "A").id, SmartListRuleSet(name: "A").id)
    }
}
