//
//  SmartlistActions.swift
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

enum SmartlistActions {

    // MARK: - Export

    static func exportAll(
        store: SmartlistStore
    ) {

        let panel =
            NSSavePanel()

        panel.title =
            "Export Smartlists"

        panel.message = """
            Saves the complete Smartlist tree as a ZIP file. If the \
            name is already taken, the number is counted up \
            (Smartlists_2.zip, …).
            """

        panel.allowedContentTypes =
            [.zip]

        panel.canCreateDirectories =
            true

        panel.isExtensionHidden =
            false

        if let folder = lastZipFolder() {

            panel.directoryURL = folder

            panel.nameFieldStringValue =
                SmartlistZip.firstFreeURL(
                    for:
                        folder.appendingPathComponent("Smartlists.zip")
                )
                .lastPathComponent

        } else {

            panel.nameFieldStringValue =
                "Smartlists.zip"
        }

        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }

        // Never overwrite: a name that is already taken gets the next
        // free number.
        let destination =
            SmartlistZip.firstFreeURL(for: url)

        do {

            try SmartlistZip.export(
                copyTree: { try store.exportAll(to: $0) },
                to: destination
            )

            rememberZipFolder(of: destination)

        } catch {

            presentError(error)
        }
    }

    private static let zipFolderDefaultsKey =
        "SmartlistZipLastFolder"

    /// The folder of the last ZIP export/import, if it still exists.
    /// Not set on the first use, so the system does not ask for access
    /// to a folder the user never chose.
    private static func lastZipFolder() -> URL? {

        guard
            let path = UserDefaults.standard.string(
                forKey: zipFolderDefaultsKey
            ),
            FileManager.default.fileExists(atPath: path)
        else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func rememberZipFolder(of url: URL) {

        UserDefaults.standard.set(
            url.deletingLastPathComponent().path,
            forKey: zipFolderDefaultsKey
        )
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
            "Import Smartlists"

        panel.message = """
            Choose a ZIP file made by Export → Smartlists (ZIP)… \
            (a folder from an older export also works).
            Its contents are copied into an internal \
            "Imported" folder,
            which you can then sort \
            into your own structure.
            """

        panel.canChooseFiles =
            true

        panel.allowedContentTypes =
            [.zip]

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

            var isDirectory: ObjCBool = false

            FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            )

            if isDirectory.boolValue {

                // An older export: a plain folder.
                try store.importAll(from: url)

            } else {

                // The ZIP is checked before anything is replaced.
                try SmartlistZip.importTree(from: url) {
                    try store.importAll(from: $0)
                }

                rememberZipFolder(of: url)
            }

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
