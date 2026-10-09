//
//  TrackLibraryActions.swift
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

/// Orchestrates Library-level actions (New / Open / Export / Import /
/// Clear / Reset). Used by both the toolbar button in
/// SmartListFilteredLibraryView and the "Library" menu, so the
/// logic lives here once instead of twice.
enum LibraryActions {

    // Actions are grouped by responsibility in extensions:
    //   LibraryActions+Lifecycle.swift        new / open / save / delete
    //   LibraryActions+Reset.swift            clear / reset to factory state
    //   LibraryActions+Backup.swift           export / import backup (zip)
    //   LibraryActions+StartupRecovery.swift  recovery when startup open fails

    // MARK: - Library Switch

    /// Shared tail of every action that ends up with a different
    /// active Library (new / open / factory reset / startup recovery):
    /// persist the new active name to AppSettings.json, reload the
    /// stores that are scoped to the per-Library subtree
    /// (Smartlists / Setlists directly here; Tandas and the saved-
    /// Setlist viewer are ContentView-local, reached via the
    /// notification).
    static func finishLibrarySwitch(
        to name: String,
        settings: AppSettings,
        smartlistStore: SmartlistStore,
        setlistStore: SetlistStore
    ) {

        settings.currentLibraryName =
            name

        settings.save()

        smartlistStore.reload()
        setlistStore.refreshAfterExternalDataChange()

        NotificationCenter.default.post(
            name: AppNotification.tandaComposerLibrarySwitched,
            object: nil
        )
    }


    // MARK: - Error Presentation

    static func presentError(
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
