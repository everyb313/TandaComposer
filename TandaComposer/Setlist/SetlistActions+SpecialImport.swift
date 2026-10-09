//
//  SetlistActions+SpecialImport.swift
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

// MARK: - Special import (M3U8, manual assignment)

extension SetlistActions {

    // MARK: - Special Import (M3U8, manual assignment)

    /// Manual intermediate stage next to the normal M3U8 import, which
    /// stays untouched. Parses the file, matches every line against the
    /// current TrackLibrary and opens the Special Import window, where
    /// non-exact lines are assigned by hand. Nothing happens to the open
    /// Setlist until "Create Setlist" is pressed there.
    static func specialImport(
        session: SpecialImportSession,
        libraryStore: LibraryStore,
        settings: AppSettings,
        openWindow: () -> Void
    ) {

        let panel =
            NSOpenPanel()

        panel.title =
            "Import Setlist (Pick Tracks)"

        panel.message =
            "Choose an M3U8 playlist or a text file with one track per line (with or without path or file suffix). Tracks without an exact path match can be picked manually."

        panel.allowedContentTypes =
            [
                UTType(filenameExtension: "m3u8"),
                UTType(filenameExtension: "m3u"),
                UTType.plainText
            ]
            .compactMap { $0 }

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

        do {

            let fileExtension =
                sourceURL.pathExtension.lowercased()

            let isPlaylist =
                fileExtension == "m3u8"
                || fileExtension == "m3u"

            let tracks: [ImportedTrack]

            if isPlaylist {

                tracks =
                    try M3U8Importer.importTracks(
                        from:
                            sourceURL
                    )

            } else {

                tracks =
                    try TextListImporter.importTracks(
                        from:
                            sourceURL
                    )
            }

            guard !tracks.isEmpty else {

                let alert =
                    NSAlert()

                alert.messageText =
                    "Nothing to Import"

                alert.informativeText =
                    "The file contains no usable track entries."

                alert.alertStyle =
                    .informational

                alert.runModal()

                return
            }

            if let problem =
                TracklibImportReferenceStore.loadProblem
            {
                let warning =
                    NSAlert()

                warning.messageText =
                    "Name List Unavailable"

                warning.informativeText =
                    "Orchestra and singer names cannot be recognized, so matching is less precise.\n\n\(problem)"

                warning.alertStyle =
                    .warning

                warning.runModal()
            }

            session.begin(
                sourceURL:
                    sourceURL,
                tracks:
                    tracks,
                songs:
                    libraryStore.songs,
                settings:
                    settings
            )

            openWindow()

        } catch {

            presentError(
                error
            )
        }
    }


    /// Lands the adopted Library songs of a Special Import as a new,
    /// saved Setlist. Same save-before-replacing question as New
    /// Setlist; returns false when nothing was created (cancelled,
    /// nothing adopted, or an error).
    @discardableResult
    static func createSetlistFromSpecialImport(
        session: SpecialImportSession,
        setlistStore: SetlistStore,
        libraryStore: LibraryStore
    ) -> Bool {

        let songs =
            session.adoptedSongs

        guard !songs.isEmpty else {
            return false
        }

        if !canSwitchWithoutAsking(setlistStore) {

            let saveAlert =
                NSAlert()

            saveAlert.messageText =
                "Save Setlist"

            saveAlert.informativeText =
                "Save \"\(setlistStore.name)\" before creating the imported Setlist?"

            saveAlert.alertStyle =
                .informational

            saveAlert.addButton(
                withTitle:
                    "Save"
            )

            saveAlert.addButton(
                withTitle:
                    "Cancel"
            )

            let dontSaveButton =
                saveAlert.addButton(
                    withTitle:
                        "Don't Save"
                )

            dontSaveButton.hasDestructiveAction =
                true

            switch saveAlert.runModal() {

            case .alertFirstButtonReturn:

                do {

                    try setlistStore.save()

                } catch {

                    presentError(
                        error
                    )

                    return false
                }

            case .alertThirdButtonReturn:

                break

            default:

                return false
            }
        }

        let existing =
            (try? setlistStore.listPlaylistNames())
            ?? []

        let uniqueName =
            uniqueSetlistName(
                base:
                    session.sourceName,
                existingNames:
                    existing
            )

        do {

            setlistStore.newPlaylist(
                named:
                    uniqueName
            )

            setlistStore.add(
                songs
            )

            try setlistStore.saveAs(
                name:
                    uniqueName,
                deleteOldName:
                    false
            )

        } catch {

            presentError(
                error
            )

            return false
        }

        setlistStore.resolveAgainstLibrary(
            byID:
                libraryStore.songsByID,
            byPath:
                libraryStore.songsByNormalizedPath,
            missingSongIDs:
                libraryStore.missingSongIDs
        )

        let left =
            session.count(of: .open)
            + session.count(of: .skipped)

        let alert =
            NSAlert()

        alert.messageText =
            "Setlist \"\(uniqueName)\" Created"

        alert.informativeText =
            left == 0
            ? "\(songs.count) song(s) added."
            : "\(songs.count) song(s) added, \(left) track(s) left out (open or skipped)."

        alert.alertStyle =
            .informational

        alert.addButton(
            withTitle:
                "OK"
        )

        alert.runModal()

        session.reset()

        return true
    }
}
