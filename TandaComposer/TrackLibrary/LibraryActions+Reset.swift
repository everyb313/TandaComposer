//
//  LibraryActions+Reset.swift
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

// MARK: - Clear & factory reset

extension LibraryActions {

    // MARK: - Clear Library

    static func clearLibrary(
        libraryStore: LibraryStore
    ) {

        guard
            !libraryStore.isLocked
        else {
            return
        }

        let alert =
            NSAlert()

        alert.messageText =
            "Clear \"\(libraryStore.currentLibraryName)\"?"

        alert.informativeText =
            "This removes all songs and Setlists from the " +
            "current library. This cannot be undone."

        alert.alertStyle =
            .warning

        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        guard
            alert.runModal() == .alertFirstButtonReturn
        else {
            return
        }

        do {

            try libraryStore.clearLibrary()

        } catch {

            presentError(error)
        }
    }


    // MARK: - Reset to Factory State

    static func resetToFactoryState(
        libraryStore: LibraryStore,
        setlistStore: SetlistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {

        let firstAlert =
            NSAlert()

        firstAlert.messageText =
            "Reset TandaComposer to Factory State?"

        firstAlert.informativeText =
            "This permanently deletes ALL internal libraries and " +
            "all Setlists inside them, and replaces them with a " +
            "single empty default library. This cannot be undone."

        firstAlert.alertStyle =
            .critical

        firstAlert.addButton(withTitle: "Continue")
        firstAlert.addButton(withTitle: "Cancel")

        guard
            firstAlert.runModal() == .alertFirstButtonReturn
        else {
            return
        }

        let confirmAlert =
            NSAlert()

        confirmAlert.messageText =
            "Are you absolutely sure?"

        confirmAlert.informativeText =
            "There is no way to undo this."

        confirmAlert.alertStyle =
            .critical

        confirmAlert.addButton(withTitle: "Yes, Delete Everything")
        confirmAlert.addButton(withTitle: "Cancel")

        guard
            confirmAlert.runModal() == .alertFirstButtonReturn
        else {
            return
        }

        do {

            try libraryStore.resetToFactoryState()

            finishLibrarySwitch(
                to: AppPaths.defaultLibraryName,
                settings: settings,
                smartlistStore: smartlistStore,
                setlistStore: setlistStore
            )

        } catch {

            presentError(error)
        }
    }
}
