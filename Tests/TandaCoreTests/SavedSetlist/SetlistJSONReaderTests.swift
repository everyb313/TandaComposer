//
//  SetlistJSONReaderTests.swift
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
//

import XCTest
import Foundation

/// Setlist JSON → ImportedTrack for Special Import: roles come from the
/// header, not from fixed tag fields.
@MainActor
final class SetlistJSONReaderTests: XCTestCase {

    private func writeSetlist(
        name: String = "Share",
        orchestra: TagSource? = .artist,
        singer: TagSource? = .albumArtist,
        songs: [Song]
    ) throws -> URL {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("\(name).json")
        try SetlistMetadataExporter.export(
            songs: songs,
            setlistName: name,
            to: file,
            orchestraSource: orchestra,
            singerSource: singer
        )
        return file
    }

    func testLooksLikeSetlistRequiresFormat() throws {
        let file = try writeSetlist(songs: [makeFullSong()])
        XCTAssertTrue(SetlistJSONReader.looksLikeSetlist(file))

        let dir = try makeTemporaryDirectory()
        let other = dir.appendingPathComponent("nope.json")
        try """
        { "format" : "Something Else", "version" : 1 }
        """.write(to: other, atomically: true, encoding: .utf8)
        XCTAssertFalse(SetlistJSONReader.looksLikeSetlist(other))
    }

    func testRolesFollowHeaderNotFixedFields() throws {
        // Orchestra in AlbumArtist, singer in Artist — opposite of defaults.
        var song = makeFullSong(id: 1)
        song.artist = "Carbel, Enrique"
        song.albumArtist = "D'Arienzo, Juan"

        let file = try writeSetlist(
            orchestra: .albumArtist,
            singer: .artist,
            songs: [song]
        )

        let result = try SetlistJSONReader.read(from: file)

        XCTAssertEqual(result.orchestraSource, .albumArtist)
        XCTAssertEqual(result.singerSource, .artist)
        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.tracks[0].artist, "D'Arienzo, Juan")
        XCTAssertEqual(result.tracks[0].singer, "Carbel, Enrique")
        XCTAssertEqual(result.tracks[0].fileHash, song.fileHash)
    }

    func testMissingHeaderAssumesArtistAndAlbumArtist() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("old.json")
        try SetlistMetadataExporter.export(
            songs: [makeFullSong()],
            setlistName: "Old",
            to: file,
            orchestraSource: nil,
            singerSource: nil
        )

        // Strip the keys to simulate an older file that never had them.
        var text = try String(contentsOf: file, encoding: .utf8)
        text = text.replacingOccurrences(
            of: #"\s*"orchestraSource"\s*:\s*"[^"]*"\s*,?"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\s*"singerSource"\s*:\s*"[^"]*"\s*,?"#,
            with: "",
            options: .regularExpression
        )
        try text.write(to: file, atomically: true, encoding: .utf8)

        let result = try SetlistJSONReader.read(from: file)

        XCTAssertNil(result.orchestraSource)
        XCTAssertNil(result.singerSource)
        // Reader falls back to Artist / AlbumArtist for track roles.
        XCTAssertEqual(result.tracks.first?.artist, makeFullSong().artist)
    }

    func testConventionNoteNamesBothSidesWhenTheyDiffer() {
        let note = SetlistJSONReader.conventionNote(
            orchestraSource: .grouping,
            singerSource: .artist,
            ownOrchestra: .artist,
            ownSinger: .albumArtist
        )

        let text = try! XCTUnwrap(note)
        XCTAssertTrue(text.contains("Sender:"))
        XCTAssertTrue(text.contains("You:"))
        XCTAssertTrue(text.contains("by role"))
    }

    func testConventionNoteWhenHeaderMissing() {
        let note = SetlistJSONReader.conventionNote(
            orchestraSource: nil,
            singerSource: nil,
            ownOrchestra: .artist,
            ownSinger: .albumArtist
        )

        let text = try! XCTUnwrap(note)
        XCTAssertTrue(text.contains("not recorded"))
    }
}
