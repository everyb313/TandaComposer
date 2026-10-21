import Foundation

/// Builds a small but valid FLAC file for tests: the "fLaC" marker, a
/// STREAMINFO block (sample rate, channels, bit depth, total samples), a
/// VORBIS_COMMENT block with the given tags, and `audioBytes` bytes of
/// fake audio data. The app's own FLAC reader needs nothing more to read
/// tags, sample rate and duration, so no audio encoder is involved.
///
/// - `seconds` + `extraSamples` define the duration (`extraSamples` allows
///   fractions of a second, e.g. 22_050 at 44.1 kHz is half a second).
/// - `audioBytes` changes file size and content (and therefore the SHA-256).
func makeFLACData(
    tags: [String: String] = [:],
    seconds: Int = 200,
    extraSamples: Int = 0,
    sampleRate: Int = 44_100,
    audioBytes: Int = 16
) -> Data {
    let channels = 2
    let bitsPerSample = 16
    let totalSamples = seconds * sampleRate + extraSamples

    var info = Data(count: 34)
    info[10] = UInt8((sampleRate >> 12) & 0xFF)
    info[11] = UInt8((sampleRate >> 4) & 0xFF)
    info[12] = UInt8(((sampleRate & 0x0F) << 4) | ((channels - 1) << 1) | ((bitsPerSample - 1) >> 4))
    info[13] = UInt8((((bitsPerSample - 1) & 0x0F) << 4) | ((totalSamples >> 32) & 0x0F))
    info[14] = UInt8((totalSamples >> 24) & 0xFF)
    info[15] = UInt8((totalSamples >> 16) & 0xFF)
    info[16] = UInt8((totalSamples >> 8) & 0xFF)
    info[17] = UInt8(totalSamples & 0xFF)

    let blocks = [
        FLACBlock(type: FLACBlocks.streamInfo, data: info),
        FLACBlock(type: FLACBlocks.vorbisComment, data: VorbisCommentCodec.encode(tags))
    ]

    return FLACBlocks.serialize(blocks: blocks, audioData: Data(repeating: 0xAB, count: audioBytes))
}
