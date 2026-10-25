import XCTest
import Foundation

/// `TagWriterKit.write` / `strip` end to end for the three formats we write
/// ourselves: the right writer is chosen, the first `_original` backup is
/// made, and the result reads back.
final class TagWriterKitPublicAPITests: XCTestCase {
    private var temporaryDirectory: URL!

    private let mp3Audio = Data([0xFF, 0xFB, 0x90, 0x64, 0x10, 0x20, 0x30, 0x40])
    private let flacAudio = Data([0xFF, 0xF8, 0x69, 0x00, 0x01])

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TagWriterKitPublicAPITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func makeFLAC(name: String = "song.flac", comments: [String: String]) throws -> (url: URL, bytes: Data) {
        let bytes = FLACBlocks.serialize(
            blocks: [
                FLACBlock(type: FLACBlocks.streamInfo, data: Data(repeating: 0, count: 34)),
                FLACBlock(type: FLACBlocks.vorbisComment, data: VorbisCommentCodec.encode(comments))
            ],
            audioData: flacAudio
        )
        let url = temporaryDirectory.appendingPathComponent(name)
        try bytes.write(to: url)
        return (url, bytes)
    }

    private func makeAIFF(name: String = "song.aiff") throws -> (url: URL, bytes: Data) {
        var comm = Data([0x00, 0x02, 0x00, 0x00, 0xAC, 0x44, 0x00, 0x10])
        comm.append(contentsOf: [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0])
        let bytes = AIFFChunks.serialize(
            formType: "AIFF",
            chunks: [
                AIFFChunk(id: "COMM", data: comm),
                AIFFChunk(id: "SSND", data: Data(repeating: 0, count: 12))
            ]
        )
        let url = temporaryDirectory.appendingPathComponent(name)
        try bytes.write(to: url)
        return (url, bytes)
    }

    private func makeMP3(name: String = "song.mp3") throws -> (url: URL, bytes: Data) {
        let url = temporaryDirectory.appendingPathComponent(name)
        try mp3Audio.write(to: url)
        return (url, mp3Audio)
    }

    private func backupURL(of url: URL) -> URL {
        URL(fileURLWithPath: url.path + "_original")
    }

    // MARK: - FLAC

    func testWriteToFLACChangesTheTagKeepsTheOthersAndBacksUpTheOriginal() async throws {
        let (url, original) = try makeFLAC(comments: ["ARTIST": "Old Artist", "TITLE": "Old Title"])

        try await TagWriterKit.write(url: url, changes: TagChanges(title: "New Title"))

        let metadata = try await FLACReader.read(url: url)
        let comments = try XCTUnwrap(metadata["vorbisComments"] as? [String: String])
        XCTAssertEqual(comments["TITLE"], "New Title")
        XCTAssertEqual(comments["ARTIST"], "Old Artist")
        XCTAssertEqual(try Data(contentsOf: backupURL(of: url)), original)
    }

    func testASecondWriteKeepsTheFirstBackup() async throws {
        let (url, original) = try makeFLAC(comments: ["TITLE": "Old Title"])

        try await TagWriterKit.write(url: url, changes: TagChanges(title: "First"))
        try await TagWriterKit.write(url: url, changes: TagChanges(title: "Second"))

        let metadata = try await FLACReader.read(url: url)
        XCTAssertEqual((metadata["vorbisComments"] as? [String: String])?["TITLE"], "Second")
        XCTAssertEqual(try Data(contentsOf: backupURL(of: url)), original)
    }

    func testStripOfAFLACRemovesItsTagsAndBacksUpTheTaggedOriginal() async throws {
        let (url, original) = try makeFLAC(comments: ["TITLE": "Old Title", "ARTIST": "Old Artist"])

        try await TagWriterKit.strip(url: url)

        let metadata = try await FLACReader.read(url: url)
        XCTAssertNil(metadata["vorbisComments"])
        XCTAssertEqual(try Data(contentsOf: backupURL(of: url)), original)
    }

    // MARK: - AIFF

    func testWriteToAIFFAddsAnID3TagAndBacksUpTheOriginal() async throws {
        let (url, original) = try makeAIFF()

        try await TagWriterKit.write(url: url, changes: TagChanges(title: "New Title", artist: "New Artist"))

        let metadata = try await AIFFReader.read(url: url)
        let common = try XCTUnwrap(metadata["common"] as? [String: Any])
        XCTAssertEqual(common["title"] as? String, "New Title")
        XCTAssertEqual(common["artist"] as? String, "New Artist")
        XCTAssertNotNil(metadata["streamInfo"], "the audio description survives")
        XCTAssertEqual(try Data(contentsOf: backupURL(of: url)), original)
    }

    func testStripOfAnAIFFRemovesItsTagButKeepsTheAudioDescription() async throws {
        let (url, _) = try makeAIFF()
        try await AIFFWriter.write(url: url, changes: TagChanges(title: "Old Title"))
        let tagged = try Data(contentsOf: url)

        try await TagWriterKit.strip(url: url)

        let metadata = try await AIFFReader.read(url: url)
        XCTAssertNil(metadata["common"])
        XCTAssertNotNil(metadata["streamInfo"])
        XCTAssertEqual(try Data(contentsOf: backupURL(of: url)), tagged)
    }

    // MARK: - MP3

    func testWriteToAnMP3PrependsATagAndKeepsTheAudioBytes() async throws {
        let (url, original) = try makeMP3()

        try await TagWriterKit.write(
            url: url,
            changes: TagChanges(title: "New Title", artist: "New Artist")
        )

        let data = try Data(contentsOf: url)
        let frames = ID3FrameCodec.parseTag(data)
        let title = frames.first { $0.id == "TIT2" }
        let artist = frames.first { $0.id == "TPE1" }
        XCTAssertEqual(title.map { ID3FrameCodec.decodeTextValue($0.content) }, "New Title")
        XCTAssertEqual(artist.map { ID3FrameCodec.decodeTextValue($0.content) }, "New Artist")
        XCTAssertEqual(data.suffix(mp3Audio.count), mp3Audio)
        XCTAssertEqual(try Data(contentsOf: backupURL(of: url)), original)
    }

    func testStripOfAnMP3LeavesOnlyTheAudio() async throws {
        let (url, _) = try makeMP3()
        try await ID3Writer.write(url: url, changes: TagChanges(title: "Old Title"))
        let tagged = try Data(contentsOf: url)

        try await TagWriterKit.strip(url: url)

        XCTAssertEqual(try Data(contentsOf: url), mp3Audio)
        XCTAssertEqual(try Data(contentsOf: backupURL(of: url)), tagged)
    }

    // MARK: - Refusals

    func testEmptyChangesAreRefusedWithoutABackup() async throws {
        let (url, original) = try makeFLAC(comments: ["TITLE": "Old Title"])

        do {
            try await TagWriterKit.write(url: url, changes: TagChanges())
            XCTFail("Expected noChangesSpecified.")
        } catch let error as TagWriteError {
            guard case .noChangesSpecified = error else { return XCTFail("unexpected \(error)") }
        }

        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL(of: url).path))
    }

    func testAnUnsupportedFileIsRefusedWithoutABackup() async throws {
        let url = temporaryDirectory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: url)

        do {
            try await TagWriterKit.write(url: url, changes: TagChanges(title: "x"))
            XCTFail("Expected unsupportedFormat.")
        } catch let error as TagWriteError {
            guard case .unsupportedFormat = error else { return XCTFail("unexpected \(error)") }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL(of: url).path))

        do {
            try await TagWriterKit.strip(url: url)
            XCTFail("Expected unsupportedFormat.")
        } catch let error as TagWriteError {
            guard case .unsupportedFormat = error else { return XCTFail("unexpected \(error)") }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL(of: url).path))
    }
}
