# Changelog

All notable changes to TandaComposer are documented in this file.

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
