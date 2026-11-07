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

// MARK: - Special import (M3U8 / text / JSON)

extension SetlistActions {

    // MARK: - Special Import

    /// Single Setlist import entry: M3U8, text list, or TandaComposer JSON.
    ///
    /// Parses the file and matches every line against the TrackLibrary.
    /// When every line is an exact path match, a short confirmation is
    /// enough and the Special Import window is skipped. Otherwise the
    /// window opens so non-exact lines can be assigned by hand. Nothing
    /// happens to the open Setlist until the user confirms.
    static func specialImport(
        session: SpecialImportSession,
        libraryStore: LibraryStore,
        setlistStore: SetlistStore,
        settings: AppSettings,
        openWindow: @escaping () -> Void
    ) {

        let panel =
            NSOpenPanel()

        panel.title =
            "Import Setlist"

        panel.message =
            "Choose a playlist, text file, or TandaComposer JSON."

        panel.allowedContentTypes =
            [
                UTType(filenameExtension: "m3u8"),
                UTType(filenameExtension: "m3u"),
                UTType.plainText,
                .json
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

            let tracks: [ImportedTrack]
            var sourceName: String
            var conventionNote: String?

            if fileExtension == "json" {

                let json =
                    try SetlistJSONReader.read(from: sourceURL)

                tracks = json.tracks
                sourceName = json.name
                conventionNote =
                    SetlistJSONReader.conventionNote(
                        orchestraSource: json.orchestraSource,
                        singerSource: json.singerSource,
                        ownOrchestra: settings.orchestraSource,
                        ownSinger: settings.singerSource
                    )

            } else {

                let isPlaylist =
                    fileExtension == "m3u8"
                    || fileExtension == "m3u"

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

                sourceName =
                    sourceURL
                        .deletingPathExtension()
                        .lastPathComponent

                conventionNote = nil
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

            if fileExtension != "json",
               let problem =
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

            let songs =
                libraryStore.songs

            let orchestraSource =
                settings.orchestraSource

            let singerSource =
                settings.singerSource

            let autoPickBestFile =
                settings.autoPickBestFile

            Task.detached(priority: .userInitiated) {

                let rows =
                    SpecialImportPlanner.makeRows(
                        tracks: tracks,
                        songs: songs,
                        orchestraSource: orchestraSource,
                        singerSource: singerSource,
                        autoPickBestFile: autoPickBestFile
                    )

                let allExact =
                    !rows.isEmpty
                    && rows.allSatisfy { $0.state == .matched }

                await MainActor.run {

                    session.beginWithPreparedRows(
                        sourceName: sourceName,
                        rows: rows,
                        conventionNote: conventionNote
                    )

                    if allExact {

                        let alert =
                            NSAlert()

                        alert.messageText =
                            "Create Setlist?"

                        let n =
                            rows.count

                        alert.informativeText =
                            n == 1
                            ? "1 track was found in your TrackLibrary by exact path. Create a new Setlist from it?"
                            : "\(n) tracks were found in your TrackLibrary by exact path. Create a new Setlist from them?"

                        alert.alertStyle =
                            .informational

                        alert.addButton(
                            withTitle:
                                "Create"
                        )

                        alert.addButton(
                            withTitle:
                                "Cancel"
                        )

                        let answer =
                            alert.runModal()

                        if answer == .alertFirstButtonReturn {

                            createSetlistFromSpecialImport(
                                session:
                                    session,
                                setlistStore:
                                    setlistStore,
                                libraryStore:
                                    libraryStore
                            )

                        } else {

                            session.reset()
                        }

                    } else {

                        openWindow()
                    }
                }
            }

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
            (try? setlistStore.listSetlistNames())
            ?? []

        let uniqueName =
            uniqueSetlistName(
                base:
                    session.sourceName,
                existingNames:
                    existing
            )

        do {

            setlistStore.newSetlist(
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
