//
//  SmartPlaylistActions.swift
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

enum SmartlistActions {

    // MARK: - Export

    static func exportAll(
        store: SmartlistStore
    ) {

        let panel =
            NSSavePanel()

        panel.title =
            "Export Smartlists"

        panel.message =
            "Export the complete Smartlist tree."

        panel.nameFieldStringValue =
            "Smartlists"

        panel.canCreateDirectories =
            true

        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }

        do {

            try store.exportAll(to: url)

        } catch {

            presentError(error)
        }
    }


    // MARK: - Import

    static func importAll(
        store: SmartlistStore
    ) {

        guard
            !store.isLocked
        else {
            return
        }

        let panel =
            NSOpenPanel()

        panel.title =
            "Import Smart Playlists"

        panel.message =
            "Choose a folder of Smartlists to import. " +
            "Its contents are copied into an internal " +
            "\"Imported\" folder, which you can then sort " +
            "into your own structure."

        panel.canChooseFiles =
            false

        panel.canChooseDirectories =
            true

        panel.allowsMultipleSelection =
            false

        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }

        if store.importedFolderExists {

            let alert =
                NSAlert()

            alert.messageText =
                "Overwrite \"Imported\"?"

            alert.informativeText =
                "The internal \"Imported\" folder already has " +
                "content. It will be completely replaced with " +
                "what's being imported now. Anything you've " +
                "already moved out of \"Imported\" elsewhere in " +
                "the tree is not affected."

            alert.alertStyle =
                .warning

            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Cancel")

            guard
                alert.runModal() == .alertFirstButtonReturn
            else {
                return
            }
        }

        do {

            try store.importAll(from: url)

        } catch {

            presentError(error)
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
