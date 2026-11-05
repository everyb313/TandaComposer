#!/bin/bash
# apply-tanda-header.sh
#
# Every Tanda file now records, in its header, which tag fields the user's
# "Orchestra" and "Singer" come from (Settings -> Tag Source):
#
#   {
#     "format" : "TandaComposer Tanda",
#     "version" : 1,
#     "tandaName" : "Calo_Tango_Instrumental",
#     "orchestraSource" : "artist",
#     "singerSource" : "albumArtist",
#     "savedAgainstLibraryName" : "USB_EdO",
#     "savedAt" : "2026-09-14T09:33:32Z",
#     "comment" : "",
#     "songs" : [ ...
#
# - Written by EVERY write of a Tanda file (new save, comment, add/remove
#   a track, replace a track, rescan) with the current Settings values.
# - Older files without these keys still load (the convention is "unknown").
# - Key order changed: savedAgainstLibraryName now comes before savedAt.
#
# New files:  TandaCore/Settings/TandaConventions.swift
#             Tests/TandaCoreTests/Settings/TandaConventionsTests.swift
# Changed:    TandaCore/TandaLibrary/TandaMetadataExport.swift,
#             TandaCore/Settings/AppSettings.swift (2 didSet mirrors),
#             Tests/.../TandaMetadataExportTests.swift, TandaStoreTests.swift
#
# Usage (run it from inside the TandaComposer project folder):
#   bash apply-tanda-header.sh
#
# The patch is stored inside this file. The script only runs
# `git apply`; it does not commit, and it changes nothing if the patch
# does not fit your files.

set -u

if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo "Not inside a git repository."
    echo "cd into the TandaComposer project folder first, then run:  bash $0"
    exit 1
fi
cd "$ROOT" || exit 1

if [ ! -f "TandaCore/TandaLibrary/TandaMetadataExport.swift" ]; then
    echo "This does not look like the TandaComposer project:"
    echo "  $ROOT"
    exit 1
fi

TMP="$(mktemp "${TMPDIR:-/tmp}/tandacomposer-fix.XXXXXX")" || exit 1
trap 'rm -f "$TMP"' EXIT

sed -n '/^__PATCH__$/,$p' "$0" | sed '1d' > "$TMP"

if git apply --reverse --check "$TMP" >/dev/null 2>&1; then
    echo "This change is already applied here. Nothing to do."
    exit 0
fi

echo "Project: $ROOT"
echo "Checking whether the patch fits ..."
if ! git apply --check "$TMP"; then
    echo
    echo "The patch does NOT fit - nothing was changed."
    echo "One of the files was probably edited after the patch was made."
    echo "Send me the files named in the error above and I will adapt the patch."
    exit 1
fi

git apply "$TMP" || { echo "git apply failed."; exit 1; }

echo
echo "Done. Changed and new files:"
git status --short
echo
echo "Next: build in Xcode (Cmd-B), run the tests (Cmd-U), then commit, e.g.:"
echo "  git add -A && git commit -m \"Tanda files record orchestraSource/singerSource in the header\""
exit 0

__PATCH__
diff --git a/TandaCore/Settings/AppSettings.swift b/TandaCore/Settings/AppSettings.swift
index 918d7e9..7696d89 100644
--- a/TandaCore/Settings/AppSettings.swift
+++ b/TandaCore/Settings/AppSettings.swift
@@ -186,10 +186,19 @@ final class AppSettings:
     // =============================================================
 
     @Published var orchestraSource:
-        TagSource = .artist
+        TagSource = .artist {
+        didSet {
+            // Mirror for code that writes Tanda files (see TandaConventions).
+            TandaConventions.orchestra = orchestraSource
+        }
+    }
 
     @Published var singerSource:
-        TagSource = .albumArtist
+        TagSource = .albumArtist {
+        didSet {
+            TandaConventions.singer = singerSource
+        }
+    }
 
 
     // =============================================================
diff --git a/TandaCore/Settings/TandaConventions.swift b/TandaCore/Settings/TandaConventions.swift
new file mode 100644
index 0000000..a45b0c7
--- /dev/null
+++ b/TandaCore/Settings/TandaConventions.swift
@@ -0,0 +1,47 @@
+//
+//  TandaConventions.swift
+//
+//  Copyright © 2026 Hagen Eckert.
+//
+//  This program is free software: you can redistribute it and/or modify
+//  it under the terms of the GNU General Public License as published by
+//  the Free Software Foundation, either version 3 of the License, or
+//  (at your option) any later version.
+//
+//  This program is distributed in the hope that it will be useful,
+//  but WITHOUT ANY WARRANTY; without even the implied warranty of
+//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
+//  GNU General Public License for more details.
+//
+//  You should have received a copy of the GNU General Public License
+//  along with this program. If not, see <https://www.gnu.org/licenses/>.
+//
+
+import Foundation
+
+
+// MARK: - Tanda Conventions
+//
+// "Orchestra" and "Singer" are not tags of their own: the user decides
+// which tag field (Artist, AlbumArtist or Grouping) holds them
+// (Settings → `AppSettings.orchestraSource` / `singerSource`).
+//
+// Every Tanda file records that choice in its header
+// ("orchestraSource", "singerSource"), so whoever reads the file later —
+// for example another DJ importing the Tanda into a different
+// TrackLibrary — knows how to read the raw tags in it.
+//
+// The Tanda writer (`TandaMetadataExporter.export`) takes the values
+// from here by default, the same way it takes the library name from
+// `AppPaths.currentLibraryName`: this is a MIRROR of the two settings,
+// kept in step by `AppSettings` (didSet on both properties). It exists
+// only so that code which writes a Tanda without having the settings at
+// hand (editing a comment, adding or removing a track, a rescan) still
+// records the current choice.
+
+public enum TandaConventions {
+
+    public static var orchestra: TagSource = .artist
+
+    public static var singer: TagSource = .albumArtist
+}
diff --git a/TandaCore/TandaLibrary/TandaMetadataExport.swift b/TandaCore/TandaLibrary/TandaMetadataExport.swift
index c361264..ccc3257 100644
--- a/TandaCore/TandaLibrary/TandaMetadataExport.swift
+++ b/TandaCore/TandaLibrary/TandaMetadataExport.swift
@@ -52,12 +52,22 @@ public struct TandaMetadataExport: Codable {
     /// property's doc comment.
     public let savedAgainstLibraryName: String?
 
+    /// Which tag field the user's "Orchestra" / "Singer" came from when
+    /// this file was last written (Settings → Tag Source): "artist",
+    /// "albumArtist" or "grouping". The raw tags in `songs` are only
+    /// meaningful together with this choice. `nil` for files written
+    /// before these fields existed (the convention is unknown then).
+    public let orchestraSource: TagSource?
+    public let singerSource: TagSource?
+
     public init(
         tandaName: String,
         songs: [Song],
         savedAt: Date = Date(),
         comment: String? = nil,
-        savedAgainstLibraryName: String? = AppPaths.currentLibraryName
+        savedAgainstLibraryName: String? = AppPaths.currentLibraryName,
+        orchestraSource: TagSource? = nil,
+        singerSource: TagSource? = nil
     ) {
         self.format = "TandaComposer Tanda"
         self.version = 1
@@ -66,6 +76,8 @@ public struct TandaMetadataExport: Codable {
         self.songs = songs
         self.comment = comment
         self.savedAgainstLibraryName = savedAgainstLibraryName
+        self.orchestraSource = orchestraSource
+        self.singerSource = singerSource
     }
 }
 
@@ -77,13 +89,21 @@ public enum TandaMetadataExporter {
     /// Exports a Tanda as a self-contained JSON file.
     ///
     /// The order of `songs` is preserved exactly as supplied.
+    ///
+    /// The header records which tag fields the user's "Orchestra" and
+    /// "Singer" came from (`orchestraSource` / `singerSource`). By default
+    /// that is the current choice from Settings (see `TandaConventions`),
+    /// so every write of a Tanda file — new save, comment, add/remove a
+    /// track, rescan — records it.
     public static func export(
         songs: [Song],
         tandaName: String,
         to fileURL: URL,
         savedAt: Date = Date(),
         comment: String? = nil,
-        savedAgainstLibraryName: String? = AppPaths.currentLibraryName
+        savedAgainstLibraryName: String? = AppPaths.currentLibraryName,
+        orchestraSource: TagSource? = TandaConventions.orchestra,
+        singerSource: TagSource? = TandaConventions.singer
     ) throws {
 
         let export =
@@ -92,7 +112,9 @@ public enum TandaMetadataExporter {
                 songs: songs,
                 savedAt: savedAt,
                 comment: comment,
-                savedAgainstLibraryName: savedAgainstLibraryName
+                savedAgainstLibraryName: savedAgainstLibraryName,
+                orchestraSource: orchestraSource,
+                singerSource: singerSource
             )
 
         let doc =
@@ -100,11 +122,13 @@ public enum TandaMetadataExporter {
                 ("format", .string(export.format)),
                 ("version", .number(String(export.version))),
                 ("tandaName", .string(export.tandaName)),
+                ("orchestraSource", .opt(export.orchestraSource?.rawValue)),
+                ("singerSource", .opt(export.singerSource?.rawValue)),
+                ("savedAgainstLibraryName", .opt(export.savedAgainstLibraryName)),
                 ("savedAt", .string(
                     SongMetadataJSON.iso8601String(export.savedAt)
                 )),
                 ("comment", .opt(export.comment)),
-                ("savedAgainstLibraryName", .opt(export.savedAgainstLibraryName)),
                 ("songs", .array(
                     export.songs.map(SongMetadataJSON.orderedValue)
                 )),
diff --git a/Tests/TandaCoreTests/Settings/TandaConventionsTests.swift b/Tests/TandaCoreTests/Settings/TandaConventionsTests.swift
new file mode 100644
index 0000000..e62ef59
--- /dev/null
+++ b/Tests/TandaCoreTests/Settings/TandaConventionsTests.swift
@@ -0,0 +1,71 @@
+//
+//  TandaConventionsTests.swift
+//
+//  Copyright © 2026 Hagen Eckert.
+//
+//  This program is free software: you can redistribute it and/or modify
+//  it under the terms of the GNU General Public License as published by
+//  the Free Software Foundation, either version 3 of the License, or
+//  (at your option) any later version.
+//
+//  This program is distributed in the hope that it will be useful,
+//  but WITHOUT ANY WARRANTY; without even the implied warranty of
+//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
+//  GNU General Public License for more details.
+//
+//  You should have received a copy of the GNU General Public License
+//  along with this program. If not, see <https://www.gnu.org/licenses/>.
+
+import XCTest
+import Foundation
+
+/// `TandaConventions` mirrors the Orchestra / Singer tag-source settings
+/// for code that writes a Tanda file without having the settings at hand.
+@MainActor
+final class TandaConventionsTests: XCTestCase {
+
+    private var savedOrchestra: TagSource = .artist
+    private var savedSinger: TagSource = .albumArtist
+
+    override func setUp() {
+        super.setUp()
+        savedOrchestra = TandaConventions.orchestra
+        savedSinger = TandaConventions.singer
+    }
+
+    override func tearDown() {
+        TandaConventions.orchestra = savedOrchestra
+        TandaConventions.singer = savedSinger
+        super.tearDown()
+    }
+
+    func testChangingTheSettingsUpdatesTheMirror() throws {
+        try withTemporaryAppRoot { _ in
+            let settings = AppSettings()
+
+            settings.orchestraSource = .grouping
+            settings.singerSource = .artist
+
+            XCTAssertEqual(TandaConventions.orchestra, .grouping)
+            XCTAssertEqual(TandaConventions.singer, .artist)
+        }
+    }
+
+    func testLoadingSavedSettingsUpdatesTheMirror() throws {
+        try withTemporaryAppRoot { _ in
+            let first = AppSettings()
+            first.orchestraSource = .albumArtist
+            first.singerSource = .grouping
+            first.save()
+
+            // Forget what the mirror knows, then start "the app" again.
+            TandaConventions.orchestra = .artist
+            TandaConventions.singer = .artist
+
+            _ = AppSettings()
+
+            XCTAssertEqual(TandaConventions.orchestra, .albumArtist)
+            XCTAssertEqual(TandaConventions.singer, .grouping)
+        }
+    }
+}
diff --git a/Tests/TandaCoreTests/TandaLibrary/TandaMetadataExportTests.swift b/Tests/TandaCoreTests/TandaLibrary/TandaMetadataExportTests.swift
index cae898f..852a3c2 100644
--- a/Tests/TandaCoreTests/TandaLibrary/TandaMetadataExportTests.swift
+++ b/Tests/TandaCoreTests/TandaLibrary/TandaMetadataExportTests.swift
@@ -55,7 +55,7 @@ final class TandaMetadataExportTests: XCTestCase {
         try export(songs: [makeFullSong()], comment: "c", to: file)
         let text = try String(contentsOf: file, encoding: .utf8)
 
-        let keys = ["\"format\"", "\"version\"", "\"tandaName\"", "\"savedAt\"", "\"comment\"", "\"savedAgainstLibraryName\"", "\"songs\""]
+        let keys = ["\"format\"", "\"version\"", "\"tandaName\"", "\"orchestraSource\"", "\"singerSource\"", "\"savedAgainstLibraryName\"", "\"savedAt\"", "\"comment\"", "\"songs\""]
         let positions = try keys.map { key in
             try XCTUnwrap(text.range(of: key), "\(key) missing").lowerBound
         }
@@ -98,5 +98,86 @@ final class TandaMetadataExportTests: XCTestCase {
         XCTAssertEqual(loaded.tandaName, "Old Tanda")
         XCTAssertNil(loaded.comment)
         XCTAssertNil(loaded.savedAgainstLibraryName)
+        XCTAssertNil(loaded.orchestraSource, "a file from before the convention was recorded: unknown")
+        XCTAssertNil(loaded.singerSource)
+    }
+
+    // MARK: - Orchestra / Singer convention in the header
+
+    func testTheHeaderRecordsOrchestraAndSingerSource() throws {
+        let dir = try makeTemporaryDirectory()
+        let file = dir.appendingPathComponent("Tanda.json")
+
+        try TandaMetadataExporter.export(
+            songs: [],
+            tandaName: "Calo_Tango_Instrumental",
+            to: file,
+            savedAt: wholeSecondDate,
+            comment: "",
+            savedAgainstLibraryName: "USB_EdO",
+            orchestraSource: .artist,
+            singerSource: .albumArtist
+        )
+
+        let text = try String(contentsOf: file, encoding: .utf8)
+        XCTAssertTrue(text.contains("\"orchestraSource\" : \"artist\""), text)
+        XCTAssertTrue(text.contains("\"singerSource\" : \"albumArtist\""), text)
+
+        let loaded = try TandaMetadataExporter.load(from: file)
+        XCTAssertEqual(loaded.orchestraSource, .artist)
+        XCTAssertEqual(loaded.singerSource, .albumArtist)
+    }
+
+    func testEveryTagSourceRoundTrips() throws {
+        let dir = try makeTemporaryDirectory()
+
+        for source in TagSource.allCases {
+            let file = dir.appendingPathComponent("\(source.rawValue).json")
+
+            try TandaMetadataExporter.export(
+                songs: [], tandaName: "T", to: file,
+                orchestraSource: source, singerSource: source
+            )
+
+            let loaded = try TandaMetadataExporter.load(from: file)
+            XCTAssertEqual(loaded.orchestraSource, source)
+            XCTAssertEqual(loaded.singerSource, source)
+        }
+    }
+
+    func testAnUnknownConventionIsWrittenAsNullAndLoadsAsNil() throws {
+        let dir = try makeTemporaryDirectory()
+        let file = dir.appendingPathComponent("Tanda.json")
+
+        try TandaMetadataExporter.export(
+            songs: [], tandaName: "T", to: file,
+            orchestraSource: nil, singerSource: nil
+        )
+
+        let text = try String(contentsOf: file, encoding: .utf8)
+        XCTAssertTrue(text.contains("\"orchestraSource\" : null"), text)
+
+        let loaded = try TandaMetadataExporter.load(from: file)
+        XCTAssertNil(loaded.orchestraSource)
+        XCTAssertNil(loaded.singerSource)
+    }
+
+    func testWithoutExplicitValuesTheCurrentSettingsAreRecorded() throws {
+        let savedOrchestra = TandaConventions.orchestra
+        let savedSinger = TandaConventions.singer
+        defer {
+            TandaConventions.orchestra = savedOrchestra
+            TandaConventions.singer = savedSinger
+        }
+        TandaConventions.orchestra = .grouping
+        TandaConventions.singer = .artist
+
+        let dir = try makeTemporaryDirectory()
+        let file = dir.appendingPathComponent("Tanda.json")
+        try export(songs: [], to: file)          // the helper passes no sources
+
+        let loaded = try TandaMetadataExporter.load(from: file)
+        XCTAssertEqual(loaded.orchestraSource, .grouping)
+        XCTAssertEqual(loaded.singerSource, .artist)
     }
 }
diff --git a/Tests/TandaCoreTests/TandaLibrary/TandaStoreTests.swift b/Tests/TandaCoreTests/TandaLibrary/TandaStoreTests.swift
index 65ce88b..24891ca 100644
--- a/Tests/TandaCoreTests/TandaLibrary/TandaStoreTests.swift
+++ b/Tests/TandaCoreTests/TandaLibrary/TandaStoreTests.swift
@@ -183,6 +183,31 @@ final class TandaStoreTests: XCTestCase {
         }
     }
 
+    func testEveryWriteRecordsTheCurrentOrchestraAndSingerSource() throws {
+        let savedOrchestra = TandaConventions.orchestra
+        let savedSinger = TandaConventions.singer
+        defer {
+            TandaConventions.orchestra = savedOrchestra
+            TandaConventions.singer = savedSinger
+        }
+
+        try withTemporaryAppRoot { _ in
+            TandaConventions.orchestra = .artist
+            TandaConventions.singer = .albumArtist
+            try writeTanda("Set", songs: makeSongs(3), comment: "old")
+            let store = TandaStore()
+
+            // The user changes the convention in Settings, then edits the Tanda.
+            TandaConventions.orchestra = .grouping
+            TandaConventions.singer = .artist
+            try store.updateComment(for: try tanda("Set", in: store), to: "x")
+
+            let file = try TandaMetadataExporter.load(from: try tanda("Set", in: store).sourceURL)
+            XCTAssertEqual(file.orchestraSource, .grouping)
+            XCTAssertEqual(file.singerSource, .artist)
+        }
+    }
+
     func testUpdateCommentIsStoredInMemoryAndOnDisk() throws {
         try withTemporaryAppRoot { _ in
             try writeTanda("Set", songs: makeSongs(3), comment: "old")
