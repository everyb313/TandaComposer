import XCTest
import Foundation

/// The read-only viewer for saved Setlists.
@MainActor
final class SavedSetlistViewerStoreTests: XCTestCase {

    private func song(_ id: Int64, _ path: String, title: String? = nil) -> Song {
        makeSong(id: id, path: path, title: title ?? "T\(id)")
    }

    @discardableResult
    private func saveSetlist(
        _ name: String,
        setlistName: String? = nil,
        songs: [Song],
        savedAgainst: String? = "Default"
    ) throws -> URL {
        try FileManager.default.createDirectory(at: AppPaths.setlistsFolder, withIntermediateDirectories: true)
        let url = AppPaths.setlistsFolder.appendingPathComponent(name).appendingPathExtension("json")
        try SetlistMetadataExporter.export(
            songs: songs,
            setlistName: setlistName ?? name,
            to: url,
            savedAgainstLibraryName: savedAgainst
        )
        return url
    }

    func testStartsEmpty() {
        let viewer = SavedSetlistViewerStore()

        XCTAssertNil(viewer.setlistName)
        XCTAssertTrue(viewer.songs.isEmpty)
        XCTAssertNil(viewer.savedAgainstLibraryName)
    }

    func testLoadReadsNameSongsAndLibraryName() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [song(1, "/Music/1.flac"), song(2, "/Music/2.flac")])
            let viewer = SavedSetlistViewerStore()

            try viewer.load(name: "Friday")

            XCTAssertEqual(viewer.setlistName, "Friday")
            XCTAssertEqual(viewer.songs.map(\.title), ["T1", "T2"])
            XCTAssertEqual(viewer.savedAgainstLibraryName, "Default")
        }
    }

    func testTheNameComesFromTheFileContentNotTheFileName() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("file-name", setlistName: "Name Inside", songs: [])
            let viewer = SavedSetlistViewerStore()

            try viewer.load(name: "file-name")

            XCTAssertEqual(viewer.setlistName, "Name Inside")
        }
    }

    func testLoadOfAMissingSetlistThrowsAndKeepsThePreviousContent() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [song(1, "/Music/1.flac")])
            let viewer = SavedSetlistViewerStore()
            try viewer.load(name: "Friday")

            XCTAssertThrowsError(try viewer.load(name: "Nope"))

            XCTAssertEqual(viewer.setlistName, "Friday")
            XCTAssertEqual(viewer.songs.count, 1)
        }
    }

    func testWithoutLibraryTablesTheSongsStayAsStored() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [song(1, "/Old/1.flac")])
            let viewer = SavedSetlistViewerStore()

            try viewer.load(name: "Friday")

            XCTAssertEqual(viewer.songs.first?.path, "/Old/1.flac")
        }
    }

    func testLoadWithLibraryTablesReplacesSongsByTheLiveOnes() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [song(1, "/Old/1.flac"), song(2, "/Music/2.flac")])
            let live1 = song(1, "/New/1.flac", title: "Live 1")
            let viewer = SavedSetlistViewerStore()

            try viewer.load(
                name: "Friday",
                byID: [1: live1],
                byPath: [live1.normalizedPath: live1],
                missingSongIDs: []
            )

            XCTAssertEqual(viewer.songs.map(\.title), ["Live 1", "T2"], "unknown songs are shown as stored")
            XCTAssertEqual(viewer.songs.first?.path, "/New/1.flac")
        }
    }

    func testIDsOfAnotherLibraryAreNotTrustedWhenResolving() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Imported", songs: [song(7, "/Music/x.flac")], savedAgainst: "Other")
            let sameID = song(7, "/Elsewhere/y.flac", title: "Unrelated")
            let samePath = song(1, "/Music/x.flac", title: "Right One")
            let viewer = SavedSetlistViewerStore()

            try viewer.load(
                name: "Imported",
                byID: [7: sameID, 1: samePath],
                byPath: [samePath.normalizedPath: samePath, sameID.normalizedPath: sameID],
                missingSongIDs: []
            )

            XCTAssertEqual(viewer.songs.first?.title, "Right One")
        }
    }

    func testResolveCanBeCalledLaterWithNewTables() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [song(1, "/Old/1.flac")])
            let viewer = SavedSetlistViewerStore()
            try viewer.load(name: "Friday")
            let live = song(1, "/New/1.flac")

            viewer.resolveAgainstLibrary(byID: [1: live], byPath: [:], missingSongIDs: [1])

            XCTAssertEqual(viewer.songs.first?.path, "/New/1.flac", "missing files are still shown with their live data")
        }
    }

    func testClearForgetsEverything() throws {
        try withTemporaryAppRoot { _ in
            try saveSetlist("Friday", songs: [song(1, "/Music/1.flac")])
            let viewer = SavedSetlistViewerStore()
            try viewer.load(name: "Friday")

            viewer.clear()

            XCTAssertNil(viewer.setlistName)
            XCTAssertTrue(viewer.songs.isEmpty)
            XCTAssertNil(viewer.savedAgainstLibraryName)
        }
    }
}
