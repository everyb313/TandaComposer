# Changelog

## Version 0.8.1 (Build 8) — 2026-10-28

### Added
- Same-name filter in the existing TrackView, activated from the Setlist.
- Automatic filter update when the focused track in the Setlist changes.
- Drag-and-drop support for adding tracks from the Setlist to an unlocked Tanda Library.
- A dedicated `+` row at the bottom of the selected, unlocked Tanda Library.

### Changed
- The active same-name filter is indicated by an orange `?` in the Setlist and next to the library name in TrackView.
- The standalone `?` control in TrackView has been removed.
- Smartlists are visually dimmed while the same-name filter is active.
- Tanda coloring is disabled by default.
- The `+` symbol in the Tanda Library has been repositioned for better alignment.

### Rules and behavior
- Adding a track already present in the same Tanda Library is prevented.
- Different tracks with the same title are allowed.
- Adding a track to a Tanda Library does not modify the Setlist.
- The same-name filter uses the existing TrackView insertion behavior; it does not replace Setlist entries.
- Legacy standalone same-name window and replacement-related code has been cleaned up.

### Maintenance
- Removed obsolete same-name window components and related replacement plumbing.
- Simplified same-name session state to support the TrackView filter.
