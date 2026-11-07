## Version 0.8.7 — 2026-11-07

### Setlist JSON (share + save header)

**Save Set**
- Setlist JSON files now record `orchestraSource`, `singerSource`, and optional `comment` in the header (same idea as Tanda JSON).
- Older Setlist files without these keys still load; the fields are then `nil`.

**Export**
- **Tools → Export → Current Setlist (JSON)…** — full Setlist as TandaComposer JSON for another user (includes convention header and track hashes).
- **Current Setlist (M3U8)…** unchanged for the player.

**Import**
- **Tools → Import → Setlist from List or M3U8…** also accepts Setlist JSON.
- JSON tracks are mapped by Orchestra / Singer **role** from the file header; file hash is carried over.
- Special Import window shows a short convention note (sender vs. you) for JSON files.
- Exact path matches still get a short confirmation; otherwise the pick-tracks window opens.

### Help
- `help_en.html` documents JSON export/import and the updated import entry.

### Tests
- `SetlistMetadataExportTests`: header field order, sources/comment round-trip, older files without sources.
- `SetlistJSONReaderTests` (new): format check, role mapping, missing header, convention note.

### Files touched

```
TandaCore/SavedSetlist/SetlistMetadataExport.swift
TandaCore/Import/SetlistJSONReader.swift
TandaComposer/Setlist/SetlistActions+ImportExport.swift
TandaComposer/Setlist/SetlistActions+SpecialImport.swift
TandaComposer/Setlist/SpecialImportSession.swift
TandaComposer/Setlist/SpecialImportView.swift
TandaComposer/Tools/Checks/RescanCommands.swift
TandaComposer/Help/help_en.html
Tests/TandaCoreTests/SavedSetlist/SetlistMetadataExportTests.swift
Tests/TandaCoreTests/Import/SetlistJSONReaderTests.swift
```

### Suggested git commit

```
Release 0.8.7: Setlist JSON export/import and save header

- Save Set writes orchestraSource, singerSource, comment
- Export Current Setlist (JSON)… for sharing
- Import accepts Setlist JSON via Special Import (roles + hash)
- Help and tests updated
```
