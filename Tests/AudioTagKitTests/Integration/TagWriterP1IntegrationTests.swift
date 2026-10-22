/*
 import XCTest
 import Foundation
 
 /// Cross-format integration tests for the supported non-MP4 writers.
 /// These tests use small synthetic containers and do not require audio fixtures.
 final class TagWriterP1IntegrationTests: XCTestCase {
 private var temporaryDirectory: URL!
 
 override func setUpWithError() throws {
 try super.setUpWithError()
 temporaryDirectory = FileManager.default.temporaryDirectory
 .appendingPathComponent("AudioTagKitP1Integration-\(UUID().uuidString)", isDirectory: true)
 try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
 }
 
 override func tearDownWithError() throws {
 if let temporaryDirectory {
 try? FileManager.default.removeItem(at: temporaryDirectory)
 }
 try super.tearDownWithError()
 }
 
 func testMP3WritePreservesAudioAndFirstOriginalBackup() async throws {
 let audio = Data([0xFF, 0xFB, 0x90, 0x64, 0x11, 0x22, 0x33, 0x44])
 let url = temporaryDirectory.appendingPathComponent("integration.mp3")
 var original = ID3FrameCodec.header(bodySize: 0)
 original.append(audio)
 try original.write(to: url)
 
 try await TagWriterKit.write(url: url, changes: TagChanges(title: "First title"))
 let firstBackup = try Data(contentsOf: URL(fileURLWithPath: url.path + "_original"))
 XCTAssertEqual(firstBackup, original, "The backup must be the exact pre-edit file.")
 
 try await TagWriterKit.write(url: url, changes: TagChanges(artist: "Integration artist"))
 let backupAfterSecondWrite = try Data(contentsOf: URL(fileURLWithPath: url.path + "_original"))
 XCTAssertEqual(backupAfterSecondWrite, original, "A later edit must not replace the first backup.")
 
 let result = try Data(contentsOf: url)
 XCTAssertEqual(mp3AudioPayload(in: result), audio, "Tag edits must preserve the audio payload.")
 let frames = ID3FrameCodec.parseTag(result)
 XCTAssertTrue(frames.contains { $0.id == "TIT2" }, "Title frame should remain after a subsequent artist edit.")
 XCTAssertTrue(frames.contains { $0.id == "TPE1" }, "Artist frame should be written.")
 XCTAssertEqual(frames.filter { $0.id == "TIT2" }.count, 1)
 XCTAssertEqual(frames.filter { $0.id == "TPE1" }.count, 1)
 }
 
 func testFLACWritePreservesAudioAndFirstOriginalBackup() async throws {
 let audio = Data([0xF8, 0x72, 0x10, 0x20, 0x30, 0x40])
 let url = temporaryDirectory.appendingPathComponent("integration.flac")
 let original = makeFLAC(audio: audio, comments: ["ALBUM": "Original album"])
 try original.write(to: url)
 
 try await TagWriterKit.write(url: url, changes: TagChanges(title: "FLAC integration"))
 let backupURL = URL(fileURLWithPath: url.path + "_original")
 XCTAssertEqual(try Data(contentsOf: backupURL), original)
 
 try await TagWriterKit.write(url: url, changes: TagChanges(genre: "Test genre"))
 XCTAssertEqual(try Data(contentsOf: backupURL), original, "First backup should remain unchanged.")
 
 let result = try Data(contentsOf: url)
 let parsed = try FLACBlocks.parse(result)
 XCTAssertEqual(result.subdata(in: parsed.audioOffset..<result.endIndex), audio)
 
 let commentsBlock = try XCTUnwrap(parsed.blocks.first { $0.type == FLACBlocks.vorbisComment })
 let comments = VorbisCommentCodec.decode(commentsBlock.data)
 XCTAssertEqual(comments["TITLE"], "FLAC integration")
 XCTAssertEqual(comments["GENRE"], "Test genre")
 XCTAssertEqual(comments["ALBUM"], "Original album", "Unchanged comments should be preserved.")
 XCTAssertEqual(parsed.blocks.filter { $0.type == FLACBlocks.vorbisComment }.count, 1)
 }
 
 func testAIFFWritePreservesSoundAndFirstOriginalBackup() async throws {
 let sound = Data([0x10, 0x20, 0x30, 0x40, 0x50])
 let custom = Data([0xCA, 0xFE, 0xBA])
 let url = temporaryDirectory.appendingPathComponent("integration.aiff")
 let original = AIFFChunks.serialize(
 formType: "AIFF",
 chunks: [
 AIFFChunk(id: "COMM", data: Data([0, 1, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
 AIFFChunk(id: "SSND", data: sound),
 AIFFChunk(id: "XTRA", data: custom)
 ]
 )
 try original.write(to: url)
 
 try await TagWriterKit.write(url: url, changes: TagChanges(title: "AIFF integration"))
 let backupURL = URL(fileURLWithPath: url.path + "_original")
 XCTAssertEqual(try Data(contentsOf: backupURL), original)
 
 try await TagWriterKit.write(url: url, changes: TagChanges(artist: "AIFF artist"))
 XCTAssertEqual(try Data(contentsOf: backupURL), original, "Second write must not overwrite original backup.")
 
 let parsed = try AIFFChunks.parse(Data(contentsOf: url))
 XCTAssertEqual(parsed.formType, "AIFF")
 XCTAssertEqual(parsed.chunks.first { $0.id == "SSND" }?.data, sound)
 XCTAssertEqual(parsed.chunks.first { $0.id == "XTRA" }?.data, custom)
 
 let id3Chunk = try XCTUnwrap(parsed.chunks.first { $0.id == "ID3 " })
 let frames = ID3FrameCodec.parseTag(id3Chunk.data)
 XCTAssertTrue(frames.contains { $0.id == "TIT2" })
 XCTAssertTrue(frames.contains { $0.id == "TPE1" })
 XCTAssertEqual(frames.filter { $0.id == "TIT2" }.count, 1)
 XCTAssertEqual(frames.filter { $0.id == "TPE1" }.count, 1)
 }
 
 func testMalformedMP3WriteFailureLeavesSourceUnchangedAndBackupExact() async throws {
 let url = temporaryDirectory.appendingPathComponent("broken.mp3")
 // Valid ID3 signature with a declared body larger than the available bytes.
 let malformed = Data([
 0x49, 0x44, 0x33, 0x04, 0x00, 0x00,
 0x00, 0x00, 0x00, 0x20,
 0x11, 0x22
 ])
 try malformed.write(to: url)
 
 do {
 try await TagWriterKit.write(url: url, changes: TagChanges(title: "Should fail"))
 XCTFail("Expected malformed ID3 input to fail.")
 } catch {
 XCTAssertEqual(try Data(contentsOf: url), malformed, "A failed write must not change the source.")
 let backupURL = URL(fileURLWithPath: url.path + "_original")
 XCTAssertEqual(try Data(contentsOf: backupURL), malformed, "Backup must preserve exact original bytes.")
 }
 }
 
 // MARK: - Synthetic fixture helpers
 
 private func makeFLAC(audio: Data, comments: [String: String]) -> Data {
 let blocks = [
 FLACBlock(type: FLACBlocks.streamInfo, data: Data(repeating: 0, count: 34)),
 FLACBlock(type: FLACBlocks.vorbisComment, data: VorbisCommentCodec.encode(comments))
 ]
 return FLACBlocks.serialize(blocks: blocks, audioData: audio)
 }
 
 private func mp3AudioPayload(in data: Data) -> Data {
 guard data.count >= 10, data.prefix(3).elementsEqual("ID3".utf8) else { return data }
 let size = ID3FrameCodec.syncsafeDecode(data.subdata(in: 6..<10))
 let start = min(data.count, 10 + size)
 return data.subdata(in: start..<data.count)
 }
 }
 */
