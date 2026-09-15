//
//  PlaylistActions.swift
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

/// Orchestrates Playlist-level actions (New / Open / Delete / Export).
/// Kept separate from LibraryActions since a Setlist lives
/// inside the active Library but is persisted independently.
enum PlaylistActions {

    // MARK: - New Playlist

    /// Creates a new empty Setlist.
    ///
    /// Offers to save the current Setlist first ("Save"), to discard
    /// it and create the new one anyway ("Don't Save"), or to abort
    /// the whole thing ("Cancel") — matching the Don't Save/Cancel/
    /// Save pattern used elsewhere in the app (e.g. New TrackLibrary,
    /// Open Setlist), which this older, separate NSAlert-based flow
    /// was previously missing a "Don't Save" option for.
    static func newPlaylist(
        playlistStore: PlaylistStore
    ) {

        let saveAlert =
            NSAlert()

        saveAlert.messageText =
            "Save Setlist"

        saveAlert.informativeText =
            "Save \"\(playlistStore.name)\" before creating a new Setlist?"

        saveAlert.alertStyle =
            .informational

        // Button order matters for NSAlert: the first one added
        // becomes the rightmost/default button. Adding Save, then
        // Cancel, then Don't Save produces the standard left-to-right
        // reading order "Don't Save | Cancel | Save".
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

            // -----------------------------------------------------
            // Save the current Setlist under its current name.
            //
            // No name change happens here.
            // -----------------------------------------------------

            do {

                try playlistStore.save()

            } catch {

                presentError(
                    error
                )

                return
            }

        case .alertThirdButtonReturn:

            // Don't Save — discard the current Setlist's unsaved
            // state and fall straight through to naming the new one.
            break

        default:

            // Cancel — abort the whole "New Setlist" action.
            return
        }

        // -------------------------------------------------------------
        // Now ask for the name of the NEW Setlist.
        // -------------------------------------------------------------

        promptForNewPlaylistName(
            playlistStore:
                playlistStore
        )
    }


    private static func promptForNewPlaylistName(
        playlistStore: PlaylistStore
    ) {

        while true {

            let alert =
                NSAlert()

            alert.messageText =
                "New Setlist"

            alert.informativeText =
                "Name for the new, empty Setlist."

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

            let textField =
                NSTextField(
                    frame:
                        NSRect(
                            x: 0,
                            y: 0,
                            width: 260,
                            height: 24
                        )
                )

            textField.stringValue =
                "Untitled Set"

            alert.accessoryView =
                textField

            alert.window.initialFirstResponder =
                textField

            guard
                alert.runModal()
                    == .alertFirstButtonReturn
            else {
                return
            }

            let newName =
                textField.stringValue
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

            guard
                !newName.isEmpty
            else {
                continue
            }

            let existing =
                (try? playlistStore.listPlaylistNames())
                ?? []

            if existing.contains(newName) {

                let overwriteAlert =
                    NSAlert()

                overwriteAlert.messageText =
                    "Name Already Used"

                overwriteAlert.informativeText =
                    "A Setlist named \"\(newName)\" already exists. " +
                    "Choose a different name."

                overwriteAlert.alertStyle =
                    .warning

                overwriteAlert.addButton(
                    withTitle:
                        "OK"
                )

                overwriteAlert.runModal()

                continue
            }

            // ---------------------------------------------------------
            // Create the NEW empty Setlist.
            // ---------------------------------------------------------

            playlistStore.newPlaylist(
                named:
                    newName
            )

            return
        }
    }


    // MARK: - Open Playlist

    static func openPlaylist(
        named targetName: String,
        playlistStore: PlaylistStore,
        switchConfirmationCenter: SwitchConfirmationCenter
    ) {

        guard
            targetName != playlistStore.name
        else {
            return
        }

        let existing =
            (try? playlistStore.listPlaylistNames())
            ?? []

        switchConfirmationCenter.ask(
            kind:
                .playlist,
            suggestedName:
                playlistStore.name,
            existingNames:
                existing,
            onSave: { saveName in

                do {

                    // -------------------------------------------------
                    // Save the current Setlist.
                    //
                    // A changed name is treated as a rename.
                    // -------------------------------------------------

                    try playlistStore.saveAs(
                        name:
                            saveName
                    )

                    // -------------------------------------------------
                    // Then open the requested Setlist.
                    // -------------------------------------------------

                    try playlistStore.load(
                        playlistName:
                            targetName
                    )

                } catch {

                    presentError(
                        error
                    )
                }
            },
            onDiscard: {

                do {

                    try playlistStore.load(
                        playlistName:
                            targetName
                    )

                } catch {

                    presentError(
                        error
                    )
                }
            }
        )
    }


    // MARK: - Delete Setlist

    static func deletePlaylist(
        named targetName: String,
        playlistStore: PlaylistStore
    ) {

        // The currently active Setlist must never be deleted.
        guard
            targetName != playlistStore.name
        else {
            return
        }

        let alert =
            NSAlert()

        alert.messageText =
            "Delete Setlist?"

        alert.informativeText =
            "The Setlist \"\(targetName)\" will be permanently deleted."

        alert.alertStyle =
            .warning

        alert.addButton(
            withTitle:
                "Delete"
        )

        alert.addButton(
            withTitle:
                "Cancel"
        )

        let response =
            alert.runModal()

        guard
            response ==
                .alertFirstButtonReturn
        else {
            return
        }

        do {

            try playlistStore.delete(
                playlistName:
                    targetName
            )

        } catch {

            presentError(
                error
            )
        }
    }


    // MARK: - Export Setlist

    static func exportSetlist(
        playlistStore: PlaylistStore
    ) {

        guard
            !playlistStore.songs.isEmpty
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
            playlistStore.name + ".m3u8"

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
                    playlistStore.songs,
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

            let metadataURL =
                m3u8URL
                    .deletingPathExtension()
                    .appendingPathExtension(
                        "tanda.json"
                    )

            try SetlistMetadataExporter.export(
                songs:
                    playlistStore.songs,
                playlistName:
                    playlistStore.name,
                to:
                    metadataURL
            )

        } catch {

            presentError(
                error
            )
        }
    }


    // MARK: - Error Presentation

    private static func presentError(
        _ error: Error
    ) {

        let alert =
            NSAlert()

        alert.messageText =
            "Something went wrong"

        alert.informativeText =
            error.localizedDescription

        alert.alertStyle =
            .warning

        alert.runModal()
    }
}

