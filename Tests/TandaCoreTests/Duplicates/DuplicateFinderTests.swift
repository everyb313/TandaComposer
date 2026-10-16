import XCTest
import Foundation

@MainActor
final class DuplicateFinderTests: XCTestCase {

    private let separator = "\u{241F}"
    private let missing = "\u{2400}"

    private func song(
        _ id: Int64,
        title: String? = nil,
        artist: String? = nil,
        albumArtist: String? = nil,
        album: String? = nil,
        path: String? = nil
    ) -> Song {
        makeSong(
            id: id,
            path: path ?? "/Music/\(id).flac",
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album
        )
    }

    private func ids(_ cluster: DuplicateCluster) -> [Int64?] {
        cluster.songs.map(\.id)
    }

    // MARK: - Level 1: song name

    func testNoSongsNoClusters() {
        XCTAssertTrue(DuplicateFinder.findClusters(in: [], level: .songName).isEmpty)
    }

    func testUniqueSongsFormNoClusters() {
        let songs = [song(1, title: "Poema"), song(2, title: "La Cumparsita"), song(3, title: "Bahia Blanca")]

        XCTAssertTrue(DuplicateFinder.findClusters(in: songs, level: .songName).isEmpty)
    }

    func testSameTitleFormsACluster() {
        let songs = [song(1, title: "Poema"), song(2, title: "Other"), song(3, title: "Poema")]

        let clusters = DuplicateFinder.findClusters(in: songs, level: .songName)

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(ids(clusters[0]), [1, 3])
    }

    func testTitleComparisonIgnoresCaseDiacriticsAndOuterWhitespace() {
        let songs = [
            song(1, title: "Poema"),
            song(2, title: "  poema \n"),
            song(3, title: "P\u{00F3}ema"),
            song(4, title: "Unrelated")
        ]

        let clusters = DuplicateFinder.findClusters(in: songs, level: .songName)

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(ids(clusters[0]), [1, 2, 3])
    }

    func testMissingTitleFallsBackToTheFullFileName() {
        let songs = [
            song(1, path: "/A/same.flac"),
            song(2, path: "/B/same.flac"),
            song(3, path: "/C/other.flac")
        ]

        let clusters = DuplicateFinder.findClusters(in: songs, level: .songName)

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(ids(clusters[0]), [1, 2])
    }

    func testFileNameFallbackKeepsTheExtension() {
        let songs = [song(1, path: "/A/same.flac"), song(2, path: "/B/same.mp3")]

        XCTAssertTrue(DuplicateFinder.findClusters(in: songs, level: .songName).isEmpty)
    }

    func testAMissingTitleIsReplacedByTheFileNameWhenComparing() {
        let songs = [song(1, title: "one.flac"), song(2, path: "/A/one.flac")]

        XCTAssertEqual(DuplicateFinder.findClusters(in: songs, level: .songName).count, 1)
    }

    // MARK: - Higher levels

    func testLevelTwoSeparatesDifferentArtists() {
        let songs = [
            song(1, title: "Poema", artist: "Di Sarli"),
            song(2, title: "Poema", artist: "D'Arienzo")
        ]

        XCTAssertEqual(DuplicateFinder.findClusters(in: songs, level: .songName).count, 1)
        XCTAssertTrue(DuplicateFinder.findClusters(in: songs, level: .songArtist).isEmpty)
    }

    func testLevelTwoMatchesSameArtistIgnoringCase() {
        let songs = [
            song(1, title: "Poema", artist: "Di Sarli"),
            song(2, title: "Poema", artist: "di sarli")
        ]

        XCTAssertEqual(DuplicateFinder.findClusters(in: songs, level: .songArtist).count, 1)
    }

    func testLevelThreeAlsoComparesTheAlbumArtist() {
        let songs = [
            song(1, title: "Poema", artist: "Di Sarli", albumArtist: "Rufino"),
            song(2, title: "Poema", artist: "Di Sarli", albumArtist: "Podest\u{00E1}")
        ]

        XCTAssertEqual(DuplicateFinder.findClusters(in: songs, level: .songArtist).count, 1)
        XCTAssertTrue(DuplicateFinder.findClusters(in: songs, level: .songArtistAlbumArtist).isEmpty)
    }

    func testLevelFourAlsoComparesTheAlbum() {
        let songs = [
            song(1, title: "Poema", artist: "Di Sarli", albumArtist: "Rufino", album: "Album One"),
            song(2, title: "Poema", artist: "Di Sarli", albumArtist: "Rufino", album: "Album Two"),
            song(3, title: "Poema", artist: "Di Sarli", albumArtist: "Rufino", album: "album one")
        ]

        XCTAssertEqual(DuplicateFinder.findClusters(in: songs, level: .songArtistAlbumArtist).count, 1)

        let level4 = DuplicateFinder.findClusters(in: songs, level: .songArtistAlbumArtistAlbum)
        XCTAssertEqual(level4.count, 1)
        XCTAssertEqual(ids(level4[0]), [1, 3])
    }

    func testMissingValuesMatchEachOtherButNotRealValues() {
        let bothMissing = [song(1, title: "Poema"), song(2, title: "Poema")]
        XCTAssertEqual(DuplicateFinder.findClusters(in: bothMissing, level: .songArtist).count, 1)

        let oneMissing = [song(1, title: "Poema"), song(2, title: "Poema", artist: "Di Sarli")]
        XCTAssertTrue(DuplicateFinder.findClusters(in: oneMissing, level: .songArtist).isEmpty)
    }

    func testHigherLevelsNeverAddSongsToClusters() {
        let songs = [
            song(1, title: "Poema", artist: "A", albumArtist: "S", album: "X"),
            song(2, title: "Poema", artist: "A", albumArtist: "S", album: "Y"),
            song(3, title: "Poema", artist: "A", albumArtist: "T", album: "X"),
            song(4, title: "Poema", artist: "B", albumArtist: "S", album: "X"),
            song(5, title: "Other", artist: "A", albumArtist: "S", album: "X")
        ]

        let counts = DuplicateLevel.allCases.map { level in
            DuplicateFinder.findClusters(in: songs, level: level).flatMap(\.songs).count
        }

        XCTAssertEqual(counts, counts.sorted(by: >), "each level is a refinement of the one before")
        XCTAssertEqual(counts.first, 4)
    }

    // MARK: - Clusters

    func testClusterKeysIdentifyTheComparedValues() {
        let songs = [
            song(1, title: "Poema", artist: "Di Sarli"),
            song(2, title: "POEMA", artist: "di sarli")
        ]

        XCTAssertEqual(
            DuplicateFinder.findClusters(in: songs, level: .songName).first?.key,
            "poema"
        )
        XCTAssertEqual(
            DuplicateFinder.findClusters(in: songs, level: .songArtist).first?.key,
            "poema\(separator)di sarli"
        )
        XCTAssertEqual(
            DuplicateFinder.findClusters(in: songs, level: .songArtistAlbumArtist).first?.key,
            "poema\(separator)di sarli\(separator)\(missing)"
        )
    }

    func testClusterIDIsItsKey() {
        let songs = [song(1, title: "Poema"), song(2, title: "Poema")]

        let cluster = DuplicateFinder.findClusters(in: songs, level: .songName)[0]

        XCTAssertEqual(cluster.id, cluster.key)
    }

    func testClustersAreSortedNaturallyByKey() {
        let songs = [
            song(1, title: "Song 10"), song(2, title: "Song 10"),
            song(3, title: "Song 2"), song(4, title: "Song 2"),
            song(5, title: "Alpha"), song(6, title: "Alpha")
        ]

        let keys = DuplicateFinder.findClusters(in: songs, level: .songName).map(\.key)

        XCTAssertEqual(keys, ["alpha", "song 2", "song 10"])
    }

    func testSongsInsideAClusterKeepTheirInputOrder() {
        let songs = [
            song(9, title: "Poema"), song(3, title: "Poema"), song(7, title: "Poema"), song(1, title: "Poema")
        ]

        let cluster = DuplicateFinder.findClusters(in: songs, level: .songName)[0]

        XCTAssertEqual(ids(cluster), [9, 3, 7, 1])
    }

    func testResultIsTheSameForTheSameInput() {
        let songs = (1...20).map { song(Int64($0), title: "T\($0 % 4)") }

        let first = DuplicateFinder.findClusters(in: songs, level: .songName).map(\.key)
        let second = DuplicateFinder.findClusters(in: songs, level: .songName).map(\.key)

        XCTAssertEqual(first, second)
    }

    // MARK: - Levels

    func testLevelsAreNumberedOneToFour() {
        XCTAssertEqual(DuplicateLevel.allCases.map(\.rawValue), [1, 2, 3, 4])
        XCTAssertEqual(DuplicateLevel.allCases.map(\.id), [1, 2, 3, 4])
        XCTAssertTrue(DuplicateLevel.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
