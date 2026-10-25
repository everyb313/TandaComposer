import XCTest
import Foundation

/// `FLACReader` reports artwork details (type, MIME, size) from the PICTURE
/// block. Damaged blocks give as much as could be read, never a crash.
final class FLACReaderPictureInfoTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FLACReaderPictureInfoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func be32(_ value: Int) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ])
    }

    /// The pieces of a complete PICTURE block, in order.
    private func pictureParts(
        type: Int = 3,
        mime: String = "image/png",
        description: String = "cover",
        width: Int = 100,
        height: Int = 50
    ) -> [Data] {
        [
            be32(type),
            be32(mime.utf8.count), Data(mime.utf8),
            be32(description.utf8.count), Data(description.utf8),
            be32(width), be32(height),
            be32(24), be32(0),
            be32(4), Data([1, 2, 3, 4])
        ]
    }

    private func readInfo(_ block: Data) async throws -> [String: Any] {
        let file = FLACBlocks.serialize(
            blocks: [
                FLACBlock(type: FLACBlocks.streamInfo, data: Data(repeating: 0, count: 34)),
                FLACBlock(type: FLACBlocks.picture, data: block)
            ],
            audioData: Data([0xFF, 0xF8])
        )
        let url = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).flac")
        try file.write(to: url)

        let metadata = try await FLACReader.read(url: url)

        XCTAssertEqual(metadata["hasArtwork"] as? Bool, true)
        return try XCTUnwrap(metadata["artworkInfo"] as? [String: Any])
    }

    private func joined(_ parts: ArraySlice<Data>) -> Data {
        parts.reduce(Data(), +)
    }

    // MARK: - Tests

    func testACompletePictureBlockGivesTypeMimeAndSize() async throws {
        let info = try await readInfo(joined(pictureParts()[...]))

        XCTAssertEqual(info["pictureType"] as? Int, 3)
        XCTAssertEqual(info["mime"] as? String, "image/png")
        XCTAssertEqual(info["width"] as? Int, 100)
        XCTAssertEqual(info["height"] as? Int, 50)
    }

    func testAnotherPictureTypeAndMimeAreReported() async throws {
        let info = try await readInfo(joined(pictureParts(type: 0, mime: "image/jpeg", width: 600, height: 600)[...]))

        XCTAssertEqual(info["pictureType"] as? Int, 0)
        XCTAssertEqual(info["mime"] as? String, "image/jpeg")
        XCTAssertEqual(info["width"] as? Int, 600)
    }

    func testABlockCutOffAfterTheDescriptionHasNoSize() async throws {
        let info = try await readInfo(joined(pictureParts()[0..<5]))

        XCTAssertEqual(info["pictureType"] as? Int, 3)
        XCTAssertEqual(info["mime"] as? String, "image/png")
        XCTAssertNil(info["width"])
        XCTAssertNil(info["height"])
    }

    func testABlockWithAWidthButNoHeightHasNoSize() async throws {
        let info = try await readInfo(joined(pictureParts()[0..<6]))

        XCTAssertEqual(info["mime"] as? String, "image/png")
        XCTAssertNil(info["width"])
        XCTAssertNil(info["height"])
    }

    func testABlockWhoseDescriptionLengthIsUnreadableKeepsTypeAndMime() async throws {
        let parts = pictureParts()
        let block = joined(parts[0..<3]) + Data([0x00, 0x00])

        let info = try await readInfo(block)

        XCTAssertEqual(info["pictureType"] as? Int, 3)
        XCTAssertEqual(info["mime"] as? String, "image/png")
        XCTAssertNil(info["width"])
    }

    func testADescriptionLengthBeyondTheBlockKeepsTypeAndMime() async throws {
        let block = joined(pictureParts()[0..<3]) + be32(5000)

        let info = try await readInfo(block)

        XCTAssertEqual(info["mime"] as? String, "image/png")
        XCTAssertNil(info["width"])
    }

    func testAMimeLengthBeyondTheBlockGivesNoDetails() async throws {
        let block = be32(3) + be32(5000) + Data("image/png".utf8)

        let info = try await readInfo(block)

        XCTAssertTrue(info.isEmpty)
    }

    func testABlockCutOffInsideTheFirstFieldGivesNoDetails() async throws {
        let info = try await readInfo(Data([0x00, 0x00, 0x03]))

        XCTAssertTrue(info.isEmpty)
    }

    func testAStreamInfoBlockThatIsTooShortGivesNoStreamDetails() async throws {
        let file = FLACBlocks.serialize(
            blocks: [FLACBlock(type: FLACBlocks.streamInfo, data: Data(repeating: 0, count: 10))],
            audioData: Data([0xFF, 0xF8])
        )
        let url = temporaryDirectory.appendingPathComponent("short-streaminfo.flac")
        try file.write(to: url)

        let metadata = try await FLACReader.read(url: url)

        let streamInfo = try XCTUnwrap(metadata["streamInfo"] as? [String: Any])
        XCTAssertTrue(streamInfo.isEmpty)
        XCTAssertNil(metadata["durationSeconds"])
        XCTAssertEqual(metadata["format"] as? String, "FLAC")
    }
}
