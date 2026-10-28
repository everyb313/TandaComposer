//
//  SameTitleFinderTests.swift
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

/// The search behind the "?" button of the TrackLibrary header: tracks with
/// the same title as the selected ones.
@MainActor
final class SameTitleFinderTests: XCTestCase {

    // MARK: - Helpers

    private func song(
        _ id: Int64,
        _ title: String?,
        artist: String? = nil,
        albumArtist: String? = nil,
        year: Int? = nil,
        path: String? = nil
    ) -> Song {
        makeSong(
            id: id,
            path: path ?? "/Library/\(id).flac",
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            year: year
        )
    }

    private func ids(_ songs: [Song]) -> [Int64?] {
        songs.map(\.id)
    }

    // MARK: - Title key

    func testTheKeyIgnoresCaseAccentsApostrophesAndSpacing() {
        let keys = [
            "Cafet\u{00ED}n de Buenos Aires",
            "CAFETIN DE BUENOS AIRES",
            "  cafetin   de buenos aires "
        ].map { SameTitleFinder.titleKey(of: song(1, $0)) }

        XCTAssertNotNil(keys[0])
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertEqual(keys[0], keys[2])
        XCTAssertEqual(
            SameTitleFinder.titleKey(of: song(1, "D\u{2019}Arienzo")),
            SameTitleFinder.titleKey(of: song(2, "D'Arienzo"))
        )
    }

    func testAdditionsToTheTitleMakeItADifferentTitle() {
        XCTAssertNotEqual(
            SameTitleFinder.titleKey(of: song(1, "Poema")),
            SameTitleFinder.titleKey(of: song(2, "Poema (remastered)"))
        )
        XCTAssertNotEqual(
            SameTitleFinder.titleKey(of: song(1, "Poema")),
            SameTitleFinder.titleKey(of: song(2, "Poema."))
        )
    }

    func testWithoutATitleTagTheFileNameWithoutSuffixIsUsed() {
        let key = SameTitleFinder.titleKey(of: song(1, nil, path: "/Music/Poema.flac"))

        XCTAssertEqual(key, SameTitleFinder.titleKey(of: song(2, "Poema")))
        XCTAssertEqual(
            SameTitleFinder.titleKey(of: song(3, "   ", path: "/Music/Poema.mp3")),
            key,
            "a blank title counts as none"
        )
    }

    func testATrackWithoutTitleAndFileNameHasNoKey() {
        var nameless = song(1, nil)
        nameless.filename = ""

        XCTAssertNil(SameTitleFinder.titleKey(of: nameless))
    }

    func testTheDisplayTitleKeepsTheOriginalSpelling() {
        XCTAssertEqual(SameTitleFinder.displayTitle(of: song(1, "  Mi Noche Triste ")), "Mi Noche Triste")
        XCTAssertEqual(SameTitleFinder.displayTitle(of: song(2, nil, path: "/Music/Poema.flac")), "Poema")
    }

    // MARK: - find: one selected track

    func testTheOtherTracksWithTheSameTitleAreFound() {
        let library = [
            song(1, "Poema", artist: "Alpha Trio", year: 1936),
            song(2, "poema", artist: "Beta Band", year: 1941),
            song(3, "POEMA", artist: "Gamma Sextet", year: 1952),
            song(4, "Other Title"),
            song(5, "Poema (remastered)")
        ]

        let result = SameTitleFinder.find(for: [library[0]], in: library)

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(ids(result.groups[0].songs), [1, 2, 3])
        XCTAssertEqual(ids(result.groups[0].anchors), [1])
        XCTAssertEqual(result.groups[0].otherCount, 2)
        XCTAssertEqual(result.groups[0].title, "Poema")
        XCTAssertEqual(result.omittedTitleCount, 0)
        XCTAssertTrue(result.untitled.isEmpty)
    }

    func testTheSelectedTrackIsFirstEvenWhenItIsTheNewest() {
        let library = [
            song(1, "Poema", year: 1936),
            song(2, "Poema", year: 1952),
            song(3, "Poema", year: 1941)
        ]

        let result = SameTitleFinder.find(for: [library[1]], in: library)

        XCTAssertEqual(ids(result.groups[0].songs), [2, 1, 3])
    }

    func testTheSelectedTrackIsNotListedTwice() {
        let library = [song(1, "Poema"), song(2, "Poema")]

        let result = SameTitleFinder.find(for: [library[0]], in: library)

        XCTAssertEqual(ids(result.groups[0].songs), [1, 2])
    }

    func testATitleThatOccursOnlyOnceGivesAGroupWithoutOthers() {
        let library = [song(1, "Poema"), song(2, "Other")]

        let result = SameTitleFinder.find(for: [library[0]], in: library)

        XCTAssertEqual(ids(result.groups[0].songs), [1])
        XCTAssertEqual(result.groups[0].otherCount, 0)
    }

    func testASelectedTrackThatIsNotInTheLibraryListIsStillShown() {
        let result = SameTitleFinder.find(for: [song(9, "Poema")], in: [song(1, "Poema")])

        XCTAssertEqual(ids(result.groups[0].songs), [9, 1])
    }

    func testAnEmptySelectionGivesAnEmptyResult() {
        let result = SameTitleFinder.find(for: [], in: [song(1, "Poema")])

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.omittedTitleCount, 0)
    }

    // MARK: - find: order of the other tracks

    func testOthersAreSortedByYearWithUnknownYearsLast() {
        let library = [
            song(1, "Poema"),
            song(2, "Poema", year: nil),
            song(3, "Poema", year: 1952),
            song(4, "Poema", year: 1936),
            song(5, "Poema", year: 1941)
        ]

        let result = SameTitleFinder.find(for: [library[0]], in: library)

        XCTAssertEqual(ids(result.groups[0].songs), [1, 4, 5, 3, 2])
    }

    func testAnchorStaysFirstThenTracksFromItsOrchestraComeNext() {
        let anchor = song(1, "Poema", artist: "Beta Orchestra", year: 1952)
        let alpha = song(2, "Poema", artist: "Alpha Orchestra", year: 1936)
        let betaOlder = song(3, "Poema", artist: "Beta Orchestra", year: 1930)
        let betaNewer = song(4, "Poema", artist: "Beta Orchestra", year: 1960)
        let gamma = song(5, "Poema", artist: "Gamma Orchestra", year: 1940)

        let result = SameTitleFinder.find(
            for: [anchor],
            in: [anchor, alpha, betaOlder, betaNewer, gamma]
        )

        XCTAssertEqual(ids(result.groups[0].songs), [1, 3, 4, 2, 5])
        XCTAssertEqual(result.groups[0].songs.first?.id, anchor.id,
                       "The selected anchor must remain first")
    }

    func testTheSameYearIsSortedByOrchestraThenSingerThenPath() {
        let library = [
            song(1, "Poema"),
            song(2, "Poema", artist: "Beta Band", albumArtist: "Singer B", year: 1940, path: "/z/2.flac"),
            song(3, "Poema", artist: "Alpha Trio", albumArtist: "Singer B", year: 1940, path: "/z/3.flac"),
            song(4, "Poema", artist: "Alpha Trio", albumArtist: "Singer A", year: 1940, path: "/z/4.flac"),
            song(5, "Poema", artist: "Alpha Trio", albumArtist: "Singer A", year: 1940, path: "/a/5.flac")
        ]

        let result = SameTitleFinder.find(for: [library[0]], in: library)

        XCTAssertEqual(ids(result.groups[0].songs), [1, 5, 4, 3, 2])
    }

    func testTheConfiguredTagSourcesDecideTheOrchestraAndSingerOrder() {
        var first = song(2, "Poema", year: 1940)
        first.grouping = "Zeta Orchestra"
        var second = song(3, "Poema", year: 1940)
        second.grouping = "Alpha Orchestra"
        let anchor = song(1, "Poema")

        let byGrouping = SameTitleFinder.find(
            for: [anchor],
            in: [anchor, first, second],
            orchestraSource: .grouping
        )
        let byArtist = SameTitleFinder.find(
            for: [anchor],
            in: [anchor, first, second]
        )

        XCTAssertEqual(ids(byGrouping.groups[0].songs), [1, 3, 2])
        XCTAssertEqual(ids(byArtist.groups[0].songs), [1, 2, 3], "no artist: falls through to the path")
    }

    // MARK: - find: several selected tracks

    func testTwoSelectedVersionsOfOneTitleShareAGroup() {
        let library = [
            song(1, "Poema", year: 1936),
            song(2, "Poema", year: 1941),
            song(3, "Poema", year: 1952)
        ]

        let result = SameTitleFinder.find(for: [library[2], library[0]], in: library)

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(ids(result.groups[0].anchors), [3, 1])
        XCTAssertEqual(ids(result.groups[0].songs), [3, 1, 2])
        XCTAssertEqual(result.groups[0].otherCount, 1)
    }

    func testDifferentTitlesGiveOneGroupEachInSelectionOrder() {
        let library = [
            song(1, "Poema"),
            song(2, "Poema"),
            song(3, "Mi Noche Triste"),
            song(4, "Mi Noche Triste")
        ]

        let result = SameTitleFinder.find(for: [library[2], library[0]], in: library)

        XCTAssertEqual(result.groups.map(\.title), ["Mi Noche Triste", "Poema"])
        XCTAssertEqual(ids(result.groups[0].songs), [3, 4])
        XCTAssertEqual(ids(result.groups[1].songs), [1, 2])
    }

    func testMoreTitlesThanTheLimitAreCutOffAndCounted() {
        let titles = (1...11).map { "Title \($0)" }
        let library = titles.enumerated().map { song(Int64($0.offset + 1), $0.element) }

        let result = SameTitleFinder.find(for: library, in: library)

        XCTAssertEqual(SameTitleFinder.maxGroups, 8)
        XCTAssertEqual(result.groups.count, 8)
        XCTAssertEqual(result.groups.map(\.title), Array(titles.prefix(8)))
        XCTAssertEqual(result.omittedTitleCount, 3)
    }

    func testSeveralVersionsOfOneTitleCountAsOneTitleForTheLimit() {
        let library = (1...20).map { song(Int64($0), "Poema") }

        let result = SameTitleFinder.find(for: library, in: library)

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].songs.count, 20)
        XCTAssertEqual(result.omittedTitleCount, 0)
    }

    // MARK: - find: tracks without a usable title

    func testSelectedTracksWithoutAnyTitleAreReportedSeparately() {
        var nameless = song(1, nil)
        nameless.filename = ""
        let titled = song(2, "Poema")

        let result = SameTitleFinder.find(for: [nameless, titled], in: [nameless, titled])

        XCTAssertEqual(ids(result.untitled), [1])
        XCTAssertEqual(result.groups.map(\.title), ["Poema"])
        XCTAssertFalse(result.isEmpty)
    }

    func testOnlyUntitledTracksStillGiveANonEmptyResult() {
        var nameless = song(1, nil)
        nameless.filename = ""

        let result = SameTitleFinder.find(for: [nameless], in: [nameless])

        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertFalse(result.isEmpty)
    }

    func testAFileNameFallbackFindsTracksWithATitleTag() {
        let library = [
            song(1, nil, path: "/Music/Poema.flac"),
            song(2, "Poema")
        ]

        let result = SameTitleFinder.find(for: [library[0]], in: library)

        XCTAssertEqual(ids(result.groups[0].songs), [1, 2])
        XCTAssertEqual(result.groups[0].title, "Poema")
    }
}
