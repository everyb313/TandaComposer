## Version 0.8.6 (Build 8) — 2026-11-07

### TandaLibrary share (JSON-ZIP)

**Export**
- Live path is only **Tools → Export → TandaLibrary (JSON-ZIP)…**
- One JSON file per Tanda, same Orchestra / Singer folders as in the TandaLibrary
- Records `orchestraSource` / `singerSource` so the importer can match by role
- Older Tanda files without that header get the sources added in the ZIP only; local files are not changed
- Text/M3U8 export (`exportForSharing`) is no longer in the menu (kept as dead code for now)

**Import**
- **Tools → Import → Tandas from ZIP…** targets JSON-ZIP exports
- Shows the sender’s Orchestra / Singer convention next to yours
- Matches by role (not by raw tag field) and by file hash when tags differ
- Legacy text/M3U8 ZIPs are still accepted by the parser
- Menu item and Import button are disabled while the Library is locked

### Setlist import simplified

- One menu item: **Tools → Import → Setlist from List or M3U8…**
- Accepts M3U8/M3U or a text list
- All tracks exact path match → short confirmation, then create Setlist
- Otherwise → Special Import window to pick tracks by hand
- Former **Setlist from M3U8 (file paths must fit)…** removed from the menu (`importSetlist` kept as dead code)

### Help

- `help_en.html` updated for JSON-ZIP only and the single Setlist import entry

### Files touched

```
TandaComposer/Tools/Checks/RescanCommands.swift
TandaComposer/TandaLibrary/TandaLibraryExportActions.swift
TandaComposer/TandaLibrary/TandaImportView.swift
TandaComposer/TandaLibrary/TandaImportSession.swift
TandaComposer/Setlist/SetlistActions+SpecialImport.swift
TandaComposer/Setlist/SpecialImportSession.swift
TandaComposer/Setlist/SetlistActions+ImportExport.swift
TandaComposer/Setlist/SpecialImportView.swift
TandaComposer/Help/help_en.html
```

### Suggested git commit

```
Release 0.8.6 (8): JSON-ZIP Tanda share, simplified Setlist import

- Keep only TandaLibrary (JSON-ZIP) in Export; text/M3U8 export dead
- Tanda import: convention note, lock when Library locked
- One Setlist import menu; exact matches confirm, else Special Import
- Help and UI strings aligned
```
