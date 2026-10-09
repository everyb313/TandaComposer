//
//  LibraryActions+StartupRecovery.swift
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

// MARK: - Startup error recovery

extension LibraryActions {

    // MARK: - Startup Library Error Recovery

    /// Shown once at launch when the TrackLibrary active at last quit
    /// could not be opened (missing or corrupted `.sqlite` file) — see
    /// `AppEnvironment.init()` / `LibraryStore.startupLibraryError`.
    /// TandaComposer is running on a temporary in-memory database at
    /// this point; this lets the user open a different existing
    /// Library or create a new one right away, instead of being stuck
    /// with no valid Library and no obvious way out other than editing
    /// files on disk.
    static func recoverFromStartupLibraryError(
        failedLibraryName: String,
        libraryStore: LibraryStore,
        setlistStore: SetlistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {

        let alert =
            NSAlert()

        alert.messageText =
            "Library \"\(failedLibraryName)\" Could Not Be Opened"

        alert.informativeText =
            "Its file is missing or corrupted. TandaComposer is " +
            "currently running with a temporary, empty library " +
            "that will not be saved. Choose a different library, " +
            "or create a new one."

        alert.alertStyle =
            .warning

        alert.addButton(withTitle: "Choose Existing Library…")
        alert.addButton(withTitle: "New Library…")
        alert.addButton(withTitle: "Continue Without Saving")

        let response =
            alert.runModal()

        switch response {

        case .alertFirstButtonReturn:

            chooseExistingLibraryAfterStartupFailure(
                excluding: failedLibraryName,
                libraryStore: libraryStore,
                setlistStore: setlistStore,
                smartlistStore: smartlistStore,
                settings: settings
            )

        case .alertSecondButtonReturn:

            promptForNewLibraryName(
                libraryStore: libraryStore,
                setlistStore: setlistStore,
                smartlistStore: smartlistStore,
                settings: settings
            )

        default:

            // "Continue Without Saving" — leave the temporary
            // in-memory library in place. The user can still reach
            // Library ▸ Open/New TrackLibrary later from the menu
            // (after unlocking) if they change their mind.
            break
        }

        libraryStore.startupLibraryError = nil
    }


    /// Lets the user pick one of the OTHER existing internal
    /// Libraries to open, after a startup failure. A simple
    /// NSPopUpButton accessory view rather than a full picker window —
    /// this is a one-off recovery dialog, not a regular workflow.
    private static func chooseExistingLibraryAfterStartupFailure(
        excluding failedLibraryName: String,
        libraryStore: LibraryStore,
        setlistStore: SetlistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {

        let names =
            ((try? libraryStore.listInternalLibraries()) ?? [])
                .filter { $0 != failedLibraryName }

        guard
            !names.isEmpty
        else {

            let noneAlert =
                NSAlert()

            noneAlert.messageText =
                "No Other Libraries Found"

            noneAlert.informativeText =
                "There are no other internal libraries to switch " +
                "to. Create a new one instead."

            noneAlert.alertStyle =
                .warning

            noneAlert.addButton(withTitle: "OK")

            noneAlert.runModal()

            return
        }

        let alert =
            NSAlert()

        alert.messageText =
            "Choose a Library"

        alert.informativeText =
            "Select the library to open."

        alert.alertStyle =
            .informational

        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let popup =
            NSPopUpButton(
                frame: NSRect(x: 0, y: 0, width: 260, height: 26)
            )

        popup.addItems(withTitles: names)

        alert.accessoryView =
            popup

        guard
            alert.runModal() == .alertFirstButtonReturn,
            let selectedName = popup.titleOfSelectedItem
        else {
            return
        }

        do {

            try libraryStore.loadInternalLibrary(named: selectedName)

            finishLibrarySwitch(
                to: selectedName,
                settings: settings,
                smartlistStore: smartlistStore,
                setlistStore: setlistStore
            )

        } catch {

            presentError(error)
        }
    }
}
