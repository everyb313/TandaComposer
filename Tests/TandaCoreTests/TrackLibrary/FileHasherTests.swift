import XCTest
import Foundation

/// Reference values were computed independently with Python's hashlib.
@MainActor
final class FileHasherTests: XCTestCase {

    private func hash(of data: Data) async throws -> String {
        let dir = try makeTemporaryDirectory()
        let file = try writeData(data, in: dir, named: "file.bin")
        return try await FileHasher.sha256(fileURL: file)
    }

    func testEmptyFile() async throws {
        let result = try await hash(of: Data())

        XCTAssertEqual(result, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testShortFile() async throws {
        let result = try await hash(of: Data("abc".utf8))

        XCTAssertEqual(result, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testResultIsLowercaseHexOf64Characters() async throws {
        let result = try await hash(of: Data("abc".utf8))

        XCTAssertEqual(result.count, 64)
        XCTAssertEqual(result, result.lowercased())
    }

    func testFileExactlyOneChunkLong() async throws {
        let result = try await hash(of: Data(repeating: 0x61, count: 1_048_576))

        XCTAssertEqual(result, "9bc1b2a288b26af7257a36277ae3816a7d4f16e89c1e7e77d0a5c48bad62b360")
    }

    func testFileSpanningSeveralChunks() async throws {
        let result = try await hash(of: Data(repeating: 0x61, count: 2 * 1_048_576 + 1))

        XCTAssertEqual(result, "16a429a1e5162fcf59e3079724763e9afafcef1e2c7f862571e9267b3d959113")
    }

    func testIdenticalContentGivesIdenticalHashRegardlessOfName() async throws {
        let dir = try makeTemporaryDirectory()
        let first = try writeData(Data("same".utf8), in: dir, named: "a.flac")
        let second = try writeData(Data("same".utf8), in: dir, named: "b.mp3")

        let hashA = try await FileHasher.sha256(fileURL: first)
        let hashB = try await FileHasher.sha256(fileURL: second)

        XCTAssertEqual(hashA, hashB)
    }

    func testOneChangedByteChangesTheHash() async throws {
        let first = try await hash(of: Data("abc".utf8))
        let second = try await hash(of: Data("abd".utf8))

        XCTAssertNotEqual(first, second)
    }

    func testMissingFileThrows() async throws {
        let dir = try makeTemporaryDirectory()
        let missing = dir.appendingPathComponent("nope.bin")

        do {
            _ = try await FileHasher.sha256(fileURL: missing)
            XCTFail("expected an error for a missing file")
        } catch {
            // expected
        }
    }
}
