import XCTest
import Foundation

/// `AIFFReader.canHandle`: by file extension, or by the file's own header
/// when the extension says nothing.
final class AIFFReaderCanHandleTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIFFReaderCanHandleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    private func write(_ data: Data, as name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private var aiffBytes: Data {
        AIFFChunks.serialize(formType: "AIFF", chunks: [AIFFChunk(id: "SSND", data: Data(repeating: 0, count: 8))])
    }

    func testTheExtensionDecides() throws {
        for name in ["a.aiff", "a.aif", "a.aifc", "A.AIFF", "a.AiF"] {
            let url = try write(Data([0x00, 0x01]), as: name)

            XCTAssertTrue(AIFFReader.canHandle(url: url), name)
        }
    }

    func testAnAIFFFileWithAnotherExtensionIsRecognizedByItsHeader() throws {
        let url = try write(aiffBytes, as: "sound.dat")

        XCTAssertTrue(AIFFReader.canHandle(url: url))
    }

    func testOtherContentWithAnotherExtensionIsNotClaimed() throws {
        let flac = try write(Data("fLaC".utf8) + Data(repeating: 0, count: 8), as: "a.dat")
        let text = try write(Data("hello world".utf8), as: "b.txt")

        XCTAssertFalse(AIFFReader.canHandle(url: flac))
        XCTAssertFalse(AIFFReader.canHandle(url: text))
    }

    func testAMissingFileWithAnotherExtensionIsNotClaimed() {
        let url = temporaryDirectory.appendingPathComponent("missing.dat")

        XCTAssertFalse(AIFFReader.canHandle(url: url))
    }
}
