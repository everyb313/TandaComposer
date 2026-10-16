import XCTest
import Foundation

@MainActor
final class TrackTextNormalizerTests: XCTestCase {

    // MARK: - normalize

    func testNilAndBlankValuesNormalizeToNil() {
        XCTAssertNil(TrackTextNormalizer.normalize(nil))
        XCTAssertNil(TrackTextNormalizer.normalize(""))
        XCTAssertNil(TrackTextNormalizer.normalize("   \n\t "))
    }

    func testCaseAndOuterWhitespaceAreRemoved() {
        XCTAssertEqual(TrackTextNormalizer.normalize("  Poema \n"), "poema")
        XCTAssertEqual(TrackTextNormalizer.normalize("LA CUMPARSITA"), "la cumparsita")
    }

    func testDiacriticsAreRemoved() {
        XCTAssertEqual(TrackTextNormalizer.normalize("Rodr\u{00ED}guez"), "rodriguez")
        XCTAssertEqual(TrackTextNormalizer.normalize("M\u{00FC}ller"), "muller")
        XCTAssertEqual(TrackTextNormalizer.normalize("Coraz\u{00F3}n"), "corazon")
    }

    func testDecomposedAndPrecomposedAccentsGiveTheSameResult() {
        XCTAssertEqual(
            Array((TrackTextNormalizer.normalize("Cafe\u{0301}") ?? "").utf8),
            Array((TrackTextNormalizer.normalize("Caf\u{00E9}") ?? "").utf8)
        )
    }

    func testAllApostropheVariantsAreUnified() {
        let variants = ["D'Arienzo", "D\u{2019}Arienzo", "D\u{2018}Arienzo", "D\u{00B4}Arienzo", "D`Arienzo"]

        for variant in variants {
            XCTAssertEqual(TrackTextNormalizer.normalize(variant), "d'arienzo", variant)
        }
    }

    func testInnerWhitespaceIsCollapsed() {
        XCTAssertEqual(TrackTextNormalizer.normalize("Di   Sarli\t Orquesta"), "di sarli orquesta")
        XCTAssertEqual(TrackTextNormalizer.normalize("Di\nSarli"), "di sarli")
    }

    // MARK: - normalizeFilename

    func testFilenameLosesFolderAndExtension() {
        XCTAssertEqual(TrackTextNormalizer.normalizeFilename("/Music/Tango/One Song.FLAC"), "one song")
        XCTAssertEqual(TrackTextNormalizer.normalizeFilename("One Song.mp3"), "one song")
    }

    func testFilenameWithoutExtensionIsJustNormalized() {
        XCTAssertEqual(TrackTextNormalizer.normalizeFilename("Plain Name"), "plain name")
    }

    func testOnlyTheLastExtensionIsRemoved() {
        XCTAssertEqual(TrackTextNormalizer.normalizeFilename("name.with.dots.flac"), "name.with.dots")
    }

    func testNilFilenameIsNil() {
        XCTAssertNil(TrackTextNormalizer.normalizeFilename(nil))
    }

    // MARK: - equals

    func testEqualsComparesTheNormalizedForms() {
        XCTAssertTrue(TrackTextNormalizer.equals("Rodr\u{00ED}guez", "RODRIGUEZ "))
        XCTAssertTrue(TrackTextNormalizer.equals("D\u{2019}Arienzo", "d'arienzo"))
        XCTAssertFalse(TrackTextNormalizer.equals("Poema", "Poemas"))
    }

    func testEmptyOrMissingValuesNeverAreEqual() {
        XCTAssertFalse(TrackTextNormalizer.equals(nil, nil))
        XCTAssertFalse(TrackTextNormalizer.equals("", ""))
        XCTAssertFalse(TrackTextNormalizer.equals("  ", nil))
        XCTAssertFalse(TrackTextNormalizer.equals("Poema", nil))
    }
}

@MainActor
final class TrackMetadataProfileTests: XCTestCase {

    private func song(artist: String?, albumArtist: String?, grouping: String?) -> Song {
        var song = makeSong(path: "/Music/a.flac", title: "Poema", artist: artist, albumArtist: albumArtist, grouping: grouping)
        song.key = "Am"
        song.bpm = 111.5
        return song
    }

    func testProfileOfASongCopiesTheComparableFields() {
        var source = makeSong(
            path: "/Music/poema.flac",
            title: "Poema",
            artist: "Alpha Trio",
            albumArtist: "Singer X",
            album: "Album One"
        )
        source.duration = 215
        source.bpm = 111.5
        source.key = "Am"

        let profile = TrackMetadataProfile(song: source)

        XCTAssertEqual(profile.title, "Poema")
        XCTAssertEqual(profile.album, "Album One")
        XCTAssertEqual(profile.duration, 215)
        XCTAssertEqual(profile.bpm, 111.5)
        XCTAssertEqual(profile.key, "Am")
        XCTAssertEqual(profile.filename, "poema.flac")
    }

    func testProfileOfAnImportedTrackCopiesTheComparableFields() {
        let track = ImportedTrack(
            sourceIndex: 0,
            filename: "x.flac",
            title: "Poema",
            album: "Album One",
            duration: 215,
            bpm: 111.5,
            key: "Am"
        )

        let profile = TrackMetadataProfile(importedTrack: track)

        XCTAssertEqual(profile.title, "Poema")
        XCTAssertEqual(profile.filename, "x.flac")
        XCTAssertEqual(profile.duration, 215)
        XCTAssertEqual(profile.bpm, 111.5)
        XCTAssertEqual(profile.key, "Am")
    }

    func testPreferredFieldComesFirstThenTheOtherTagsWithoutDuplicates() {
        let profile = TrackMetadataProfile(
            song: song(artist: "Alpha Trio", albumArtist: "Singer X", grouping: "alpha trio")
        )

        XCTAssertEqual(profile.orchestraValues, ["Alpha Trio", "Singer X"])
        XCTAssertEqual(profile.singerValues, ["Singer X", "Alpha Trio"])
    }

    func testBlankAndMissingTagsAreSkipped() {
        let profile = TrackMetadataProfile(
            song: song(artist: "  ", albumArtist: nil, grouping: " Group A ")
        )

        XCTAssertEqual(profile.orchestraValues, ["Group A"])
        XCTAssertEqual(profile.singerValues, ["Group A"])
    }

    func testNoTagsGiveNoRoleValues() {
        let profile = TrackMetadataProfile(song: song(artist: nil, albumArtist: nil, grouping: nil))

        XCTAssertTrue(profile.orchestraValues.isEmpty)
        XCTAssertTrue(profile.singerValues.isEmpty)
    }

    func testTagSourcesDecideWhichFieldComesFirst() {
        let profile = TrackMetadataProfile(
            song: song(artist: "Alpha Trio", albumArtist: "Singer X", grouping: "Group A"),
            orchestraSource: .grouping,
            singerSource: .artist
        )

        XCTAssertEqual(profile.orchestraValues.first, "Group A")
        XCTAssertEqual(profile.singerValues.first, "Alpha Trio")
        XCTAssertEqual(Set(profile.orchestraValues), ["Alpha Trio", "Singer X", "Group A"])
    }

    func testImportedTracksUseTheSameRules() {
        let track = ImportedTrack(sourceIndex: 0, artist: "Alpha Trio", albumArtist: "Singer X", grouping: "ALPHA TRIO")

        let profile = TrackMetadataProfile(importedTrack: track)

        XCTAssertEqual(profile.orchestraValues, ["Alpha Trio", "Singer X"])
        XCTAssertEqual(profile.singerValues, ["Singer X", "Alpha Trio"])
    }
}
