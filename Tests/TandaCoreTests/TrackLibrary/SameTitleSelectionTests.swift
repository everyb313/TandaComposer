//
//  SameTitleSelectionTests.swift
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

/// Click, Command-click and Shift-click in the "Same Title" window.
@MainActor
final class SameTitleSelectionTests: XCTestCase {

    private let order = ["a", "b", "c", "d", "e"]

    private func click(
        _ selection: inout SameTitleSelection,
        _ key: String,
        command: Bool = false,
        shift: Bool = false
    ) {
        selection.click(key, in: order, command: command, shift: shift)
    }

    func testANewSelectionIsEmpty() {
        let selection = SameTitleSelection()

        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.count, 0)
        XCTAssertFalse(selection.contains("a"))
    }

    func testAPlainClickSelectsOnlyThatRow() {
        var selection = SameTitleSelection()

        click(&selection, "b")
        click(&selection, "d")

        XCTAssertEqual(selection.keys, ["d"])
    }

    func testAPlainClickOnTheSelectedRowKeepsItSelected() {
        var selection = SameTitleSelection()

        click(&selection, "b")
        click(&selection, "b")

        XCTAssertEqual(selection.keys, ["b"])
    }

    func testCommandClickAddsAndRemovesRows() {
        var selection = SameTitleSelection()

        click(&selection, "a")
        click(&selection, "c", command: true)
        click(&selection, "e", command: true)

        XCTAssertEqual(selection.keys, ["a", "c", "e"])

        click(&selection, "c", command: true)

        XCTAssertEqual(selection.keys, ["a", "e"])
    }

    func testShiftClickSelectsTheRangeFromTheLastClick() {
        var selection = SameTitleSelection()

        click(&selection, "b")
        click(&selection, "d", shift: true)

        XCTAssertEqual(selection.keys, ["b", "c", "d"])
    }

    func testShiftClickWorksUpwardsToo() {
        var selection = SameTitleSelection()

        click(&selection, "d")
        click(&selection, "b", shift: true)

        XCTAssertEqual(selection.keys, ["b", "c", "d"])
    }

    func testShiftClickReplacesAnEarlierRangeFromTheSameStart() {
        var selection = SameTitleSelection()

        click(&selection, "a")
        click(&selection, "d", shift: true)
        click(&selection, "b", shift: true)

        XCTAssertEqual(selection.keys, ["a", "b"])
    }

    func testCommandShiftClickAddsTheRangeToTheSelection() {
        var selection = SameTitleSelection()

        click(&selection, "a")
        click(&selection, "c", command: true)
        click(&selection, "e", command: true, shift: true)

        XCTAssertEqual(selection.keys, ["a", "c", "d", "e"])
    }

    func testShiftClickWithoutAPreviousClickJustSelectsTheRow() {
        var selection = SameTitleSelection()

        click(&selection, "c", shift: true)

        XCTAssertEqual(selection.keys, ["c"])
    }

    func testShiftClickAfterClearingJustSelectsTheRow() {
        var selection = SameTitleSelection()
        click(&selection, "a")

        selection.clear()
        click(&selection, "c", shift: true)

        XCTAssertEqual(selection.keys, ["c"])
    }

    func testARangeCanSpanSeveralBlocksBecauseTheOrderIsOneList() {
        var selection = SameTitleSelection()
        let twoBlocks = ["x1", "x2", "y1", "y2"]

        selection.click("x2", in: twoBlocks, command: false, shift: false)
        selection.click("y1", in: twoBlocks, command: false, shift: true)

        XCTAssertEqual(selection.keys, ["x2", "y1"])
    }

    func testClearEmptiesTheSelection() {
        var selection = SameTitleSelection()
        click(&selection, "a")
        click(&selection, "b", command: true)

        selection.clear()

        XCTAssertTrue(selection.isEmpty)
    }

    func testRowsMissingFromTheOrderAreStillSelectableByAPlainClick() {
        var selection = SameTitleSelection()

        click(&selection, "zzz")

        XCTAssertEqual(selection.keys, ["zzz"])
    }
}
