# Changelog

All notable changes to TandaComposer are documented in this file.

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
