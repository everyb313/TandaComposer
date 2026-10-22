import XCTest
import Foundation

/// `SmartlistStore` manages the folder tree of Smartlist rule-set files:
/// create, save, delete, move (drag and drop), export and import.
@MainActor
final class SmartListStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore() throws -> (store: SmartlistStore, root: URL) {
        // Real path (/private/var/...): FileManager lists children under it,
        // and node ids are paths. `canonicalURL` is the shared helper from
        // TestSupport (`resolvingSymlinksInPath()` would strip /private again).
        let root = canonicalURL(try makeTemporaryDirectory())
            .appendingPathComponent("Smartlists", isDirectory: true)

        return (SmartlistStore(rootURLOverride: root), root)
    }

    private func names(_ node: SmartlistNode) -> [String] {
        node.children.map(\.name)
    }

    private func child(_ name: String, of node: SmartlistNode) -> SmartlistNode? {
        node.children.first { $0.name == name }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func writeRuleSet(named name: String, to url: URL) throws {
        try JSONEncoder().encode(SmartListRuleSet(name: name)).write(to: url)
    }

    // MARK: - Start

    func testNewStoreCreatesItsRootFolderAndStartsLockedAndEmpty() throws {
        let (store, root) = try makeStore()

        XCTAssertTrue(exists(root))
        XCTAssertTrue(store.root.isFolder)
        XCTAssertEqual(store.root.name, "Smartlists")
        XCTAssertTrue(store.root.children.isEmpty)
        XCTAssertTrue(store.isLocked)
        XCTAssertNil(store.lastImportEvent)
        XCTAssertFalse(store.importedFolderExists)
    }

    func testStoreLoadsWhatIsAlreadyOnDisk() throws {
        let root = try makeTemporaryDirectory().appendingPathComponent("Smartlists", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try writeRuleSet(named: "Existing", to: root.appendingPathComponent("existing.json"))

        let store = SmartlistStore(rootURLOverride: root)

        XCTAssertEqual(names(store.root), ["Folder", "Existing"])
    }

    // MARK: - Create

    func testCreateRuleSetWritesAFileAndShowsItInTheTree() throws {
        let (store, _) = try makeStore()

        let node = try store.createRuleSet(named: "Fast")

        XCTAssertFalse(node.isFolder)
        XCTAssertEqual(node.name, "Fast")
        XCTAssertEqual(node.url.lastPathComponent, "Fast.json")
        XCTAssertTrue(exists(node.url))
        XCTAssertEqual(names(store.root), ["Fast"])

        let loaded = try store.loadRuleSet(from: node.url)
        XCTAssertEqual(loaded.name, "Fast")
        XCTAssertEqual(loaded.matchMode, .all)
        XCTAssertTrue(loaded.conditions.isEmpty)
    }

    func testCreateRuleSetInsideAFolder() throws {
        let (store, _) = try makeStore()
        let folder = try store.createFolder(named: "Milongas")

        let node = try store.createRuleSet(named: "Fast", in: folder)

        XCTAssertTrue(node.url.deletingLastPathComponent().lastPathComponent == "Milongas")
        XCTAssertEqual(names(try XCTUnwrap(child("Milongas", of: store.root))), ["Fast"])
        XCTAssertTrue(store.root.children.filter { !$0.isFolder }.isEmpty)
    }

    func testCreateFolderMakesADirectory() throws {
        let (store, _) = try makeStore()

        let folder = try store.createFolder(named: "Milongas")

        XCTAssertTrue(folder.isFolder)
        XCTAssertEqual(folder.name, "Milongas")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreatingTheSameFolderTwiceIsHarmless() throws {
        let (store, _) = try makeStore()

        try store.createFolder(named: "Milongas")
        XCTAssertNoThrow(try store.createFolder(named: "Milongas"))

        XCTAssertEqual(names(store.root), ["Milongas"])
    }

    // MARK: - Listing

    func testFoldersComeFirstThenRuleSetsEachAlphabetically() throws {
        let (store, _) = try makeStore()
        try store.createRuleSet(named: "b")
        try store.createRuleSet(named: "a")
        try store.createFolder(named: "z-folder")
        try store.createFolder(named: "m-folder")

        XCTAssertEqual(names(store.root), ["m-folder", "z-folder", "a", "b"])
    }

    func testOnlyFoldersAndJSONFilesAreListed() throws {
        let (store, root) = try makeStore()
        try Data("x".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try writeRuleSet(named: "Hidden", to: root.appendingPathComponent(".hidden.json"))
        try writeRuleSet(named: "Shown", to: root.appendingPathComponent("shown.json"))

        store.reload()

        XCTAssertEqual(names(store.root), ["Shown"])
    }

    func testBrokenJSONIsListedByFileNameWithoutARuleSet() throws {
        let (store, root) = try makeStore()
        try Data("{ not json".utf8).write(to: root.appendingPathComponent("broken.json"))

        store.reload()

        let node = try XCTUnwrap(child("broken", of: store.root))
        XCTAssertNil(node.ruleSet)
        XCTAssertFalse(node.isFolder)
    }

    func testNodeNameComesFromTheRuleSetNotFromTheFileName() throws {
        let (store, root) = try makeStore()
        try writeRuleSet(named: "Pretty Name", to: root.appendingPathComponent("file1.json"))

        store.reload()

        let node = try XCTUnwrap(child("Pretty Name", of: store.root))
        XCTAssertEqual(node.url.lastPathComponent, "file1.json")
        XCTAssertEqual(node.ruleSet?.name, "Pretty Name")
    }

    func testNestedFoldersAreLoadedRecursively() throws {
        let (store, _) = try makeStore()
        let outer = try store.createFolder(named: "Outer")
        let inner = try store.createFolder(named: "Inner", in: outer)
        try store.createRuleSet(named: "Deep", in: inner)

        let loadedOuter = try XCTUnwrap(child("Outer", of: store.root))
        let loadedInner = try XCTUnwrap(child("Inner", of: loadedOuter))
        XCTAssertEqual(names(loadedInner), ["Deep"])
    }

    // MARK: - Save

    func testSaveWritesTheRuleSetAndRenamesTheNodeButNotTheFile() throws {
        let (store, _) = try makeStore()
        let node = try store.createRuleSet(named: "A")
        var ruleSet = try XCTUnwrap(node.ruleSet)
        ruleSet.name = "B"
        ruleSet.matchMode = .any
        ruleSet.conditions = [
            SmartlistCondition(field: .year, op: .isBetween, value: "1930", secondValue: "1940"),
            SmartlistCondition(field: .artist, op: .contains, value: "Alpha", secondValue: nil)
        ]

        try store.save(ruleSet, to: node)

        XCTAssertEqual(node.name, "B")
        XCTAssertEqual(node.ruleSet, ruleSet)
        XCTAssertEqual(node.url.lastPathComponent, "A.json")
        XCTAssertEqual(try store.loadRuleSet(from: node.url), ruleSet)
    }

    func testSavedRuleSetSurvivesAReload() throws {
        let (store, _) = try makeStore()
        let node = try store.createRuleSet(named: "A")
        var ruleSet = try XCTUnwrap(node.ruleSet)
        ruleSet.name = "Renamed"
        try store.save(ruleSet, to: node)

        store.reload()

        let reloaded = try XCTUnwrap(child("Renamed", of: store.root))
        XCTAssertEqual(reloaded.ruleSet, ruleSet)
    }

    func testLoadingAnInvalidRuleSetFileThrows() throws {
        let (store, root) = try makeStore()
        let url = try writeText("{}", in: root, named: "empty.json")

        XCTAssertThrowsError(try store.loadRuleSet(from: url))
    }

    // MARK: - Find

    func testFindNodeFindsTheRootNestedFoldersAndRuleSets() throws {
        let (store, _) = try makeStore()
        let folder = try store.createFolder(named: "F")
        let leaf = try store.createRuleSet(named: "Leaf", in: folder)

        XCTAssertEqual(store.findNode(id: store.root.id)?.id, store.root.id)
        XCTAssertEqual(store.findNode(id: folder.id)?.id, folder.id)
        XCTAssertEqual(store.findNode(id: leaf.id)?.id, leaf.id)
        XCTAssertNil(store.findNode(id: "/nowhere/else.json"))
    }

    func testNodeIDIsTheFilePathSoItSurvivesAReload() throws {
        let (store, _) = try makeStore()
        let leaf = try store.createRuleSet(named: "Leaf")
        let before = leaf.id

        store.reload()

        XCTAssertNotNil(store.findNode(id: before))
    }

    // MARK: - Delete

    func testDeleteRemovesTheFileAndTheNode() throws {
        let (store, _) = try makeStore()
        let node = try store.createRuleSet(named: "Gone")

        try store.delete(node)

        XCTAssertFalse(exists(node.url))
        XCTAssertTrue(store.root.children.isEmpty)
    }

    func testDeleteRemovesAFolderWithItsContents() throws {
        let (store, _) = try makeStore()
        let folder = try store.createFolder(named: "F")
        let leaf = try store.createRuleSet(named: "Inside", in: folder)

        try store.delete(folder)

        XCTAssertFalse(exists(folder.url))
        XCTAssertFalse(exists(leaf.url))
        XCTAssertTrue(store.root.children.isEmpty)
    }

    // MARK: - Move

    func testMoveRuleSetIntoAFolder() throws {
        let (store, _) = try makeStore()
        let leaf = try store.createRuleSet(named: "A")
        let folder = try store.createFolder(named: "F")
        let oldURL = leaf.url

        try store.move(leaf, into: folder)

        XCTAssertFalse(exists(oldURL))
        XCTAssertNil(child("A", of: store.root))
        XCTAssertEqual(names(try XCTUnwrap(child("F", of: store.root))), ["A"])
    }

    func testMoveBackToTheRoot() throws {
        let (store, _) = try makeStore()
        let folder = try store.createFolder(named: "F")
        let leaf = try store.createRuleSet(named: "A", in: folder)

        try store.move(leaf, into: store.root)

        XCTAssertNotNil(child("A", of: store.root))
        XCTAssertTrue(try XCTUnwrap(child("F", of: store.root)).children.isEmpty)
    }

    func testMoveFolderWithItsContentsIntoAnotherFolder() throws {
        let (store, _) = try makeStore()
        let source = try store.createFolder(named: "Source")
        try store.createRuleSet(named: "Inside", in: source)
        let target = try store.createFolder(named: "Target")

        try store.move(source, into: target)

        let movedTarget = try XCTUnwrap(child("Target", of: store.root))
        let movedSource = try XCTUnwrap(child("Source", of: movedTarget))
        XCTAssertEqual(names(movedSource), ["Inside"])
        XCTAssertNil(child("Source", of: store.root))
    }

    func testMoveIntoANameCollisionIsRefusedAndNothingChanges() throws {
        let (store, _) = try makeStore()
        let first = try store.createFolder(named: "F1")
        let second = try store.createFolder(named: "F2")
        let leaf1 = try store.createRuleSet(named: "X", in: first)
        let leaf2 = try store.createRuleSet(named: "X", in: second)

        XCTAssertThrowsError(try store.move(leaf1, into: second)) { error in
            guard case SmartSetlistStoreError.destinationExists = error else {
                return XCTFail("unexpected error \(error)")
            }
        }

        XCTAssertTrue(exists(leaf1.url))
        XCTAssertTrue(exists(leaf2.url))
    }

    func testAFolderCannotBeMovedIntoItsOwnDescendant() throws {
        let (store, _) = try makeStore()
        let outer = try store.createFolder(named: "A")
        let inner = try store.createFolder(named: "B", in: outer)

        XCTAssertThrowsError(try store.move(outer, into: inner)) { error in
            guard case SmartSetlistStoreError.cannotMoveIntoSelfOrDescendant = error else {
                return XCTFail("unexpected error \(error)")
            }
        }

        XCTAssertTrue(exists(inner.url))
    }

    func testAFolderMovedIntoItselfIsLeftAlone() throws {
        let (store, _) = try makeStore()
        let folder = try store.createFolder(named: "A")

        XCTAssertNoThrow(try store.move(folder, into: folder))

        XCTAssertTrue(exists(folder.url))
    }

    func testAFolderMayMoveIntoASiblingWhoseNameOnlyStartsTheSame() throws {
        let (store, _) = try makeStore()
        let short = try store.createFolder(named: "A")
        let long = try store.createFolder(named: "AB")

        XCTAssertNoThrow(try store.move(short, into: long))

        let movedLong = try XCTUnwrap(child("AB", of: store.root))
        XCTAssertNotNil(child("A", of: movedLong))
    }

    func testMovingIntoARuleSetFileDoesNothing() throws {
        let (store, _) = try makeStore()
        let leaf = try store.createRuleSet(named: "A")
        let other = try store.createRuleSet(named: "B")

        XCTAssertNoThrow(try store.move(leaf, into: other))

        XCTAssertTrue(exists(leaf.url))
        XCTAssertEqual(names(store.root), ["A", "B"])
    }

    // MARK: - Export / Import

    func testExportAllCopiesTheWholeTree() throws {
        let (store, _) = try makeStore()
        let folder = try store.createFolder(named: "F")
        try store.createRuleSet(named: "Top")
        try store.createRuleSet(named: "Inside", in: folder)
        let destination = try makeTemporaryDirectory().appendingPathComponent("export")

        try store.exportAll(to: destination)

        XCTAssertTrue(exists(destination.appendingPathComponent("Top.json")))
        XCTAssertTrue(exists(destination.appendingPathComponent("F/Inside.json")))
    }

    func testExportAllIntoAnExistingFolderFails() throws {
        let (store, _) = try makeStore()
        let destination = try makeTemporaryDirectory()

        XCTAssertThrowsError(try store.exportAll(to: destination))
    }

    func testImportAllPutsTheContentsOfTheSourceIntoImported() throws {
        let (store, _) = try makeStore()
        let source = try makeTemporaryDirectory().appendingPathComponent("Whatever", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try writeRuleSet(named: "Alpha", to: source.appendingPathComponent("a.json"))
        try writeRuleSet(named: "Beta", to: source.appendingPathComponent("sub/b.json"))
        XCTAssertFalse(store.importedFolderExists)

        try store.importAll(from: source)

        XCTAssertTrue(store.importedFolderExists)
        XCTAssertEqual(store.findNode(id: store.importedFolderID)?.name, "Imported")
        let imported = try XCTUnwrap(child("Imported", of: store.root))
        XCTAssertEqual(names(imported), ["sub", "Alpha"], "the source folder's own name is not added as a level")
        XCTAssertEqual(names(try XCTUnwrap(child("sub", of: imported))), ["Beta"])
        XCTAssertNotNil(store.lastImportEvent)
    }

    func testImportAllReplacesAPreviousImport() throws {
        let (store, _) = try makeStore()
        let first = try makeTemporaryDirectory()
        try writeRuleSet(named: "Old", to: first.appendingPathComponent("old.json"))
        let second = try makeTemporaryDirectory()
        try writeRuleSet(named: "New", to: second.appendingPathComponent("new.json"))

        try store.importAll(from: first)
        let firstEvent = store.lastImportEvent
        try store.importAll(from: second)

        let imported = try XCTUnwrap(child("Imported", of: store.root))
        XCTAssertEqual(names(imported), ["New"])
        XCTAssertNotEqual(store.lastImportEvent, firstEvent)
    }

    func testImportAllLeavesTheOtherSmartlistsAlone() throws {
        let (store, _) = try makeStore()
        try store.createRuleSet(named: "Mine")
        let source = try makeTemporaryDirectory()
        try writeRuleSet(named: "Theirs", to: source.appendingPathComponent("theirs.json"))

        try store.importAll(from: source)

        XCTAssertEqual(names(store.root), ["Imported", "Mine"])
    }

    // MARK: - Library switch

    func testStoreFollowsTheActiveLibraryAfterReload() throws {
        try withTemporaryAppRoot { _ in
            let store = SmartlistStore()
            XCTAssertTrue(samePath(store.root.url, AppPaths.smartlistFolder))
            try store.createRuleSet(named: "InDefault")

            AppPaths.currentLibraryName = "Other"
            store.reload()

            XCTAssertTrue(samePath(store.root.url, AppPaths.smartlistFolder))
            XCTAssertTrue(store.root.children.isEmpty, "the other library has its own Smartlists")
            XCTAssertTrue(exists(AppPaths.smartlistFolder))

            AppPaths.currentLibraryName = AppPaths.defaultLibraryName
            store.reload()

            XCTAssertEqual(names(store.root), ["InDefault"])
        }
    }

    // MARK: - Errors

    func testErrorMessages() {
        XCTAssertEqual(
            SmartSetlistStoreError.destinationExists.errorDescription,
            "A smartlist or folder with that name already exists there."
        )
        XCTAssertEqual(
            SmartSetlistStoreError.cannotMoveIntoSelfOrDescendant.errorDescription,
            "Can't move a folder into itself or one of its own subfolders."
        )
    }
}
