#!/bin/bash
# apply-orange-dots.sh
#
# Applies two changes to the TandaComposer project:
#   1. The "file not found" status dot is now ORANGE instead of red
#      (Track Library, Setlist, Tanda Library rows + the "N missing"
#      labels + the status table in help_en.html).
#   2. When the Preview Player (double-click on a track) finds that the
#      file is missing, that track gets the orange dot immediately
#      (LibraryStore.noteFileMissing), without waiting for a restart.
#      Includes two new tests in LibraryStoreTests.
#
# Usage (run it from inside the TandaComposer project folder):
#   bash apply-orange-dots.sh
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

if [ ! -f "TandaCore/TrackLibrary/TrackLibraryStore.swift" ]; then
    echo "This does not look like the TandaComposer project:"
    echo "  $ROOT"
    exit 1
fi

if ! grep -q "refreshMissingNow" TandaCore/TrackLibrary/TrackLibraryStore.swift; then
    echo "Apply the earlier fix first (apply-status-refresh-fix.sh)."
    echo "This change builds on it (refreshMissingNow is missing)."
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
echo "Done. Changed files:"
git diff --stat
echo
echo "Next: build in Xcode (Cmd-B), run the tests (Cmd-U), then commit, e.g.:"
echo "  git add -A && git commit -m \"Missing-file dot is orange; Preview Player reports missing files at once\""
exit 0

__PATCH__
diff --git a/TandaComposer/App/ContentView.swift b/TandaComposer/App/ContentView.swift
index 4bed3a8..e4e5ec8 100644
--- a/TandaComposer/App/ContentView.swift
+++ b/TandaComposer/App/ContentView.swift
@@ -396,6 +396,16 @@ struct ContentView: View {
         }
 
 
+        // The Preview Player found a file missing when the user tried to
+        // play it: show the orange dot at once instead of waiting for
+        // the next Library check (restart, drive mount, rescan).
+        .onAppear {
+            previewPlayer.onFileMissing = { song in
+                libraryStore.noteFileMissing(for: song)
+            }
+        }
+
+
         // =============================================================
         // IMPORT
         // =============================================================
diff --git a/TandaComposer/Help/help_en.html b/TandaComposer/Help/help_en.html
index d22c80d..31d513d 100644
--- a/TandaComposer/Help/help_en.html
+++ b/TandaComposer/Help/help_en.html
@@ -429,15 +429,15 @@ img.help-shot{display:block;max-width:100%;height:auto;margin:18px auto 28px;bor
     <thead><tr><th>Dot</th><th>Meaning</th><th>Typical next step</th></tr></thead>
     <tbody>
       <tr><td>No dot</td><td>The track reference is resolved.</td><td>Nothing to do.</td></tr>
-      <tr><td>Red</td><td>The file was not found at the last check.</td><td>Reconnect the drive or check the file, then rescan.</td></tr>
-      <tr><td>Blue</td><td>The track is not in the current Library.</td><td>Import the file, then rescan.</td></tr>
-      <tr><td>Orange</td><td>Tanda-only: the file was found at a new location but the saved Tanda path is old.</td><td>Rescan the Tanda Library.</td></tr>
+      <tr><td>Orange octagon</td><td>The file was not found, either at the last check or when you tried to play it with a double-click.</td><td>Reconnect the drive or check the file, then rescan.</td></tr>
+      <tr><td>Blue question mark</td><td>The track is not in the current Library.</td><td>Import the file, then rescan.</td></tr>
+      <tr><td>Orange triangle</td><td>Tanda-only: the file was found at a new location but the saved Tanda path is old.</td><td>Rescan the Tanda Library.</td></tr>
     </tbody>
   </table>
 
   <div class="shot half-shot">
     <b>SCREENSHOT PLACEHOLDER — Status dots</b>
-    TandaComposer status dots (red / blue / orange).
+    TandaComposer status dots (orange octagon / blue question mark / orange triangle).
   </div>
 
   <h3>Clean Up Missing Links</h3>
diff --git a/TandaComposer/Setlist/SetlistTableCoordinator+Cells.swift b/TandaComposer/Setlist/SetlistTableCoordinator+Cells.swift
index eaa3cb3..056ac88 100644
--- a/TandaComposer/Setlist/SetlistTableCoordinator+Cells.swift
+++ b/TandaComposer/Setlist/SetlistTableCoordinator+Cells.swift
@@ -89,7 +89,7 @@ extension SetlistTableCoordinator {
                     )
 
                 imageView.contentTintColor =
-                    .systemRed
+                    .systemOrange
 
                 imageView.toolTip =
                     "File not found on disk"
diff --git a/TandaComposer/Smartlist/SmartListFilteredLibraryView.swift b/TandaComposer/Smartlist/SmartListFilteredLibraryView.swift
index 68b511a..d3de4bb 100644
--- a/TandaComposer/Smartlist/SmartListFilteredLibraryView.swift
+++ b/TandaComposer/Smartlist/SmartListFilteredLibraryView.swift
@@ -125,7 +125,7 @@ struct SmartListFilteredLibraryView:
                         "\(libraryStore.missingSongIDs.count) missing"
                     )
                     .font(.caption)
-                    .foregroundStyle(.red)
+                    .foregroundStyle(.orange)
                 }
 
 
diff --git a/TandaComposer/TandaLibrary/TandaLibraryView.swift b/TandaComposer/TandaLibrary/TandaLibraryView.swift
index 800a216..6db5d12 100644
--- a/TandaComposer/TandaLibrary/TandaLibraryView.swift
+++ b/TandaComposer/TandaLibrary/TandaLibraryView.swift
@@ -497,7 +497,7 @@ struct TandaLibraryView:
                             "octagon.fill"
                     )
                     .font(.caption)
-                    .foregroundStyle(.red)
+                    .foregroundStyle(.orange)
                     .help(
                         "File not found on disk at last TrackLibrary rescan. If the file moved, run \"Rescan TrackLibrary\", then \"Rescan TandaLibrary\" to re-link it here."
                     )
diff --git a/TandaComposer/TandaLibrary/TandaSongRow.swift b/TandaComposer/TandaLibrary/TandaSongRow.swift
index e337774..f027195 100644
--- a/TandaComposer/TandaLibrary/TandaSongRow.swift
+++ b/TandaComposer/TandaLibrary/TandaSongRow.swift
@@ -93,7 +93,7 @@ struct TandaSongRow:
 
     // MARK: - Status Indicator
     //
-    // Mirrors LibraryTableView/SetlistView's Status column: red
+    // Mirrors LibraryTableView/SetlistView's Status column: orange
     // octagon for a file the Library couldn't find on disk at last
     // rescan, blue question mark for a song this Tanda references that
     // isn't in the current Library at all, nothing for a song that
@@ -114,7 +114,7 @@ struct TandaSongRow:
                         "octagon.fill"
                 )
                 .foregroundStyle(
-                    Color.red
+                    Color.orange
                 )
                 .help(
                     "File not found on disk"
diff --git a/TandaComposer/TrackLibrary/TrackLibraryTableCells.swift b/TandaComposer/TrackLibrary/TrackLibraryTableCells.swift
index 5d42704..bddcafc 100644
--- a/TandaComposer/TrackLibrary/TrackLibraryTableCells.swift
+++ b/TandaComposer/TrackLibrary/TrackLibraryTableCells.swift
@@ -93,7 +93,7 @@ enum LibraryTableCells {
                     )
 
                 imageView.contentTintColor =
-                    .systemRed
+                    .systemOrange
 
                 imageView.toolTip =
                     "File not found on disk"
diff --git a/TandaCore/Playback/PreviewPlayer.swift b/TandaCore/Playback/PreviewPlayer.swift
index 9961708..50977d1 100644
--- a/TandaCore/Playback/PreviewPlayer.swift
+++ b/TandaCore/Playback/PreviewPlayer.swift
@@ -35,6 +35,12 @@ final class PreviewPlayer: NSObject, ObservableObject {
     @Published private(set) var currentTime: TimeInterval = 0
     @Published private(set) var duration: TimeInterval = 0
     @Published private(set) var lastPlayErrorMessage: String?
+
+    /// Called when `play(song:)` finds that the file of the song is not
+    /// on disk. The app connects this to `LibraryStore.noteFileMissing`,
+    /// so the orange dot appears at once instead of at the next Library
+    /// check (restart, drive mount, rescan).
+    var onFileMissing: (@MainActor (Song) -> Void)?
     
     // MARK: - Audio
     
@@ -522,6 +528,12 @@ final class PreviewPlayer: NSObject, ObservableObject {
                         song.path
                 )
         )
+    
+        // play(url:) refuses a file that is not on disk (and clears
+        // currentSong). Tell the Library right away.
+        if !FileManager.default.fileExists(atPath: song.path) {
+            onFileMissing?(song)
+        }
     }
     
     // =============================================================
diff --git a/TandaCore/TrackLibrary/TrackLibraryStore.swift b/TandaCore/TrackLibrary/TrackLibraryStore.swift
index 963f505..b077214 100644
--- a/TandaCore/TrackLibrary/TrackLibraryStore.swift
+++ b/TandaCore/TrackLibrary/TrackLibraryStore.swift
@@ -794,6 +794,29 @@ public final class LibraryStore: ObservableObject {
         }
     }
 
+    /// The Preview Player tried to play `song` and found the file gone.
+    /// Marks the matching Library song as missing immediately (orange
+    /// dot everywhere) without waiting for the next Library check.
+    ///
+    /// Matches by PATH only: a Tanda snapshot from another Library can
+    /// carry an id that belongs to a different song here. A song whose
+    /// path the Library does not know is ignored (a stale Tanda path is
+    /// already shown as "outdated"). If the file exists after all,
+    /// nothing is marked.
+    public func noteFileMissing(for song: Song) {
+
+        guard let known = songsByNormalizedPath[song.normalizedPath],
+              let id = known.id,
+              !FileManager.default.fileExists(atPath: known.path)
+        else {
+            return
+        }
+
+        if !missingSongIDs.contains(id) {
+            missingSongIDs.insert(id)
+        }
+    }
+
     private nonisolated static func missingIDs(in songs: [Song]) -> Set<Int64> {
 
         let fm = FileManager.default
diff --git a/Tests/TandaCoreTests/TrackLibrary/LibraryStoreTests.swift b/Tests/TandaCoreTests/TrackLibrary/LibraryStoreTests.swift
index 3401e0a..e54d54a 100644
--- a/Tests/TandaCoreTests/TrackLibrary/LibraryStoreTests.swift
+++ b/Tests/TandaCoreTests/TrackLibrary/LibraryStoreTests.swift
@@ -358,6 +358,40 @@ final class LibraryStoreTests: XCTestCase {
         XCTAssertEqual(store.songs.map(\.id), [song.id])
     }
 
+    func testNoteFileMissingMarksTheSongAtOnce() async throws {
+        let dir = try makeTemporaryDirectory()
+        let file = try writeData(Data("x".utf8), in: dir, named: "a.flac")
+        let (store, manager) = try makeStore()
+        let song = try insert(makeSong(path: file.path, title: "A", artist: "X"), into: manager)
+        try store.reload()
+        await store.refreshMissingNow()
+        XCTAssertTrue(store.missingSongIDs.isEmpty)
+
+        // The file is there: a wrong report must not mark it.
+        store.noteFileMissing(for: song)
+        XCTAssertTrue(store.missingSongIDs.isEmpty)
+
+        // The Preview Player finds the file gone.
+        try FileManager.default.removeItem(at: file)
+        store.noteFileMissing(for: song)
+        XCTAssertEqual(store.missingSongIDs, [try XCTUnwrap(song.id)])
+    }
+
+    func testNoteFileMissingIgnoresAPathTheLibraryDoesNotKnow() async throws {
+        let dir = try makeTemporaryDirectory()
+        let file = try writeData(Data("x".utf8), in: dir, named: "a.flac")
+        let (store, manager) = try makeStore()
+        let song = try insert(makeSong(path: file.path, title: "A", artist: "X"), into: manager)
+        try store.reload()
+        await store.refreshMissingNow()
+
+        // A Tanda snapshot from another Library: same id, a path that is not ours.
+        let foreign = makeSong(id: song.id, path: "/Other/place.flac", title: "F", artist: "Y")
+        store.noteFileMissing(for: foreign)
+
+        XCTAssertTrue(store.missingSongIDs.isEmpty)
+    }
+
     // MARK: - Errors
 
     func testEveryLibraryStoreErrorHasADescription() {
