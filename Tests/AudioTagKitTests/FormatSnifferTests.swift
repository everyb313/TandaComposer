import XCTest
import Foundation

final class FormatSnifferTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TandaComposerFormatTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testDetectsFLACFromMagicBytesRegardlessOfExtension() throws {
        try assertFormat(.flac, bytes: Array("fLaC".utf8) + [0, 0, 0, 0], filename: "audio.bin")
    }

    func testDetectsID3TaggedMP3() throws {
        try assertFormat(.mp3, bytes: Array("ID3".utf8) + [4, 0, 0, 0, 0, 0, 0], filename: "audio.data")
    }

    func testDetectsMP3FrameWithoutID3Tag() throws {
        try assertFormat(.mp3, bytes: [0xFF, 0xFB, 0x90, 0x64, 0, 0, 0, 0], filename: "audio.unknown")
    }

    func testDetectsMP4FamilyFromFtypBox() throws {
        try assertFormat(.mp4Family, bytes: [0, 0, 0, 0] + Array("ftypM4A ".utf8), filename: "audio.mp3")
    }

    func testDetectsAIFFAndAIFC() throws {
        try assertFormat(.aiff, bytes: Array("FORM".utf8) + [0, 0, 0, 0] + Array("AIFF".utf8), filename: "audio.bin")
        try assertFormat(.aiff, bytes: Array("FORM".utf8) + [0, 0, 0, 0] + Array("AIFC".utf8), filename: "audio.bin")
    }

    func testUnknownHeaderRemainsUnknown() throws {
        try assertFormat(.unknown, bytes: Array("text data".utf8), filename: "audio.flac")
    }

    private func assertFormat(
        _ expected: AudioFormat,
        bytes: [UInt8],
        filename: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = temporaryDirectory.appendingPathComponent(filename)
        try Data(bytes).write(to: url)
        let actual = FormatSniffer.detect(url: url)

        switch (expected, actual) {
        case (.flac, .flac), (.mp3, .mp3), (.mp4Family, .mp4Family),
             (.aiff, .aiff), (.unknown, .unknown):
            break
        default:
            XCTFail("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }
}
