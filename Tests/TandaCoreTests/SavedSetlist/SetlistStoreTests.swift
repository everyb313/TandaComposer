import XCTest
import Foundation

/// Every test runs inside `withTemporaryAppRoot`, so Setlists, the recovery
/// file and everything else are written to a temporary folder, never to
/// `~/.TandaComposer`.
@MainActor
final class SetlistStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore() throws -> SetlistStore {
        SetlistStore(db: try DatabaseManager())
    }

    private func titles(_ store: SetlistStore) -> [String?] {
        store.songs.map(\.title)
    }

    private func letters(_ names: String...) -> [Song] {
        names.enumerated().map { index, name in
            makeSong(id: Int64(index + 1), path: "/Music/\(name).flac", title: name, artist: "Artist \(name)")
        }
    }

    private func setlistFile(_ name: String) -> URL {
        SetlistStore.fileURLOnDisk(forName: name)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private var recoveryFile: URL {
        setlistFile("Recovery (autosaved)")
    }

    // MARK: - Initial state

    func testNewStoreIsEmptyAndClean() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()

            XCTAssertTrue(store.entries.isEmpty)
            XCTAssertEqual(store.name, "Untitled Set")
            XCTAssertFalse(store.hasUnsavedChanges)
            XCTAssertTrue(store.savedSetlistNamesList.isEmpty)
            XCTAssertFalse(store.isDuplicateHighlightingEnabled)
        }
    }

    // MARK: - Editing

    func testAddAppendsInOrderAndMarksTheSetlistUnsaved() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()

            store.add(letters("A", "B"))
            store.add(letters("C"))

            XCTAssertEqual(titles(store), ["A", "B", "C"])
            XCTAssertTrue(store.hasUnsavedChanges)
        }
    }

    func testAddingNothingIsIgnored() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()

            store.add([])

            XCTAssertFalse(store.hasUnsavedChanges)
            XCTAssertFalse(exists(recoveryFile), "no edit, no recovery file")
        }
    }

    func testInsertAtAnIndex() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B", "C"))

            store.insert(letters("X"), at: 1)

            XCTAssertEqual(titles(store), ["A", "X", "B", "C"])
        }
    }

    func testInsertClampsTheIndexIntoTheValidRange() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B"))

            store.insert(letters("First"), at: -5)
            store.insert(letters("Last"), at: 99)

            XCTAssertEqual(titles(store), ["First", "A", "B", "Last"])
        }
    }

    func testMoveFollowsTheUsualListSemantics() throws {
        try withTemporaryAppRoot { _ in
            let cases: [(IndexSet, Int, [String])] = [
                ([0], 3, ["B", "C", "A", "D"]),
                ([3], 0, ["D", "A", "B", "C"]),
                ([0, 1], 4, ["C", "D", "A", "B"]),
                ([1, 2], 0, ["B", "C", "A", "D"]),
                ([1], 2, ["A", "B", "C", "D"]),
                ([1], 1, ["A", "B", "C", "D"])
            ]

            for (source, destination, expected) in cases {
                let store = try makeStore()
                store.add(letters("A", "B", "C", "D"))

                store.move(fromOffsets: source, toOffset: destination)

                XCTAssertEqual(titles(store), expected.map { Optional($0) }, "move \(Array(source)) to \(destination)")
            }
        }
    }

    func testMoveKeepsTheEntryIDs() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B", "C", "D"))
            let ids = store.entries.map(\.id)

            store.move(fromOffsets: [0], toOffset: 3)

            XCTAssertEqual(store.entries.map(\.id), [ids[1], ids[2], ids[0], ids[3]])
        }
    }

    func testRemoveDeletesTheEntriesAndClearsTheSelection() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B", "C", "D"))
            store.updateSelectedRowIndexes([0, 1])

            store.remove(atOffsets: [1, 2])

            XCTAssertEqual(titles(store), ["A", "D"])
            XCTAssertTrue(store.selectedRowIndexes.isEmpty)
        }
    }

    func testRemovingNothingIsIgnored() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A"))
            store.updateSelectedRowIndexes([0])

            store.remove(atOffsets: [])

            XCTAssertEqual(titles(store), ["A"])
            XCTAssertEqual(store.selectedRowIndexes, [0], "selection stays when nothing was removed")
        }
    }

    /// Regression guard: edits used to rebuild every entry and reset ids/status.
    func testEditsDoNotTouchTheIDsOfOtherEntries() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B", "C"))
            let originalIDs = store.entries.map(\.id)

            store.add(letters("D"))
            XCTAssertEqual(Array(store.entries.map(\.id).prefix(3)), originalIDs)

            store.insert(letters("X"), at: 0)
            XCTAssertEqual(Array(store.entries.map(\.id).suffix(4).prefix(3)), originalIDs)

            store.remove(atOffsets: [2])   // removes "B"
            let remaining = store.entries.map(\.id)
            XCTAssertTrue(remaining.contains(originalIDs[0]))
            XCTAssertFalse(remaining.contains(originalIDs[1]))
            XCTAssertTrue(remaining.contains(originalIDs[2]))
        }
    }

    func testSongsIsAPlainViewOnTheEntries() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B"))

            XCTAssertEqual(store.songs.map(\.filename), ["A.flac", "B.flac"])
            XCTAssertEqual(store.songs.count, store.entries.count)
        }
    }

    // MARK: - Duplicate highlighting

    private func duplicateFixtures() -> [Song] {
        [
            makeSong(id: 1, path: "/Music/1.flac", title: "Poema", artist: "Di Sarli"),
            makeSong(id: 2, path: "/Music/2.flac", title: "  poema ", artist: "di sarli"),
            makeSong(id: 3, path: "/Music/3.flac", title: "Other", artist: "Di Sarli")
        ]
    }

    func testDuplicatesAreFoundIgnoringCaseAndSurroundingSpaces() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(duplicateFixtures())

            store.toggleDuplicateHighlighting()

            XCTAssertTrue(store.isDuplicateHighlightingEnabled)
            XCTAssertEqual(store.duplicateSongIDs, [1, 2])
        }
    }

    func testDuplicatesAreNotComputedWhileHighlightingIsOff() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()

            store.add(duplicateFixtures())

            XCTAssertTrue(store.duplicateSongIDs.isEmpty)
        }
    }

    func testDuplicatesFollowEditsWhileHighlightingIsOn() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(duplicateFixtures())
            store.toggleDuplicateHighlighting()

            store.remove(atOffsets: [1])
            XCTAssertTrue(store.duplicateSongIDs.isEmpty)

            store.add([makeSong(id: 4, path: "/Music/4.flac", title: "Other", artist: "Di Sarli")])
            XCTAssertEqual(store.duplicateSongIDs, [3, 4])
        }
    }

    func testTurningHighlightingOffClearsTheDuplicates() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(duplicateFixtures())
            store.toggleDuplicateHighlighting()

            store.toggleDuplicateHighlighting()

            XCTAssertFalse(store.isDuplicateHighlightingEnabled)
            XCTAssertTrue(store.duplicateSongIDs.isEmpty)
        }
    }

    // MARK: - Undo

    /// Call this AFTER the setup edits: with `groupsByEvent == false` the
    /// UndoManager throws if an undo is registered outside an open group.
    private func makeUndoManager(for store: SetlistStore) -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        return undo
    }

    private func grouped(_ undo: UndoManager, _ action: () -> Void) {
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
    }

    func testUndoAdd() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A"))
            let undo = makeUndoManager(for: store)

            grouped(undo) { store.add(letters("B", "C")) }
            XCTAssertTrue(undo.canUndo)
            undo.undo()

            XCTAssertEqual(titles(store), ["A"])
        }
    }

    func testUndoInsert() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B"))
            let undo = makeUndoManager(for: store)

            grouped(undo) { store.insert(letters("X", "Y"), at: 1) }
            undo.undo()

            XCTAssertEqual(titles(store), ["A", "B"])
        }
    }

    func testUndoRemoveRestoresTheSameEntriesAtTheirPositions() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B", "C", "D"))
            let undo = makeUndoManager(for: store)
            let idsBefore = store.entries.map(\.id)

            grouped(undo) { store.remove(atOffsets: [1, 2]) }
            XCTAssertEqual(titles(store), ["A", "D"])
            undo.undo()

            XCTAssertEqual(titles(store), ["A", "B", "C", "D"])
            XCTAssertEqual(store.entries.map(\.id), idsBefore)
        }
    }

    func testUndoMove() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B", "C"))
            let undo = makeUndoManager(for: store)

            grouped(undo) { store.move(fromOffsets: [0], toOffset: 3) }
            XCTAssertEqual(titles(store), ["B", "C", "A"])
            undo.undo()

            XCTAssertEqual(titles(store), ["A", "B", "C"])
        }
    }

    func testEditsWithoutAnUndoManagerStillWork() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            XCTAssertNil(store.undoManager)

            store.add(letters("A"))

            XCTAssertEqual(titles(store), ["A"])
        }
    }

    // MARK: - Save

    func testSaveWritesTheNamedFileIntoTheSetlistsFolder() throws {
        try withTemporaryAppRoot { root in
            let store = try makeStore()
            store.name = "Friday"
            store.add(letters("A", "B"))

            try store.save()

            let expected = root.appendingPathComponent("Default/Setlists/Friday.json")
            XCTAssertTrue(samePath(setlistFile("Friday"), expected))
            XCTAssertTrue(exists(expected))
            XCTAssertEqual(store.savedSetlistNamesList, ["Friday"])
            XCTAssertFalse(store.hasUnsavedChanges)
            XCTAssertTrue(store.isSavedAndUnchanged)
        }
    }

    func testSavedFileContainsTheSongsAndTheLibraryName() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Friday"
            store.add(letters("A", "B"))

            try store.save()
            let loaded = try SetlistMetadataExporter.load(from: setlistFile("Friday"))

            XCTAssertEqual(loaded.setlistName, "Friday")
            XCTAssertEqual(loaded.songs.map(\.title), ["A", "B"])
            XCTAssertEqual(loaded.savedAgainstLibraryName, "Default")
        }
    }

    func testSaveAsTrimsTheName() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()

            try store.saveAs(name: "  Late Night \n")

            XCTAssertEqual(store.name, "Late Night")
            XCTAssertTrue(exists(setlistFile("Late Night")))
        }
    }

    func testSaveAsRejectsAnEmptyName() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Keep"

            do {
                try store.saveAs(name: "  \n ")
                XCTFail("expected invalidSetlistName")
            } catch SetlistStoreError.invalidSetlistName {
                // expected
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertEqual(store.name, "Keep")
            XCTAssertTrue(store.savedSetlistNamesList.isEmpty)
        }
    }

    func testSaveAsWithANewNameRenamesTheSavedFile() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Old"
            store.add(letters("A"))
            try store.save()

            try store.saveAs(name: "New")

            XCTAssertTrue(exists(setlistFile("New")))
            XCTAssertFalse(exists(setlistFile("Old")))
            XCTAssertEqual(store.savedSetlistNamesList, ["New"])
            XCTAssertEqual(store.name, "New")
        }
    }

    func testSaveAsCanKeepTheOldFile() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Old"
            try store.save()

            try store.saveAs(name: "Copy", deleteOldName: false)

            XCTAssertTrue(exists(setlistFile("Old")))
            XCTAssertTrue(exists(setlistFile("Copy")))
            XCTAssertEqual(store.savedSetlistNamesList, ["Copy", "Old"])
        }
    }

    func testSaveUnderAChangedNameNeverDeletesTheOldFile() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "A"
            try store.save()

            store.name = "B"
            try store.save()

            XCTAssertTrue(exists(setlistFile("A")))
            XCTAssertTrue(exists(setlistFile("B")))
        }
    }

    func testRenameWithoutAnExistingOldFileDoesNotFail() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Never Saved"

            XCTAssertNoThrow(try store.saveAs(name: "Fresh"))
            XCTAssertTrue(exists(setlistFile("Fresh")))
        }
    }

    func testSavingCreatesTheSetlistsFolderIfNeeded() throws {
        try withTemporaryAppRoot { root in
            let store = try makeStore()
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Default").path))

            try store.save()

            XCTAssertTrue(exists(setlistFile("Untitled Set")))
        }
    }

    func testIsSavedAndUnchangedNeedsASavedFileAndNoEdits() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            XCTAssertFalse(store.isSavedAndUnchanged, "nothing saved yet")

            try store.save()
            XCTAssertTrue(store.isSavedAndUnchanged)

            store.add(letters("A"))
            XCTAssertFalse(store.isSavedAndUnchanged)
        }
    }

    // MARK: - Load

    func testLoadRestoresNameAndSongsInAFreshStore() throws {
        try withTemporaryAppRoot { _ in
            let writer = try makeStore()
            writer.name = "Friday"
            writer.add(letters("A", "B", "C"))
            try writer.save()

            let reader = try makeStore()
            try reader.load(setlistName: "Friday")

            XCTAssertEqual(reader.name, "Friday")
            XCTAssertEqual(titles(reader), ["A", "B", "C"])
            XCTAssertEqual(reader.songs.map(\.path), ["/Music/A.flac", "/Music/B.flac", "/Music/C.flac"])
            XCTAssertEqual(reader.savedAgainstLibraryName, "Default")
            XCTAssertFalse(reader.hasUnsavedChanges)
        }
    }

    func testLoadOfAnUnknownNameThrows() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()

            do {
                try store.load(setlistName: "Nope")
                XCTFail("expected setlistNotFound")
            } catch SetlistStoreError.setlistNotFound(let name) {
                XCTAssertEqual(name, "Nope")
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testLoadReplacesTheOpenSetlistAndDiscardsItsRecovery() throws {
        try withTemporaryAppRoot { _ in
            let saver = try makeStore()
            saver.name = "Saved"
            saver.add(letters("S"))
            try saver.save()

            let store = try makeStore()
            store.add(letters("X", "Y"))
            XCTAssertTrue(exists(recoveryFile))

            try store.load(setlistName: "Saved")

            XCTAssertEqual(titles(store), ["S"])
            XCTAssertFalse(exists(recoveryFile))
            XCTAssertFalse(store.hasUnsavedChanges)
        }
    }

    func testLoadedEntriesHaveTheDefaultStatus() throws {
        try withTemporaryAppRoot { _ in
            let writer = try makeStore()
            writer.add(letters("A"))
            try writer.save()

            let reader = try makeStore()
            try reader.load(setlistName: "Untitled Set")

            XCTAssertEqual(reader.entries.first?.status, .resolved)
        }
    }

    // MARK: - Names list

    func testSavedNamesAreSortedNaturallyAndSkipOtherFiles() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            for name in ["Set 10", "Set 2", "Alpha"] {
                try store.saveAs(name: name, deleteOldName: false)
            }
            let folder = AppPaths.setlistsFolder
            FileManager.default.createFile(atPath: folder.appendingPathComponent("notes.txt").path, contents: Data())
            FileManager.default.createFile(atPath: folder.appendingPathComponent("Old (autosaved).json").path, contents: Data("{}".utf8))

            XCTAssertEqual(try SetlistStore.listSetlistNamesOnDisk(), ["Alpha", "Set 2", "Set 10"])
            XCTAssertEqual(try store.listSetlistNames(), ["Alpha", "Set 2", "Set 10"])
        }
    }

    func testNamesOfAMissingFolderAreEmpty() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertEqual(try SetlistStore.listSetlistNamesOnDisk(), [])
        }
    }

    // MARK: - New and delete

    func testNewSetlistResetsEverything() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A", "B"))
            store.updateSelectedRowIndexes([0])
            XCTAssertTrue(exists(recoveryFile))

            store.newSetlist(named: "Fresh")

            XCTAssertEqual(store.name, "Fresh")
            XCTAssertTrue(store.entries.isEmpty)
            XCTAssertTrue(store.selectedRowIndexes.isEmpty)
            XCTAssertFalse(store.hasUnsavedChanges)
            XCTAssertFalse(exists(recoveryFile))
            XCTAssertEqual(store.savedAgainstLibraryName, "Default")
        }
    }

    func testNewSetlistWithoutANameIsCalledUntitledSet() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Something"

            store.newSetlist()

            XCTAssertEqual(store.name, "Untitled Set")
        }
    }

    func testDeleteRemovesTheSavedFile() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Old"
            try store.save()
            store.newSetlist(named: "Current")

            try store.delete(setlistName: "Old")

            XCTAssertFalse(exists(setlistFile("Old")))
            XCTAssertTrue(store.savedSetlistNamesList.isEmpty)
        }
    }

    func testTheOpenSetlistCannotBeDeleted() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Open"
            try store.save()

            try store.delete(setlistName: "Open")

            XCTAssertTrue(exists(setlistFile("Open")))
        }
    }

    func testDeletingAnUnknownSetlistIsHarmless() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()

            XCTAssertNoThrow(try store.delete(setlistName: "Nope"))
        }
    }

    // MARK: - Recovery

    func testEveryEditWritesARecoveryFileThatIsNotListedAsASetlist() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Draft"

            store.add(letters("A", "B"))

            XCTAssertTrue(exists(recoveryFile))
            let info = try XCTUnwrap(SetlistStore.pendingRecoveryInfo())
            XCTAssertEqual(info.name, "Draft")
            XCTAssertEqual(info.songCount, 2)
            XCTAssertNil(info.savedFileSongCount, "no saved file yet")
            XCTAssertTrue(try SetlistStore.listSetlistNamesOnDisk().isEmpty)
        }
    }

    func testSavingRemovesTheRecoveryFile() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A"))
            XCTAssertNotNil(SetlistStore.pendingRecoveryInfo())

            try store.save()

            XCTAssertNil(SetlistStore.pendingRecoveryInfo())
            XCTAssertFalse(exists(recoveryFile))
        }
    }

    func testRecoveryNeverTouchesTheSavedSetlistFile() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.name = "Draft"
            store.add(letters("A", "B"))
            try store.save()

            store.add(letters("C"))

            let saved = try SetlistMetadataExporter.load(from: setlistFile("Draft"))
            XCTAssertEqual(saved.songs.count, 2)
            let info = try XCTUnwrap(SetlistStore.pendingRecoveryInfo())
            XCTAssertEqual(info.songCount, 3)
            XCTAssertEqual(info.savedFileSongCount, 2)
        }
    }

    func testRestoreFromRecoveryInAFreshStore() throws {
        try withTemporaryAppRoot { _ in
            let crashed = try makeStore()
            crashed.name = "Draft"
            crashed.add(letters("A", "B", "C"))

            let restarted = try makeStore()
            XCTAssertEqual(SetlistStore.pendingRecoveryInfo()?.name, "Draft")
            try restarted.restoreFromRecovery()

            XCTAssertEqual(restarted.name, "Draft")
            XCTAssertEqual(titles(restarted), ["A", "B", "C"])
            XCTAssertTrue(restarted.hasUnsavedChanges, "restored work is still unsaved")
        }
    }

    func testDiscardRecovery() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()
            store.add(letters("A"))

            store.discardRecovery()

            XCTAssertNil(SetlistStore.pendingRecoveryInfo())
            XCTAssertFalse(store.hasUnsavedChanges)
        }
    }

    func testRestoreWithoutARecoveryFileThrows() throws {
        try withTemporaryAppRoot { _ in
            let store = try makeStore()

            XCTAssertNil(SetlistStore.pendingRecoveryInfo())
            XCTAssertThrowsError(try store.restoreFromRecovery())
        }
    }

    func testBrokenRecoveryFileIsTreatedAsNoRecovery() throws {
        try withTemporaryAppRoot { _ in
            try FileManager.default.createDirectory(at: AppPaths.setlistsFolder, withIntermediateDirectories: true)
            try "garbage".write(to: recoveryFile, atomically: true, encoding: .utf8)

            XCTAssertNil(SetlistStore.pendingRecoveryInfo())
        }
    }

    // MARK: - Errors

    func testErrorDescriptions() {
        XCTAssertTrue(SetlistStoreError.setlistNotFound("Friday").errorDescription?.contains("Friday") == true)
        XCTAssertNotNil(SetlistStoreError.invalidSetlistName.errorDescription)
    }
}
