## Changelog

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
