# AudioTagKit – P1 Tests

Diese Ergänzung enthält P1-Regressionstests für die bestehenden Parser/Codecs
sowie den Artwork-Extractor. **Es sind keine MP4/M4A-Tests enthalten.**

## Inhalt

- `ID3FrameCodecTests.swift` – Unicode, Kommentare, Syncsafe-Größen und defekte Frames
- `FLACBlocksTests.swift` – Block-Roundtrip, Audio-Payload-Erhalt und beschädigte Eingaben
- `AIFFChunksTests.swift` – AIFF/AIFC, Chunk-Reihenfolge, Padding und beschädigte Eingaben
- `VorbisCommentCodecTests.swift` – Unicode, Schlüssel-Normalisierung und fehlerhafte Kommentare
- `ArtworkExtractorTests.swift` – FLAC-Cover, fehlende Cover und abgeschnittene Picture-Blöcke
- `P1CodecIntegrationTests.swift` – kombinierte ID3/AIFF- und FLAC/Vorbis-Roundtrips

## Einbau

1. Den Ordner `P1` in `Tests/AudioTagKitTests/` des Projekts kopieren.
2. Sicherstellen, dass alle sechs Swift-Dateien Mitglied des Testtargets `AudioTagKitTests` sind.
   Bei Xcode File-System-Synchronized Groups werden Dateien unterhalb des Testordners üblicherweise
   automatisch aufgenommen; bei klassischen Gruppen gegebenenfalls `Add Files to ...` verwenden.
3. Das Scheme `AudioTagKitTests` ausführen.

Die Tests nutzen die internen Typen `ID3FrameCodec`, `FLACBlocks`, `AIFFChunks` und
`VorbisCommentCodec` direkt. Das entspricht dem Muster der vorhandenen Tests, sofern diese Dateien
im selben Testmodul sichtbar sind.

## Hinweise

- Die Bilddaten im FLAC-Test sind bewusst minimale Testbytes mit JPEG-Signatur; der FLAC-Picture-Parser
  prüft Container-Metadaten und liefert die Bildbytes zurück, validiert aber nicht das vollständige JPEG.
- Diese Tests wurden aus dem Projektcode abgeleitet, aber in dieser Umgebung nicht mit Xcode/macOS
  kompiliert oder ausgeführt. Bitte den Testlauf nach dem Einbau durchführen.
