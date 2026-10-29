//
//  LibraryActions+Lifecycle.swift
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

// MARK: - Library lifecycle (new / open / save / delete)

extension LibraryActions {

    // MARK: - New Library

    /// If the current Library is unlocked, save its current contents
    /// first. If it is locked, skip saving because it cannot have pending
    /// edits. Then ask for a name and create a fresh empty Library.
    static func newLibrary(
        libraryStore: LibraryStore,
        setlistStore: SetlistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {

        // A locked library cannot have pending edits, so creating a new
        // library does not require unlocking or exporting the old one.
        // Preserve the existing save-before-switch behavior when unlocked.
        if !libraryStore.isLocked {
            do {
                try libraryStore.exportLibrary(
                    to: libraryStore.currentLibraryPath
                )
            } catch {
                presentError(error)
                return
            }
        }

        promptForNewLibraryName(
            libraryStore: libraryStore,
            setlistStore: setlistStore,
            smartlistStore: smartlistStore,
            settings: settings
        )
    }


    static func promptForNewLibraryName(
        libraryStore: LibraryStore,
        setlistStore: SetlistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {

        while true {

            let alert =
                NSAlert()

            alert.messageText =
                "New TrackLibrary"

            alert.informativeText =
                "Name for the new, empty Library."

            alert.alertStyle =
                .informational

            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            let textField =
                NSTextField(
                    frame: NSRect(x: 0, y: 0, width: 260, height: 24)
                )

            textField.stringValue =
                "NewLibrary"

            alert.accessoryView =
                textField

            alert.window.initialFirstResponder =
                textField

            guard
                alert.runModal() == .alertFirstButtonReturn
            else {
                return
            }

            let name =
                textField.stringValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                !name.isEmpty
            else {
                continue
            }

            let existing =
                (try? libraryStore.listInternalLibraries()) ?? []

            if existing.contains(name) {

                let errorAlert =
                    NSAlert()

                errorAlert.messageText =
                    "Name Already Used"

                errorAlert.informativeText =
                    "A library named \"\(name)\" already exists " +
                    "internally. Choose a different name."

                errorAlert.alertStyle =
                    .warning

                errorAlert.addButton(withTitle: "OK")

                errorAlert.runModal()

                continue
            }

            do {

                try libraryStore.newLibrary(named: name)

                finishLibrarySwitch(
                    to: name,
                    settings: settings,
                    smartlistStore: smartlistStore,
                    setlistStore: setlistStore
                )

            } catch {

                presentError(error)
            }

            return
        }
    }


    static func renameCurrentLibrary(
        libraryStore: LibraryStore,
        setlistStore: SetlistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {
        guard !libraryStore.isLocked else { return }

        // Protect unsaved Setlist changes before starting the rename.
        guard !setlistStore.hasUnsavedChanges else {
            let unsavedAlert = NSAlert()
            unsavedAlert.messageText = "Cannot Rename TrackLibrary"
            unsavedAlert.informativeText =
                "The current Setlist has unsaved changes. " +
                "Please save or discard those changes before renaming the TrackLibrary."
            unsavedAlert.alertStyle = .warning
            unsavedAlert.addButton(withTitle: "OK")
            unsavedAlert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Rename TrackLibrary"
        alert.informativeText =
            "Rename the active TrackLibrary and update its saved Tanda " +
            "and Setlist JSON references. Track files and track metadata " +
            "will not be changed."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 300, height: 24)
        )
        textField.stringValue = libraryStore.currentLibraryName
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let newName = textField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !newName.isEmpty,
              newName != libraryStore.currentLibraryName else {
            return
        }

        // Recheck before modifying files in case the state changed.
        guard !setlistStore.hasUnsavedChanges else {
            let unsavedAlert = NSAlert()
            unsavedAlert.messageText = "Cannot Rename TrackLibrary"
            unsavedAlert.informativeText =
                "The current Setlist has unsaved changes. " +
                "Please save or discard those changes before renaming the TrackLibrary."
            unsavedAlert.alertStyle = .warning
            unsavedAlert.addButton(withTitle: "OK")
            unsavedAlert.runModal()
            return
        }

        do {
            try libraryStore.renameCurrentLibrary(to: newName)

            finishLibrarySwitch(
                to: newName,
                settings: settings,
                smartlistStore: smartlistStore,
                setlistStore: setlistStore
            )
        } catch {
            presentError(error)
        }
    }


    // MARK: - Open (Internal) Library

    static func openLibrary(
        named name: String,
        libraryStore: LibraryStore,
        switchConfirmationCenter: SwitchConfirmationCenter,
        setlistStore: SetlistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {

        guard
            name != libraryStore.currentLibraryName
        else {
            return
        }

        // Shared by every successful switch path — persist the new
        // active name and reload stores scoped to this library.
        func finishSwitch() {

            finishLibrarySwitch(
                to: name,
                settings: settings,
                smartlistStore: smartlistStore,
                setlistStore: setlistStore
            )
        }

        // A locked library cannot have been edited through the UI.
        // Switch directly without asking to save/discard it.
        if libraryStore.isLocked {
            do {
                try libraryStore.loadInternalLibrary(named: name)
                finishSwitch()
            } catch {
                presentError(error)
            }
            return
        }

        let existing =
            (try? libraryStore.listInternalLibraries()) ?? []

        // For an unlocked library, preserve the existing save/discard
        // confirmation flow before switching.
        switchConfirmationCenter.ask(
            kind: .library,
            suggestedName: libraryStore.currentLibraryName,
            existingNames: existing,
            onSave: { saveName in

                do {

                    try libraryStore.exportLibrary(
                        to: AppPaths.libraryFile(named: saveName).path
                    )

                    try libraryStore.loadInternalLibrary(named: name)

                    finishSwitch()

                } catch {

                    presentError(error)
                }
            },
            onDiscard: {

                do {

                    try libraryStore.loadInternalLibrary(named: name)

                    finishSwitch()

                } catch {

                    presentError(error)
                }
            }
        )
    }


    // MARK: - Save Library Locally

    /// Saves an internal snapshot copy of the current Library under
    /// a (possibly different, editable) name — purely internal, no
    /// external file panel. If the name matches the currently active
    /// Library, `exportLibrary` itself reports that it's already
    /// saved there (nothing to do).
    static func saveLibraryLocally(
        libraryStore: LibraryStore
    ) {

        let alert =
            NSAlert()

        alert.messageText =
            "Save Library"

        alert.informativeText =
            "Save the current Library internally under this name."

        alert.alertStyle =
            .informational

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField =
            NSTextField(
                frame: NSRect(x: 0, y: 0, width: 260, height: 24)
            )

        textField.stringValue =
            libraryStore.currentLibraryName

        alert.accessoryView =
            textField

        alert.window.initialFirstResponder =
            textField

        guard
            alert.runModal() == .alertFirstButtonReturn
        else {
            return
        }

        let name =
            textField.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            !name.isEmpty
        else {
            return
        }

        let existing =
            (try? libraryStore.listInternalLibraries()) ?? []

        if existing.contains(name),
           name != libraryStore.currentLibraryName {

            let overwriteAlert =
                NSAlert()

            overwriteAlert.messageText =
                "Overwrite \"\(name)\"?"

            overwriteAlert.informativeText =
                "A library named \"\(name)\" already exists " +
                "internally and will be overwritten."

            overwriteAlert.alertStyle =
                .warning

            overwriteAlert.addButton(withTitle: "Overwrite")
            overwriteAlert.addButton(withTitle: "Cancel")

            guard
                overwriteAlert.runModal() == .alertFirstButtonReturn
            else {
                return
            }
        }

        do {

            try libraryStore.exportLibrary(
                to: AppPaths.libraryFile(named: name).path
            )

        } catch {

            presentError(error)
        }
    }


    // MARK: - Delete Library

    static func deleteLibrary(
        named name: String,
        libraryStore: LibraryStore
    ) {

        guard
            name != libraryStore.currentLibraryName
        else {
            return
        }

        let alert =
            NSAlert()

        alert.messageText =
            "Delete \"\(name)\"?"

        alert.informativeText =
            "This permanently deletes the library \"\(name)\" " +
            "and everything in it (songs and Setlists). " +
            "This cannot be undone."

        alert.alertStyle =
            .warning

        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard
            alert.runModal() == .alertFirstButtonReturn
        else {
            return
        }

        do {

            try libraryStore.deleteInternalLibrary(named: name)

        } catch {

            presentError(error)
        }
    }
}
