import XCTest
import Foundation

/// Reading must survive AIFF files whose FORM size is wrong or that carry
/// bytes after the FORM; writing must still refuse them.
///
/// NEEDS the `lenient:` parameter and the reader/extractor changes
/// (see README_TESTS.md).
final class AIFFLenientReadingTests: XCTestCase {
    private var temporaryDirectory: URL!

    private let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIFFLenientReadingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// 2 channels, 44100 sample frames, 16 bit, 44100 Hz: exactly one second.
    private var commChunk: AIFFChunk {
        var data = Data()
        data.append(contentsOf: [0x00, 0x02])
        data.append(contentsOf: [0x00, 0x00, 0xAC, 0x44])
        data.append(contentsOf: [0x00, 0x10])
        data.append(contentsOf: [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0])
        return AIFFChunk(id: "COMM", data: data)
    }

    private func id3Chunk(_ frames: [Data]) -> AIFFChunk {
        let body = frames.reduce(Data(), +)
        var tag = ID3FrameCodec.header(bodySize: body.count)
        tag.append(body)
        return AIFFChunk(id: "ID3 ", data: tag)
    }

    private func apicFrame() -> Data {
        var content = Data([0x00])
        content.append(contentsOf: Array("image/png".utf8))
        content.append(contentsOf: [0x00, 0x03])
        content.append(contentsOf: Array("cover".utf8))
        content.append(0x00)
        content.append(png)
        return ID3FrameCodec.frame(id: "APIC", content: content)
    }

    private func damagedFile(
        name: String = "damaged.aiff",
        formSize: Int? = nil,
        trailing: Data = Data()
    ) throws -> (url: URL, bytes: Data) {
        let chunks = [
            commChunk,
            id3Chunk([ID3FrameCodec.textFrame("TIT2", "Lenient title"), apicFrame()]),
            AIFFChunk(id: "SSND", data: Data(repeating: 0, count: 16))
        ]

        var bytes = AIFFChunks.serialize(formType: "AIFF", chunks: chunks)

        if let formSize {
            let value = UInt32(truncatingIfNeeded: formSize)
            bytes.replaceSubrange(4..<8, with: [
                UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
            ])
        }

        bytes.append(trailing)

        let url = temporaryDirectory.appendingPathComponent(name)
        try bytes.write(to: url)

        return (url, bytes)
    }

    // MARK: - Reading

    func testTagsAndStreamInfoAreReadDespiteAWrongFormSize() async throws {
        let (url, _) = try damagedFile(formSize: 0x00FF_FFFF)

        let metadata = try await AIFFReader.read(url: url)

        let common = try XCTUnwrap(metadata["common"] as? [String: Any])
        let streamInfo = try XCTUnwrap(metadata["streamInfo"] as? [String: Any])
        XCTAssertEqual(common["title"] as? String, "Lenient title")
        XCTAssertEqual(streamInfo["sampleRate"] as? Int, 44_100)
        XCTAssertEqual(streamInfo["channels"] as? Int, 2)
        XCTAssertEqual(metadata["durationSeconds"] as? Double, 1.0)
        XCTAssertEqual(metadata["hasArtwork"] as? Bool, true)
    }

    func testTagsAreReadWhenBytesFollowTheForm() async throws {
        let (url, _) = try damagedFile(trailing: Data(repeating: 0x55, count: 33))

        let metadata = try await AIFFReader.read(url: url)

        let common = try XCTUnwrap(metadata["common"] as? [String: Any])
        XCTAssertEqual(common["title"] as? String, "Lenient title")
    }

    func testArtworkIsExtractedDespiteAWrongFormSize() async throws {
        let (url, _) = try damagedFile(formSize: 0x00FF_FFFF)

        let artwork = try await ArtworkExtractor.extract(from: url)

        XCTAssertEqual(try XCTUnwrap(artwork).data, png)
    }

    // MARK: - Writing stays strict

    func testWritingRefusesAWrongFormSizeAndLeavesTheFileUntouched() async throws {
        let (url, bytes) = try damagedFile(formSize: 0x00FF_FFFF)

        do {
            try await AIFFWriter.write(url: url, changes: TagChanges(title: "Must not be written"))
            XCTFail("Expected the damaged AIFF to be rejected.")
        } catch {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testWritingRefusesBytesAfterTheFormAndLeavesTheFileUntouched() async throws {
        let (url, bytes) = try damagedFile(trailing: Data(repeating: 0x55, count: 33))

        do {
            try await AIFFWriter.write(url: url, changes: TagChanges(title: "Must not be written"))
            XCTFail("Expected the AIFF with trailing bytes to be rejected.")
        } catch {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testStrippingRefusesADamagedFileToo() async throws {
        let (url, bytes) = try damagedFile(formSize: 0x00FF_FFFF)

        do {
            try await AIFFWriter.strip(url: url)
            XCTFail("Expected the damaged AIFF to be rejected.")
        } catch {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}
