# Changelog

All notable changes to TandaComposer are documented in this file.

## [0.7.0] - 2026-10-25

### Added
- Automated tests: `TandaCoreTests` and `AudioTagKitTests` (both shared
  schemes), plus `coverage.sh` for a coverage report of both.
- Import Setlist (Pick Tracks): lines that name an orchestra and/or a
  singer list only matching tracks; without one, same-titled tracks are
  offered as incomplete suggestions under "No candidate (...)".

### Changed
- "Instrumental" is a singer category of its own; it matches other
  instrumental spellings, never an empty or a named singer.
- Tandas from ZIP, "Show tracks": no doubled track number, "best of
  several files" in orange, "n candidates" for open lines, and the
  only match looks like every other line with candidates.

### Fixed
- AudioTagKit: stripping an MP3 with an inconsistent ID3 header no longer
  risks an emptied file; AIFF files with a wrong FORM size are read, but
  never rewritten.

## [0.5.3] - 2026-10-12

### Fixed
- Setlist and Tanda files: file paths are written with plain `/`
  again instead of `\/` (`/Volumes/...`), so they stay readable.
  Existing files keep `\/` until rewritten; they still load fine.

## [0.5.2] - 2026-10-12

### Fixed
- Saved Setlists view: the duplicate-check icon now appears as soon as
  a saved Setlist is shown; before, it only appeared after the Library
  lock was toggled.
- Typo in the Tools → Export menu ("Selists" → "Setlists").

### Changed
- Menu labels, dialogs, README and Help use the same names for the
  Tools → Export / Import commands.

## [0.5.1] - 2026-10-12

Covers all changes since 0.1.3 (version numbers in between were not
recorded here).

### Added
- Tanda Library: permanent "new Tanda" drop lane; click a Tanda's
  title to select/deselect; orange "Library is locked" hint when
  dragging over a locked Tanda Library.
- Track Library: the selected row keeps its on-screen position after
  re-sorting by a column header.
- Edit Tags… (experimental): write Title, Orchestra, Singer
  (AlbumArtist), Genre, Year and Comment into FLAC, MP3, M4A/AAC and
  AIFF files; a `_original` backup copy is made before the first change.
- Saved Setlists view: optional cross-Setlist duplicate check (toggle
  in the title row, default off).
- Import Setlist (Pick Tracks) (in development): imports M3U8 or plain
  text lists; tracks that do not match exactly can be picked by hand
  from same-named Library tracks. New setting "Auto-pick best file".
- Share Tandas: Tools → Export → TandaLibrary (ZIP)… and
  Tools → Import → Tandas from ZIP… (experimental).

### Changed
- All import/export commands now live in the Tools menu
  (Export / Import submenus); the Setlist menu only manages Setlists.
- "Playlist" renamed to "Setlist" in the UI and in code identifiers
  (on-disk JSON keys and stored settings unchanged).
- Large source files split by responsibility (no behavior change).

### Fixed
- Import: name recognition no longer strips names out of titles and is
  faster; imports are only matched against a library with a trusted ID.

## [0.1.3] - 2026-09-24

### Added
- Tanda Library: existing Tandas can now be edited directly instead of
  only created/deleted. Drop the current Setlist selection directly
  onto a Tanda block to append those tracks to it (dropping on the
  background still creates a new Tanda, as before). Each track row
  has a small red "x" to remove it individually, visible only while
  that Tanda is selected, the Library is unlocked, and removing
  wouldn't drop the Tanda below the 3-track minimum.
- Rescan TandaLibrary now also detects when a Tanda's saved
  name/folder no longer matches what its current tracks resolve to
  (e.g. after adding/removing a track changed the Orchestra/Singer
  mix), and offers to rename/refile it — old and new path are shown
  side by side in the preview before Apply, same as the existing
  track-reference fixes.

### Fixed
- Singer (AlbumArtist) and Genre resolution, used when saving/editing
  a Tanda, is now case- and diacritic-insensitive, matching the
  Orchestra comparison that already worked this way. Previously,
  tags for the same singer or genre differing only by case or accents
  (e.g. "Podestá" vs "Podesta") were treated as different values and
  could incorrectly produce `VariousSingers`/`VariousGenres`,
  misfiling the Tanda.

### Changed
- Tanda Library: Tanda blocks are now sorted alphabetically by name
  instead of filesystem/load order.

## [0.1.1] - 2026-09-16

### Removed
- Dead `playlists`/`playlist_songs` SQLite tables and their migration
  code (`createPlaylists`/`createPlaylistSongs`). Setlists/Tandas are
  stored as JSON files on disk and have not used these tables in a
  long time.

### Fixed
- Library-file validity check (`DatabaseManager.loadLibrary`) no
  longer requires the now-removed `playlists`/`playlist_songs` tables
  to exist — only `songs` is checked.

## [0.1.0]

- Initial tracked version.
