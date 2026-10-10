//
//  SetlistActions+Lifecycle.swift
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

// MARK: - Setlist lifecycle (new / open / switch / restore / delete)

extension SetlistActions {

    // MARK: - New Setlist

    /// Creates a new empty Setlist.
    ///
    /// Offers to save the current Setlist first ("Save"), to discard
    /// it and create the new one anyway ("Don't Save"), or to abort
    /// the whole thing ("Cancel") — matching the Don't Save/Cancel/
    /// Save pattern used elsewhere in the app (e.g. New TrackLibrary,
    /// Open Setlist), which this older, separate NSAlert-based flow
    /// was previously missing a "Don't Save" option for.
    static func newPlaylist(
        setlistStore: SetlistStore
    ) {

        // Nothing unsaved — no question, straight to naming the new one.
        if canSwitchWithoutAsking(setlistStore) {

            promptForNewPlaylistName(
                setlistStore:
                    setlistStore
            )

            return
        }

        let saveAlert =
            NSAlert()

        saveAlert.messageText =
            "Save Setlist"

        saveAlert.informativeText =
            "Save \"\(setlistStore.name)\" before creating a new Setlist?"

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

                try setlistStore.save()

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
            setlistStore:
                setlistStore
        )
    }


    private static func promptForNewPlaylistName(
        setlistStore: SetlistStore
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
                (try? setlistStore.listPlaylistNames())
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

            setlistStore.newPlaylist(
                named:
                    newName
            )

            return
        }
    }


    // MARK: - Open Setlist

    static func openPlaylist(
        named targetName: String,
        setlistStore: SetlistStore,
        switchConfirmationCenter: SwitchConfirmationCenter
    ) {

        guard
            targetName != setlistStore.name
        else {
            return
        }

        // Nothing unsaved — open the requested Setlist right away.
        if canSwitchWithoutAsking(setlistStore) {

            do {

                try setlistStore.load(
                    playlistName:
                        targetName
                )

            } catch {

                presentError(
                    error
                )
            }

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

                    // -------------------------------------------------
                    // Save the current Setlist.
                    //
                    // A changed name is treated as a rename.
                    // -------------------------------------------------

                    try setlistStore.saveAs(
                        name:
                            saveName
                    )

                    // -------------------------------------------------
                    // Then open the requested Setlist.
                    // -------------------------------------------------

                    try setlistStore.load(
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

                    try setlistStore.load(
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


    // MARK: - Switching Without Unsaved Edits

    /// True when the open Setlist has no unsaved edits, so the
    /// Save / Don't Save question can be skipped. If the Setlist is
    /// already on disk, SetlistView shows its short "Saved" badge as
    /// feedback.
    static func canSwitchWithoutAsking(
        _ setlistStore: SetlistStore
    ) -> Bool {

        guard !setlistStore.hasUnsavedChanges else {
            return false
        }

        if setlistStore.isSavedAndUnchanged {
            setlistStore.announceAlreadySaved()
        }

        return true
    }


    // MARK: - Restore Unsaved Edits (App Start)

    /// Asked at start-up when the last session ended with unsaved
    /// edits. Returns true for "Restore", false for "Discard".
    static func askToRestoreUnsavedEdits(
        _ info: SetlistStore.RecoveryInfo
    ) -> Bool {

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var text =
            "TandaComposer was closed with unsaved changes to "
            + "\"\(info.name)\" (\(info.songCount) songs, last change "
            + "\(formatter.string(from: info.savedAt)))."

        if let savedCount = info.savedFileSongCount {

            text += " The saved version has \(savedCount) songs."

        } else {

            text += " This Setlist has not been saved yet."
        }

        if info.savedFileIsNewer {

            text += "\n\nNote: the saved file was changed after these edits."
        }

        text += "\n\nRestoring leaves the saved file as it is until you save."

        let alert = NSAlert()

        alert.messageText = "Restore unsaved changes?"
        alert.informativeText = text
        alert.alertStyle = .informational

        alert.addButton(withTitle: "Restore")

        let discardButton =
            alert.addButton(withTitle: "Discard")

        discardButton.hasDestructiveAction = true

        return alert.runModal() == .alertFirstButtonReturn
    }


    // MARK: - Delete Setlist

    static func deletePlaylist(
        named targetName: String,
        setlistStore: SetlistStore
    ) {

        // The currently active Setlist must never be deleted.
        guard
            targetName != setlistStore.name
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

            try setlistStore.delete(
                playlistName:
                    targetName
            )

        } catch {

            presentError(
                error
            )
        }
    }
}
