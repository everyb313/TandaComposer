//
//  SetlistActions+ImportExport.swift
//
//  Copyright © 2026 Hagen Eckert.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//


import AppKit
import UniformTypeIdentifiers

// MARK: - Export & import

extension SetlistActions {

    // MARK: - Export Setlist

    static func exportSetlist(
        setlistStore: SetlistStore
    ) {

        guard
            !setlistStore.songs.isEmpty
        else {
            return
        }

        let panel =
            NSSavePanel()

        panel.title =
            "Export Setlist"

        panel.message =
            "Export the current Setlist."

        panel.nameFieldStringValue =
            setlistStore.name + ".m3u8"

        panel.allowedContentTypes =
            [
                UTType(
                    filenameExtension:
                        "m3u8"
                )!
            ]

        panel.canCreateDirectories =
            true

        panel.isExtensionHidden =
            false

        guard
            panel.runModal() == .OK,
            let selectedURL = panel.url
        else {
            return
        }

        // Make absolutely sure that the selected filename
        // has the required .m3u8 extension.

        var m3u8URL =
            selectedURL

        if
            m3u8URL.pathExtension.lowercased()
                != "m3u8"
        {

            m3u8URL.deletePathExtension()

            m3u8URL.appendPathExtension(
                "m3u8"
            )
        }

        do {

            // ---------------------------------------------------------
            // 1. Export the M3U8 playlist.
            // ---------------------------------------------------------

            try M3U8Exporter.export(
                songs:
                    setlistStore.songs,
                to:
                    m3u8URL,
                pathStyle:
                    .absolute,
                extended:
                    true
            )

            // ---------------------------------------------------------
            // 2. Create the metadata file beside the M3U8.
            //
            //    Example:
            //
            //    MySetlist.m3u8
            //    MySetlist.tanda.json
            //
            //    The user only selected the M3U8 file.
            //    The metadata file is created automatically.
            // ---------------------------------------------------------
/*
            let metadataURL =
                m3u8URL
                    .deletingPathExtension()
                    .appendingPathExtension(
                        "tanda.json"
                    )

            try SetlistMetadataExporter.export(
                songs:
                    setlistStore.songs,
                playlistName:
                    setlistStore.name,
                to:
                    metadataURL
            )
*/
        } catch {

            presentError(
                error
            )
        }
    }


    // MARK: - Import Setlist

    /// Imports an external or previously-exported `.m3u8` file as a
    /// brand-new Setlist.
    ///
    /// This always REPLACES what's currently on screen — there is
    /// only ever one active Setlist — so it goes through the same
    /// "save your current Setlist first?" prompt as Open Setlist,
    /// rather than silently discarding unsaved work.
    static func importSetlist(
        setlistStore: SetlistStore,
        libraryStore: LibraryStore,
        switchConfirmationCenter: SwitchConfirmationCenter
    ) {

        let panel =
            NSOpenPanel()

        panel.title =
            "Import Setlist"

        panel.message =
            "Choose an M3U8 playlist to import as a new Setlist."

        panel.allowedContentTypes =
            [
                UTType(
                    filenameExtension:
                        "m3u8"
                )!
            ]

        panel.allowsMultipleSelection =
            false

        panel.canChooseDirectories =
            false

        guard
            panel.runModal() == .OK,
            let sourceURL = panel.url
        else {
            return
        }

        // Nothing unsaved — import right away.
        if canSwitchWithoutAsking(setlistStore) {

            performImport(
                from:
                    sourceURL,
                setlistStore:
                    setlistStore,
                libraryStore:
                    libraryStore
            )

            return
        }

        let existing =
            (try? setlistStore.listPlaylistNames())
            ?? []

        switchConfirmationCenter.ask(
            kind:
                .playlist,
            suggestedName:
                setlistStore.name,
            existingNames:
                existing,
            onSave: { saveName in

                do {

                    try setlistStore.saveAs(
                        name:
                            saveName
                    )

                    performImport(
                        from:
                            sourceURL,
                        setlistStore:
                            setlistStore,
                        libraryStore:
                            libraryStore
                    )

                } catch {

                    presentError(
                        error
                    )
                }
            },
            onDiscard: {

                performImport(
                    from:
                        sourceURL,
                    setlistStore:
                        setlistStore,
                    libraryStore:
                        libraryStore
                )
            }
        )
    }


    /// Parses, resolves, and lands the result as a new Setlist. Shared
    /// by both branches of the save-before-switching prompt above.
    private static func performImport(
        from sourceURL: URL,
        setlistStore: SetlistStore,
        libraryStore: LibraryStore
    ) {

        do {

            let result =
                try M3U8Importer.importSongs(
                    from:
                        sourceURL,
                    songsByNormalizedPath:
                        libraryStore.songsByNormalizedPath
                )

            let baseName =
                sourceURL
                    .deletingPathExtension()
                    .lastPathComponent

            let existing =
                (try? setlistStore.listPlaylistNames())
                ?? []

            let uniqueName =
                uniqueSetlistName(
                    base:
                        baseName,
                    existingNames:
                        existing
                )

            setlistStore.newPlaylist(
                named:
                    uniqueName
            )

            setlistStore.add(
                result.resolvedSongs
            )

            try setlistStore.saveAs(
                name:
                    uniqueName,
                deleteOldName:
                    false
            )

            presentImportSummary(
                setlistName:
                    uniqueName,
                result:
                    result
            )

        } catch {

            presentError(
                error
            )
        }
    }


    /// `<base>`, then `<base> #2`, `<base> #3`, … — the first name not
    /// already used by a saved Setlist.
    static func uniqueSetlistName(
        base: String,
        existingNames: [String]
    ) -> String {

        guard
            existingNames.contains(
                base
            )
        else {
            return base
        }

        var suffix =
            2

        while
            existingNames.contains(
                "\(base) #\(suffix)"
            )
        {
            suffix += 1
        }

        return "\(base) #\(suffix)"
    }


    /// One summary alert — no per-line preview/apply step, since
    /// path-only resolution with no fallback leaves nothing for the
    /// user to decide: a line either resolved or it didn't.
    private static func presentImportSummary(
        setlistName: String,
        result: M3U8Importer.Result
    ) {

        let alert =
            NSAlert()

        alert.messageText =
            "Setlist \"\(setlistName)\" Imported"

        var lines: [String] =
            [
                "\(result.resolvedSongs.count) song(s) added."
            ]

        if !result.notInLibraryPaths.isEmpty {

            lines.append(
                "\(result.notInLibraryPaths.count) path(s) not found in the current TrackLibrary:"
            )

            lines.append(
                contentsOf:
                    result.notInLibraryPaths.prefix(20)
            )

            if result.notInLibraryPaths.count > 20 {
                lines.append(
                    "… and \(result.notInLibraryPaths.count - 20) more."
                )
            }
        }

        if !result.unreadableLines.isEmpty {

            lines.append(
                "\(result.unreadableLines.count) line(s) could not be read as file paths:"
            )

            lines.append(
                contentsOf:
                    result.unreadableLines.prefix(20)
            )

            if result.unreadableLines.count > 20 {
                lines.append(
                    "… and \(result.unreadableLines.count - 20) more."
                )
            }
        }

        alert.informativeText =
            lines.joined(
                separator:
                    "\n"
            )

        alert.alertStyle =
            (result.notInLibraryPaths.isEmpty && result.unreadableLines.isEmpty)
                ? .informational
                : .warning

        alert.addButton(
            withTitle:
                "OK"
        )

        alert.runModal()
    }
}
