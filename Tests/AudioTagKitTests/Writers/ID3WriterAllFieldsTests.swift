import XCTest
import Foundation

/// `ID3Writer.write` with every field at once, and the handling of old date
/// frames when a year is written.
final class ID3WriterAllFieldsTests: XCTestCase {
    private var temporaryDirectory: URL!

    private let audio = Data([0xFF, 0xFB, 0x90, 0x64, 0x10, 0x20, 0x30])

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ID3WriterAllFieldsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    private func makeFile(existingFrames: [Data] = []) throws -> URL {
        var data = Data()

        if !existingFrames.isEmpty {
            let body = existingFrames.reduce(Data(), +)
            data.append(ID3FrameCodec.header(bodySize: body.count))
            data.append(body)
        }

        data.append(audio)

        let url = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp3")
        try data.write(to: url)
        return url
    }

    private func frames(in url: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]

        for frame in ID3FrameCodec.parseTag(try Data(contentsOf: url)) {
            result[frame.id] = frame.content
        }

        return result
    }

    func testEveryFieldBecomesItsOwnFrame() async throws {
        let url = try makeFile()

        try await ID3Writer.write(
            url: url,
            changes: TagChanges(
                title: "Poema",
                artist: "Alpha Trio",
                albumArtist: "Singer X",
                album: "Album One",
                genre: "Tango",
                track: "3/12",
                year: "1940",
                comment: "Remark"
            )
        )

        let result = try frames(in: url)
        func text(_ id: String) -> String? { result[id].map { ID3FrameCodec.decodeTextValue($0) } }

        XCTAssertEqual(text("TIT2"), "Poema")
        XCTAssertEqual(text("TPE1"), "Alpha Trio")
        XCTAssertEqual(text("TPE2"), "Singer X")
        XCTAssertEqual(text("TALB"), "Album One")
        XCTAssertEqual(text("TCON"), "Tango")
        XCTAssertEqual(text("TRCK"), "3/12")
        XCTAssertEqual(text("TDRC"), "1940")
        XCTAssertEqual(result["COMM"].map { ID3FrameCodec.decodeCommentValue($0) }, "Remark")
        XCTAssertEqual(try Data(contentsOf: url).suffix(audio.count), audio)
    }

    func testFieldsThatAreNotChangedKeepTheirFrames() async throws {
        let url = try makeFile(existingFrames: [
            ID3FrameCodec.textFrame("TIT2", "Old Title"),
            ID3FrameCodec.textFrame("TPE1", "Old Artist")
        ])

        try await ID3Writer.write(url: url, changes: TagChanges(artist: "New Artist"))

        let result = try frames(in: url)
        XCTAssertEqual(result["TIT2"].map { ID3FrameCodec.decodeTextValue($0) }, "Old Title")
        XCTAssertEqual(result["TPE1"].map { ID3FrameCodec.decodeTextValue($0) }, "New Artist")
    }

    func testWritingAYearReplacesALegacyYearFrame() async throws {
        let url = try makeFile(existingFrames: [
            ID3FrameCodec.textFrame("TYER", "1999"),
            ID3FrameCodec.textFrame("TIT2", "Old Title")
        ])

        try await ID3Writer.write(url: url, changes: TagChanges(year: "2001"))

        let result = try frames(in: url)
        XCTAssertEqual(result["TDRC"].map { ID3FrameCodec.decodeTextValue($0) }, "2001")
        XCTAssertNil(result["TYER"], "the old frame would contradict the new one")
        XCTAssertEqual(result["TIT2"].map { ID3FrameCodec.decodeTextValue($0) }, "Old Title")
    }

    func testOtherFramesSuchAsPicturesSurviveAWrite() async throws {
        let picture = ID3FrameCodec.frame(id: "APIC", content: Data([0x00]) + Data("image/png".utf8) + Data([0x00, 0x03, 0x00, 1, 2, 3]))
        let url = try makeFile(existingFrames: [picture, ID3FrameCodec.textFrame("TIT2", "Old Title")])

        try await ID3Writer.write(url: url, changes: TagChanges(title: "New Title"))

        let result = try frames(in: url)
        XCTAssertNotNil(result["APIC"])
        XCTAssertEqual(result["TIT2"].map { ID3FrameCodec.decodeTextValue($0) }, "New Title")
    }
}
