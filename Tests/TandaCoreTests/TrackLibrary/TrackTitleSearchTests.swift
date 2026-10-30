//
//  TrackTitleSearchTests.swift
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

/// The quick title search of the TrackLibrary: ONE character = title starts
/// with it, two or more = title contains it. Title only.
final class TrackTitleSearchTests: XCTestCase {

    // MARK: - Helpers

    private func songs(_ titles: [String?]) -> [Song] {
        titles.enumerated().map { index, title in
            makeSong(
                id: Int64(index + 1),
                path: "/Music/\(index + 1).flac",
                title: title,
                // Other fields must NOT be searched.
                artist: "Zzz Artist",
                genre: "Zzz Genre",
                album: "Zzz Album"
            )
        }
    }

    private func hits(_ query: String, in titles: [String?]) -> [String?] {
        TrackTitleSearch.filter(songs(titles), query: query).map(\.title)
    }

    // MARK: - Mode

    func testModeDependsOnTheNumberOfTypedCharacters() {
        XCTAssertEqual(TrackTitleSearch.mode(for: ""), .inactive)
        XCTAssertEqual(TrackTitleSearch.mode(for: "   "), .inactive)
        XCTAssertEqual(TrackTitleSearch.mode(for: "a"), .startsWith)
        XCTAssertEqual(TrackTitleSearch.mode(for: " a "), .startsWith)
        XCTAssertEqual(TrackTitleSearch.mode(for: "ab"), .contains)
        XCTAssertEqual(TrackTitleSearch.mode(for: "a b"), .contains)
    }

    func testAGermanSharpSIsOneTypedCharacter() {
        // Folding turns "ß" into "ss"; the mode must follow what was typed.
        XCTAssertEqual(TrackTitleSearch.mode(for: "ß"), .startsWith)
    }

    // MARK: - One character: starts with

    func testOneLetterFindsOnlyTitlesStartingWithIt() {
        let titles: [String?] = ["Amurado", "Bailongo", "La Cumparsita", "Mala Junta"]

        XCTAssertEqual(hits("a", in: titles), ["Amurado"])
        XCTAssertEqual(hits("m", in: titles), ["Mala Junta"])
    }

    func testOneLetterIgnoresCaseAndAccents() {
        let titles: [String?] = ["Ángel", "angelito", "Bailongo"]

        XCTAssertEqual(hits("a", in: titles), ["Ángel", "angelito"])
        XCTAssertEqual(hits("A", in: titles), ["Ángel", "angelito"])
        XCTAssertEqual(hits("á", in: titles), ["Ángel", "angelito"])
    }

    func testOneLetterIgnoresLeadingWhitespaceInTheTitle() {
        XCTAssertEqual(hits("a", in: ["  Amurado", "Bailongo"]), ["  Amurado"])
    }

    // MARK: - Two or more characters: contains

    func testSeveralLettersFindTheTextAnywhereInTheTitle() {
        let titles: [String?] = ["La Cumparsita", "Cumbia", "Bailongo"]

        XCTAssertEqual(hits("cump", in: titles), ["La Cumparsita"])
        XCTAssertEqual(hits("um", in: titles), ["La Cumparsita", "Cumbia"])
    }

    func testSeveralLettersIgnoreCaseAndAccents() {
        XCTAssertEqual(hits("CUMPARS", in: ["La Cumparsita"]), ["La Cumparsita"])
        XCTAssertEqual(hits("pugl", in: ["Púgliese"]), ["Púgliese"])
    }

    func testSurroundingWhitespaceOfTheQueryIsIgnored() {
        XCTAssertEqual(hits("  cump  ", in: ["La Cumparsita", "Bailongo"]), ["La Cumparsita"])
    }

    func testQueryWithAnInnerSpaceIsMatchedAsTyped() {
        let titles: [String?] = ["La Cumparsita", "Lacumparsita"]

        XCTAssertEqual(hits("la c", in: titles), ["La Cumparsita"])
    }

    // MARK: - Title only

    func testOtherFieldsAreNotSearched() {
        // Every song has artist/genre/album "Zzz ...".
        XCTAssertTrue(hits("zzz", in: ["Amurado", "Bailongo"]).isEmpty)
        XCTAssertTrue(hits("z", in: ["Amurado", "Bailongo"]).isEmpty)
    }

    func testSongsWithoutATitleNeverMatchAnActiveSearch() {
        XCTAssertTrue(hits("a", in: [nil]).isEmpty)
        XCTAssertTrue(hits("ab", in: [nil]).isEmpty)
    }

    // MARK: - Inactive search

    func testEmptyOrBlankQueryReturnsEverythingIncludingUntitledSongs() {
        let titles: [String?] = ["Amurado", nil, "Bailongo"]

        XCTAssertEqual(hits("", in: titles).count, 3)
        XCTAssertEqual(hits("   ", in: titles).count, 3)
    }

    func testNoHitsGivesAnEmptyList() {
        XCTAssertTrue(hits("qqq", in: ["Amurado"]).isEmpty)
    }

    func testTheOrderOfTheSongsIsKept() {
        let titles: [String?] = ["Mala", "Amurado", "Milonga"]

        XCTAssertEqual(hits("m", in: titles), ["Mala", "Milonga"])
    }
}
