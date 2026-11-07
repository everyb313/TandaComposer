//
//  TandaJSONImportTests.swift
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

/// "Tandas from ZIP…" also reads the Tanda files of a "TandaLibrary
/// (JSON-ZIP)" export; the header says which tag fields hold the
/// Orchestra and the Singer.
@MainActor
final class TandaJSONImportTests: XCTestCase {

    // MARK: - Helpers

    /// A song as the SENDER has it: its own tags, paths and hash.
    private func senderSong(
        _ id: Int64,
        title: String? = nil,
        artist: String?,
        albumArtist: String?,
        grouping: String? = nil
    ) -> Song {
        var song = makeSong(
            id: id,
            path: "/Users/sender/Music/\(id).flac",
            title: title ?? "Song \(id)",
            artist: artist,
            albumArtist: albumArtist,
            year: 1938,
            duration: 150
        )
        song.grouping = grouping
        song.album = "Album \(id)"
        song.bpm = 120
        song.key = "Am"
        song.fileHash = "sender-hash-\(id)"
        return song
    }

    private func senderSongs(
        _ count: Int = 3,
        artist: String? = "Artist X",
        albumArtist: String? = "AlbumArtist X",
        grouping: String? = "Grouping X"
    ) -> [Song] {
        (1...count).map {
            senderSong(Int64($0), artist: artist, albumArtist: albumArtist, grouping: grouping)
        }
    }

    /// Builds a "Tandas/…" tree like the JSON export, plus extra files,
    /// and zips it.
    private func makeZip(
        tandas: [(path: String, songs: [Song], name: String, orchestra: TagSource?, singer: TagSource?)] = [],
        extraFiles: [String: String] = [:]
    ) throws -> URL {
        let work = try makeTemporaryDirectory()
        let staging = work.appendingPathComponent("Tandas", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        for tanda in tandas {
            let url = staging.appendingPathComponent(tanda.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try TandaMetadataExporter.export(
                songs: tanda.songs,
                tandaName: tanda.name,
                to: url,
                savedAt: wholeSecondDate,
                comment: "c",
                savedAgainstLibraryName: "Sender Library",
                orchestraSource: tanda.orchestra,
                singerSource: tanda.singer
            )
        }

        for (path, text) in extraFiles {
            let url = staging.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        let zip = work.appendingPathComponent("shared.zip")
        try TandaLibraryExporter.zip(folder: staging, to: zip)
        return zip
    }

    private func scan(
        _ tandas: [(path: String, songs: [Song], name: String, orchestra: TagSource?, singer: TagSource?)],
        extraFiles: [String: String] = [:]
    ) throws -> SharedTandaScan {
        try TandaZipImporter.read(zipURL: try makeZip(tandas: tandas, extraFiles: extraFiles))
    }

    // MARK: - Reading

    func testAJsonTandaIsReadWithNameCommentAndFolders() throws {
        let result = try scan([
            ("Di Sarli/Acuna/T1.json", senderSongs(3), "Set X", .artist, .albumArtist)
        ])

        let tanda = try XCTUnwrap(result.tandas.first)
        XCTAssertEqual(result.tandas.count, 1)
        XCTAssertEqual(tanda.folder, "Di Sarli", "the Tandas wrapper folder is dropped")
        XCTAssertEqual(tanda.subfolder, "Acuna")
        XCTAssertEqual(tanda.fileName, "T1")
        XCTAssertEqual(tanda.name, "Set X")
        XCTAssertEqual(tanda.comment, "c")
        XCTAssertEqual(tanda.tracks.count, 3)
        XCTAssertTrue(tanda.isJSON)
        XCTAssertTrue(result.unreadable.isEmpty)
    }

    func testTheHeaderSaysWhichFieldsAreOrchestraAndSinger() throws {
        let result = try scan([
            ("O/S/T.json", senderSongs(), "T", .albumArtist, .grouping)
        ])

        let tanda = try XCTUnwrap(result.tandas.first)
        XCTAssertEqual(tanda.orchestraSource, .albumArtist)
        XCTAssertEqual(tanda.singerSource, .grouping)

        // The tracks arrive in role form: artist = orchestra, singer = singer.
        let track = try XCTUnwrap(tanda.tracks.first)
        XCTAssertEqual(track.artist, "AlbumArtist X")
        XCTAssertEqual(track.singer, "Grouping X")
    }

    func testWithoutAConventionArtistAndAlbumArtistAreAssumed() throws {
        let result = try scan([
            ("O/S/T.json", senderSongs(), "T", nil, nil)
        ])

        let tanda = try XCTUnwrap(result.tandas.first)
        XCTAssertNil(tanda.orchestraSource, "unknown, not guessed")
        XCTAssertNil(tanda.singerSource)

        let track = try XCTUnwrap(tanda.tracks.first)
        XCTAssertEqual(track.artist, "Artist X")
        XCTAssertEqual(track.singer, "AlbumArtist X")
    }

    func testAnEmptyRoleFieldGivesNoValueInsteadOfAnotherField() throws {
        let result = try scan([
            ("O/S/T.json", senderSongs(artist: nil, albumArtist: "Singer"), "T", .artist, .albumArtist)
        ])

        let track = try XCTUnwrap(result.tandas.first?.tracks.first)
        XCTAssertNil(track.artist)
        XCTAssertEqual(track.singer, "Singer")
    }

    func testHashDurationAlbumYearAndPathAreCarriedOver() throws {
        let result = try scan([
            ("O/S/T.json", senderSongs(), "T", .artist, .albumArtist)
        ])

        let track = try XCTUnwrap(result.tandas.first?.tracks.first)
        XCTAssertEqual(track.title, "Song 1")
        XCTAssertEqual(track.fileHash, "sender-hash-1")
        XCTAssertEqual(track.duration, 150)
        XCTAssertEqual(track.album, "Album 1")
        XCTAssertEqual(track.year, 1938)
        XCTAssertEqual(track.bpm, 120)
        XCTAssertEqual(track.key, "Am")
        XCTAssertEqual(track.path, "/Users/sender/Music/1.flac")
        XCTAssertEqual(track.filename, "1.flac")
        XCTAssertEqual(track.sourceIndex, 0)
        XCTAssertNil(track.libraryID, "the sender's database id means nothing here")
    }

    func testAJsonFileThatIsNotATandaIsIgnored() throws {
        let result = try scan(
            [("O/S/Good.json", senderSongs(), "Good", .artist, .albumArtist)],
            extraFiles: ["O/S/other.json": "{ \"hello\": 1 }"]
        )

        XCTAssertEqual(result.tandas.map(\.fileName), ["Good"])
        XCTAssertTrue(result.unreadable.isEmpty, "a foreign JSON file is not reported")
    }

    func testABrokenTandaFileIsReportedAndTheRestIsStillRead() throws {
        let result = try scan(
            [("O/S/Good.json", senderSongs(), "Good", .artist, .albumArtist)],
            extraFiles: ["O/S/bad.json": "{ \"format\" : \"TandaComposer Tanda\", \"version\" : 1 }"]
        )

        XCTAssertEqual(result.tandas.map(\.fileName), ["Good"])
        XCTAssertEqual(result.unreadable.count, 1)
        XCTAssertTrue(result.unreadable.first?.hasSuffix("O/S/bad.json") == true, "\(result.unreadable)")
    }

    func testTextListsAndJsonTandasCanBeMixedInOneZip() throws {
        let result = try scan(
            [("O/S/Json.json", senderSongs(), "Json", .artist, .albumArtist)],
            extraFiles: ["O/S/List.txt": "Alpha Trio - One\nAlpha Trio - Two\nAlpha Trio - Three\n"]
        )

        XCTAssertEqual(result.tandas.count, 2)
        XCTAssertEqual(result.tandas.first { $0.fileName == "Json" }?.isJSON, true)
        XCTAssertEqual(result.tandas.first { $0.fileName == "List" }?.isJSON, false)
    }

    // MARK: - What the window says

    func testTheNoteNamesBothConventions() throws {
        let result = try scan([("O/S/T.json", senderSongs(), "T", .artist, .albumArtist)])

        let note = try XCTUnwrap(SenderConventionNote.text(
            for: result.tandas, ownOrchestra: .grouping, ownSinger: .artist))

        XCTAssertTrue(note.contains("Sender: Orchestra = \(TagSource.artist.displayName), Singer = \(TagSource.albumArtist.displayName)."), note)
        XCTAssertTrue(note.contains("You: Orchestra = \(TagSource.grouping.displayName), Singer = \(TagSource.artist.displayName)."), note)
        XCTAssertTrue(note.contains("by role"), note)
    }

    func testTheNoteSaysWhenConventionsDiffer() throws {
        let result = try scan([
            ("O/S/A.json", senderSongs(), "A", .artist, .albumArtist),
            ("O/S/B.json", senderSongs(), "B", .grouping, .artist)
        ])

        let note = try XCTUnwrap(SenderConventionNote.text(
            for: result.tandas, ownOrchestra: .artist, ownSinger: .albumArtist))

        XCTAssertTrue(note.contains("different conventions"), note)
    }

    func testTheNoteSaysWhenTheConventionIsUnknown() throws {
        let allUnknown = try scan([("O/S/A.json", senderSongs(), "A", nil, nil)])
        let note1 = try XCTUnwrap(SenderConventionNote.text(
            for: allUnknown.tandas, ownOrchestra: .artist, ownSinger: .albumArtist))
        XCTAssertTrue(note1.contains("do not record"), note1)

        let some = try scan([
            ("O/S/A.json", senderSongs(), "A", .artist, .albumArtist),
            ("O/S/B.json", senderSongs(), "B", nil, nil)
        ])
        let note2 = try XCTUnwrap(SenderConventionNote.text(
            for: some.tandas, ownOrchestra: .artist, ownSinger: .albumArtist))
        XCTAssertTrue(note2.contains("1 Tandas record none"), note2)
    }

    func testTextOnlyZipsGetNoNote() throws {
        let result = try scan([], extraFiles: ["O/S/List.txt": "Alpha Trio - One\nAlpha Trio - Two\nAlpha Trio - Three\n"])

        XCTAssertNil(SenderConventionNote.text(
            for: result.tandas, ownOrchestra: .artist, ownSinger: .albumArtist))
    }

    // MARK: - End to end: matching against a different TrackLibrary

    private func library(_ count: Int) -> [Song] {
        (1...count).map {
            var song = makeSong(
                id: Int64($0),
                path: "/Music/\($0).flac",
                title: "Song \($0)",
                artist: "D'Arienzo, Juan",
                albumArtist: "Carbel, Enrique"
            )
            song.fileHash = "my-hash-\($0)"
            return song
        }
    }

    private func evaluate(_ scan: SharedTandaScan, library: [Song]) -> [TandaImportEntry] {
        TandaImportResolver.evaluate(
            scan.tandas,
            library: library,
            orchestraSource: .artist,
            singerSource: .albumArtist,
            autoPickBestFile: false,
            missingSongIDs: [],
            existing: []
        )
    }

    func testATandaFromAnotherConventionIsMatchedByRole() throws {
        // The sender keeps the orchestra in AlbumArtist and the singer in
        // Artist — the opposite of this library. Different paths, no hash
        // in common: only the roles can match.
        let sender = (1...4).map {
            senderSong(Int64($0), artist: "Carbel, Enrique", albumArtist: "D'Arienzo, Juan")
        }
        let result = try scan([("D'Arienzo/Carbel/T.json", sender, "T", .albumArtist, .artist)])

        let entry = try XCTUnwrap(evaluate(result, library: library(4)).first)

        XCTAssertEqual(entry.status, .ready)
        XCTAssertEqual(entry.songs.map(\.id), [1, 2, 3, 4])
    }

    func testTheFileHashFindsTheTrackWhateverTheTagsSay() throws {
        // Completely different tags, but the audio file is the same.
        let sender = (1...3).map { id -> Song in
            var song = senderSong(Int64(id), title: "Other title \(id)", artist: "Someone", albumArtist: "Else")
            song.fileHash = "my-hash-\(id)"
            return song
        }
        let result = try scan([("O/S/T.json", sender, "T", .artist, .albumArtist)])

        let entry = try XCTUnwrap(evaluate(result, library: library(3)).first)

        XCTAssertEqual(entry.status, .ready)
        XCTAssertEqual(entry.songs.map(\.id), [1, 2, 3])
    }

    func testTracksThatAreNotInThisLibraryNeedHelp() throws {
        let sender = (1...3).map {
            senderSong(Int64($0), title: "Unknown \($0)", artist: "D'Arienzo, Juan", albumArtist: "Carbel, Enrique")
        }
        let result = try scan([("O/S/T.json", sender, "T", .artist, .albumArtist)])

        let entry = try XCTUnwrap(evaluate(result, library: library(3)).first)

        XCTAssertNotEqual(entry.status, .ready)
    }
}
