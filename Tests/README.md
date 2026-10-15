# Automated tests

## Run in Xcode

1. Open `TandaComposer.xcodeproj` on macOS with Xcode 26 or later.
2. Select the shared `AudioTagKitTests` scheme.
3. Run **Product > Test** (`⌘U`).

The test target compiles the `AudioTagKit` sources into the test bundle so tests can exercise internal implementation details without widening production access control. Test files live under `Tests/AudioTagKitTests`.

## Current coverage

- `BackupUtilityTests`: backup naming and byte preservation, existing backup preservation, missing source.
- `TagWriterKitTests`: empty changes and unsupported write/strip requests must be rejected without creating a backup.
- `FormatSnifferTests`: FLAC, ID3-tagged MP3, raw MPEG frame sync, MP4-family `ftyp`, AIFF/AIFC and unknown headers; checks that detection follows header bytes rather than the filename extension.

## Execution status

The project file and shared scheme XML have been syntax-checked. The current development environment is Linux and does not include `xcodebuild` or Apple's AVFoundation SDK, so the Xcode test bundle cannot be built or executed here. Run the suite on macOS/Xcode before treating it as passing.
