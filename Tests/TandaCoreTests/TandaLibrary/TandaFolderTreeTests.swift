import XCTest
import Foundation

/// The folder tree of the Tanda Library, built either from the loaded Tandas'
/// `sourceFolder` values (`buildTree`) or by scanning `Tandas/` (`loadRoot`).
@MainActor
final class TandaFolderTreeTests: XCTestCase {

    private func ids(_ nodes: [TandaFolderNode]) -> [String] {
        nodes.map(\.id)
    }

    // MARK: - buildTree

    func testNoFoldersGiveAnEmptyTree() {
        XCTAssertTrue(TandaFolderTree.buildTree(fromSourceFolders: []).isEmpty)
    }

    func testTandasInTheRootFolderAddNoNode() {
        XCTAssertTrue(TandaFolderTree.buildTree(fromSourceFolders: ["", ""]).isEmpty)
    }

    func testOneFolderGivesOneNodeWithoutChildren() {
        let tree = TandaFolderTree.buildTree(fromSourceFolders: ["Biagi"])

        XCTAssertEqual(tree, [TandaFolderNode(id: "Biagi", name: "Biagi", children: [])])
    }

    func testNestedFolderBecomesAChildWithTheFullRelativePathAsID() {
        let tree = TandaFolderTree.buildTree(fromSourceFolders: ["Biagi/Live"])

        XCTAssertEqual(ids(tree), ["Biagi"])
        XCTAssertEqual(tree.first?.children.map(\.id), ["Biagi/Live"])
        XCTAssertEqual(tree.first?.children.first?.name, "Live")
    }

    func testMissingParentsAreCreated() {
        let tree = TandaFolderTree.buildTree(fromSourceFolders: ["A/B/C"])

        XCTAssertEqual(tree.map(\.id), ["A"])
        XCTAssertEqual(tree[0].children.map(\.id), ["A/B"])
        XCTAssertEqual(tree[0].children[0].children.map(\.id), ["A/B/C"])
        XCTAssertTrue(tree[0].children[0].children[0].children.isEmpty)
    }

    func testRepeatedFoldersAreMerged() {
        let tree = TandaFolderTree.buildTree(
            fromSourceFolders: ["Biagi", "Biagi", "Biagi/Live", "Biagi/Live", "Biagi/Studio"]
        )

        XCTAssertEqual(ids(tree), ["Biagi"])
        XCTAssertEqual(tree[0].children.map(\.name), ["Live", "Studio"])
    }

    func testSiblingsAreSortedNaturallyAndIgnoringCase() {
        let tree = TandaFolderTree.buildTree(fromSourceFolders: ["Calo", "biagi", "Di Sarli"])

        XCTAssertEqual(tree.map(\.name), ["biagi", "Calo", "Di Sarli"])
    }

    func testNumbersInNamesAreSortedByValue() {
        let tree = TandaFolderTree.buildTree(fromSourceFolders: ["Set 10", "Set 2", "Set 1"])

        XCTAssertEqual(tree.map(\.name), ["Set 1", "Set 2", "Set 10"])
    }

    func testSubfoldersAreSortedToo() {
        let tree = TandaFolderTree.buildTree(fromSourceFolders: ["A/z", "A/b", "A/M"])

        XCTAssertEqual(tree[0].children.map(\.name), ["b", "M", "z"])
    }

    func testSeveralTopLevelFoldersWithTheirOwnChildren() {
        let tree = TandaFolderTree.buildTree(fromSourceFolders: ["A/x", "B/y", "B/z"])

        XCTAssertEqual(ids(tree), ["A", "B"])
        XCTAssertEqual(tree[0].children.map(\.id), ["A/x"])
        XCTAssertEqual(tree[1].children.map(\.id), ["B/y", "B/z"])
    }

    // MARK: - loadRoot

    func testLoadRootListsOnlyFoldersRecursively() throws {
        try withTemporaryAppRoot { _ in
            let tandas = AppPaths.tandasFolder
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: tandas.appendingPathComponent("Biagi/Live"), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: tandas.appendingPathComponent("Calo"), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: tandas.appendingPathComponent("loose.json"))
            try Data("{}".utf8).write(to: tandas.appendingPathComponent("Biagi/Tanda 1.json"))

            let tree = TandaFolderTree.loadRoot()

            XCTAssertEqual(ids(tree), ["Biagi", "Calo"])
            XCTAssertEqual(tree[0].children.map(\.id), ["Biagi/Live"])
            XCTAssertTrue(tree[1].children.isEmpty)
        }
    }

    func testLoadRootShowsEmptyFoldersToo() throws {
        try withTemporaryAppRoot { _ in
            try FileManager.default.createDirectory(
                at: AppPaths.tandasFolder.appendingPathComponent("Empty"),
                withIntermediateDirectories: true
            )

            XCTAssertEqual(ids(TandaFolderTree.loadRoot()), ["Empty"])
        }
    }

    func testLoadRootWithoutATandasFolderIsEmpty() throws {
        try withTemporaryAppRoot { _ in
            XCTAssertTrue(TandaFolderTree.loadRoot().isEmpty)
        }
    }

    func testLoadRootSortsNaturally() throws {
        try withTemporaryAppRoot { _ in
            for name in ["Set 10", "Set 2", "set 1"] {
                try FileManager.default.createDirectory(
                    at: AppPaths.tandasFolder.appendingPathComponent(name),
                    withIntermediateDirectories: true
                )
            }

            XCTAssertEqual(TandaFolderTree.loadRoot().map(\.name), ["set 1", "Set 2", "Set 10"])
        }
    }

    // MARK: - Selection

    func testFolderSelectionEquality() {
        XCTAssertEqual(TandaFolderSelection.showAll, .showAll)
        XCTAssertEqual(TandaFolderSelection.folder("A"), .folder("A"))
        XCTAssertNotEqual(TandaFolderSelection.folder("A"), .folder("B"))
        XCTAssertNotEqual(TandaFolderSelection.folder("A"), .showAll)
    }
}
