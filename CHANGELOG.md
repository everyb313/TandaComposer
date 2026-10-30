## Changelog

## Version 0.8.5 (Build 8) — 2026-10-30

### Added
- **Title search** in the TrackLibrary: a search field with a magnifier icon at the top of the Smartlist column, directly above “Show All”.
- One typed letter finds the titles that **start with** it; two or more letters find the titles that **contain** the text.
- The search looks at the title only. Case, accents and surrounding spaces are ignored (“a” also finds “Ángel”).
- A ✕ button in the field and the Escape key clear the search.

### Changed
- While a search is active it **replaces the Smartlist**: the track list shows the matches from the whole TrackLibrary, and the Smartlist column is dimmed. The header label shows “Title search” instead of the Smartlist name.
- The A/T/V/M/X filter buttons are greyed out and not applied while a search is active (they will be combined with the search later).
- Double-clicking “Show All” or a Smartlist clears the search.
- Switching the TrackLibrary clears the search.
- The same-title filter still takes precedence over everything else.

### Internal
- The library store no longer filters. `LibraryStore.songs` and its lookup caches (`songsByID`, `songsByNormalizedPath`) always cover the whole TrackLibrary, so Rescans, Duplicate Finder, imports, Clean Up Missing Links and Save Library are never affected by a search. All display filters are applied by the views.
- The search rules live in the new `TrackTitleSearch` (with its own test suite). The old five-field store search was removed.

### Unchanged
- Smartlists, the A/T/V/M/X filter and the same-title filter work as before when no search is active.

## Version 0.8.4 (Build 8) — 2026-10-29

### Fixed
- **Rescan TandaLibrary:** when several Tandas needed renaming in one scan (e.g. to fill a gap in the numbering), they could all be assigned the same new name (e.g. `…_VariousSingers_5`). Applying such a preview would have overwritten Tanda files and lost data. Each Tanda now gets its own unique name.

### Improved
- Gaps in the Tanda numbering are closed in a single scan (`_6 → _5`, `_7 → _6`, `_8 → _7`).
- Rescan processes Tandas in natural numeric order (`_6` before `_10`), and applies the fixes in that same order.
- “Apply Fixes” never overwrites an existing Tanda file that belongs to a different Tanda. Such a rename is skipped and reported as a failed write; the original file stays untouched.

### Unchanged
- Track reconnection in saved Tandas works as before.
- Tandas whose name and folder are already correct are not touched.

## Version 0.8.3 (Build 8) — 2026-10-29

### Added
- Added a vertical “Songs by Year” chart to the orchestra statistics window.
- Song counts are grouped by the year recorded in the song metadata.

### Improved
- The chart's X-axis now spans the minimum and maximum years found among the songs instead of starting at year zero.
- Single-year datasets receive a small axis range so the chart remains readable.

### Unchanged
- The existing orchestra tanda statistics remain unchanged.
- Songs without a valid year are excluded from the yearly chart.
