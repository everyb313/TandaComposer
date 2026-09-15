//
//  LibraryActions.swift
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

/// Orchestrates Library-level actions (New / Open / Export / Import /
/// Clear / Reset). Used by both the toolbar button in
/// SmartListFilteredLibraryView and the "Library" menu, so the
/// logic lives here once instead of twice.
enum LibraryActions {

    // MARK: - New Library

    /// Saves the current Library under its own name first (nothing
    /// discarded — the old Library stays exactly where it is), then
    /// asks for a name and creates a fresh empty Library under it.
    static func newLibrary(
        libraryStore: LibraryStore,
        playlistStore: PlaylistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {

        guard
            !libraryStore.isLocked
        else {
            return
        }

        do {

            try libraryStore.exportLibrary(
                to: libraryStore.currentLibraryPath
            )

        } catch {

            presentError(error)
            return
        }

        promptForNewLibraryName(
            libraryStore: libraryStore,
            playlistStore: playlistStore,
            smartlistStore: smartlistStore,
            settings: settings
        )
    }


    private static func promptForNewLibraryName(
        libraryStore: LibraryStore,
        playlistStore: PlaylistStore,
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

                settings.currentLibraryName = name
                settings.save()

                smartlistStore.reload()
                playlistStore.refreshAfterExternalDataChange()

                NotificationCenter.default.post(
                    name: .tandaComposerLibrarySwitched,
                    object: nil
                )

            } catch {

                presentError(error)
            }

            return
        }
    }


    // MARK: - Open (Internal) Library

    static func openLibrary(
        named name: String,
        libraryStore: LibraryStore,
        switchConfirmationCenter: SwitchConfirmationCenter,
        playlistStore: PlaylistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {

        guard
            !libraryStore.isLocked,
            name != libraryStore.currentLibraryName
        else {
            return
        }

        let existing =
            (try? libraryStore.listInternalLibraries()) ?? []

        // Shared by both onSave/onDiscard below — everything a
        // successful switch needs beyond LibraryStore itself:
        // persist the new active name to AppSettings.json, and
        // reload the stores that are now scoped to a different
        // per-TrackLibrary subtree (Setlists/Smartlists directly
        // here; Tandas and the saved-Setlist viewer are
        // ContentView-local, reached via the notification).
        func finishSwitch() {

            settings.currentLibraryName = name
            settings.save()

            smartlistStore.reload()
            playlistStore.refreshAfterExternalDataChange()

            NotificationCenter.default.post(
                name: .tandaComposerLibrarySwitched,
                object: nil
            )
        }

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
            "and everything in it (songs and playlists). " +
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
            "This removes all songs and playlists from the " +
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

            try libraryStore.clearLibraryCompletely()

        } catch {

            presentError(error)
        }
    }


    // MARK: - Reset to Factory State

    static func resetToFactoryState(
        libraryStore: LibraryStore,
        playlistStore: PlaylistStore,
        smartlistStore: SmartlistStore,
        settings: AppSettings
    ) {

        let firstAlert =
            NSAlert()

        firstAlert.messageText =
            "Reset TandaComposer to Factory State?"

        firstAlert.informativeText =
            "This permanently deletes ALL internal libraries and " +
            "all playlists inside them, and replaces them with a " +
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

            settings.currentLibraryName = AppPaths.defaultLibraryName
            settings.save()

            smartlistStore.reload()
            playlistStore.refreshAfterExternalDataChange()

            NotificationCenter.default.post(
                name: .tandaComposerLibrarySwitched,
                object: nil
            )

        } catch {

            presentError(error)
        }
    }


    // MARK: - Export Backup

    /// Zips the entire ~/.TandaComposer folder (all internal
    /// Libraries, Setlists, Tandas, Smartlists, Settings) to a file
    /// the user picks — a full backup, not just the current Library.
    static func exportBackup() {

        let panel =
            NSSavePanel()

        panel.title =
            "Export Backup"

        panel.nameFieldStringValue =
            defaultBackupFileName()

        panel.allowedContentTypes =
            [.zip]

        panel.canCreateDirectories =
            true

        // The default name is long enough ("TandaComposer Backup
        // yyyy-MM-dd_HHmmss") that NSSavePanel's default width
        // visually truncates it in the name field — this widens the
        // whole panel (the name field scales with it) instead of
        // shortening the name.
        var frame = panel.frame
        frame.size.width = 560
        panel.setFrame(frame, display: true)

        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }

        do {

            try zipInternalRoot(
                to: url
            )

        } catch {

            presentError(error)
        }
    }


    private static func defaultBackupFileName() -> String {

        let formatter =
            DateFormatter()

        formatter.dateFormat =
            "yyyy-MM-dd_HHmmss"

        return
            "TandaComposer Backup \(formatter.string(from: Date()))"
    }


    /// Zips ~/.TandaComposer, but the folder appears in the archive
    /// under its plain, visible name (`AppPaths.appName`, e.g.
    /// "TandaComposer") rather than the hidden dot-name it actually
    /// has on disk (`.TandaComposer`) — so unzipping the backup
    /// manually in Finder shows a normal, browsable folder instead
    /// of a hidden one. Achieved by staging a copy of the folder
    /// under the visible name in a temp directory first, since
    /// `ditto --keepParent` otherwise names the archive entry after
    /// the source folder's actual (hidden) name.
    private static func zipInternalRoot(
        to destinationURL: URL
    ) throws {

        if FileManager.default.fileExists(
            atPath: destinationURL.path
        ) {

            try FileManager.default.removeItem(
                at: destinationURL
            )
        }

        let stagingParent =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        let stagingRoot =
            stagingParent
                .appendingPathComponent(
                    AppPaths.appName,
                    isDirectory: true
                )

        defer {

            try? FileManager.default.removeItem(
                at: stagingParent
            )
        }

        try FileManager.default.createDirectory(
            at: stagingParent,
            withIntermediateDirectories: true
        )

        try FileManager.default.copyItem(
            at: AppPaths.internalRoot,
            to: stagingRoot
        )

        let process =
            Process()

        process.executableURL =
            URL(fileURLWithPath: "/usr/bin/ditto")

        process.arguments = [
            "-c", "-k",
            "--sequesterRsrc",
            "--keepParent",
            stagingRoot.path,
            destinationURL.path
        ]

        let errorPipe =
            Pipe()

        process.standardError =
            errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {

            let message =
                String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )
                ?? "ditto failed with status \(process.terminationStatus)"

            throw LibraryBackupError.exportFailed(message)
        }
    }


    // MARK: - Import Backup

    /// Unzips a previously exported backup back into
    /// ~/.TandaComposer. Files in the backup overwrite any existing
    /// file with the same relative path (Libraries/Default.sqlite,
    /// Setlists/My Set.json, etc — standard `ditto` merge behavior);
    /// anything currently on disk that isn't in the backup is left
    /// untouched. This cannot be undone, so the user is warned before
    /// anything is written.
    static func importBackup(
        db: DatabaseManager,
        libraryStore: LibraryStore,
        playlistStore: PlaylistStore,
        smartlistStore: SmartlistStore
    ) {

        guard
            !libraryStore.isLocked
        else {
            return
        }

        let panel =
            NSOpenPanel()

        panel.title =
            "Import Backup"

        panel.allowedContentTypes =
            [.zip]

        panel.canChooseFiles =
            true

        panel.canChooseDirectories =
            false

        panel.allowsMultipleSelection =
            false

        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }

        let alert =
            NSAlert()

        alert.messageText =
            "Import Backup?"

        alert.informativeText =
            "Files in this backup will overwrite any existing " +
            "file with the same name in your current TandaComposer " +
            "data (Libraries, Setlists, Tandas, Smartlists, " +
            "Settings). Anything you have that isn't in the backup " +
            "is left untouched. This cannot be undone."

        alert.alertStyle =
            .warning

        alert.addButton(withTitle: "Import and Overwrite")
        alert.addButton(withTitle: "Cancel")

        guard
            alert.runModal() == .alertFirstButtonReturn
        else {
            return
        }

        // The path we need to reopen once ditto is done — read
        // BEFORE detaching, since detachForExternalReplace() swaps in
        // a throwaway in-memory database and currentLibraryPath is
        // only meaningful for a file-based one.
        let libraryPathToReopen =
            libraryStore.currentLibraryPath

        do {

            // MUST happen before unzipIntoInternalRoot() touches the
            // .sqlite file on disk — see detachForExternalReplace()'s
            // doc comment for what goes wrong otherwise (a corrupted
            // connection that only a full app restart clears).
            try db.detachForExternalReplace()

            try unzipIntoInternalRoot(
                from: url
            )

            // Reopen the same path. Whether the backup actually
            // contained a Library at this path or not, the file
            // still exists either way — merge either overwrote it
            // with the backup's version, or (if the backup didn't
            // include it) left it completely untouched.
            try db.switchDatabase(
                to: libraryPathToReopen
            )

        } catch {

            presentError(error)
            return
        }

        // Everything on disk may have just changed underneath the
        // in-memory state — reload every store that reads from
        // ~/.TandaComposer. TandaStore and the read-only saved-
        // Setlist viewer live in ContentView, not here, so they're
        // reached via notification instead — see its doc comment.
        do {

            try libraryStore.reload()

        } catch {

            presentError(error)
        }

        smartlistStore.reload()

        playlistStore.refreshAfterExternalDataChange()

        NotificationCenter.default.post(
            name: .tandaComposerBackupImported,
            object: nil
        )
    }


    /// Unzips into a scratch temp folder first (rather than directly
    /// into the home folder), then merges that folder's contents into
    /// ~/.TandaComposer. Two steps are needed now because the backup's
    /// top-level entry is the visible "TandaComposer" name (see
    /// zipInternalRoot), not the actual hidden ".TandaComposer" name
    /// unzipping would need to land on directly — so a plain
    /// extract-in-place can't be used. Also accepts the old hidden-
    /// name top-level entry, for backups made before this change.
    private static func unzipIntoInternalRoot(
        from sourceURL: URL
    ) throws {

        let scratchParent =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        defer {

            try? FileManager.default.removeItem(
                at: scratchParent
            )
        }

        try FileManager.default.createDirectory(
            at: scratchParent,
            withIntermediateDirectories: true
        )

        let extractProcess =
            Process()

        extractProcess.executableURL =
            URL(fileURLWithPath: "/usr/bin/ditto")

        extractProcess.arguments = [
            "-x", "-k",
            sourceURL.path,
            scratchParent.path
        ]

        let extractErrorPipe =
            Pipe()

        extractProcess.standardError =
            extractErrorPipe

        try extractProcess.run()
        extractProcess.waitUntilExit()

        guard extractProcess.terminationStatus == 0 else {

            let message =
                String(
                    data: extractErrorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )
                ?? "ditto failed with status \(extractProcess.terminationStatus)"

            throw LibraryBackupError.importFailed(message)
        }

        // Accept either the current visible top-level folder name or
        // the old hidden-dot one from backups made before this change.
        let visibleCandidate =
            scratchParent
                .appendingPathComponent(
                    AppPaths.appName,
                    isDirectory: true
                )

        let hiddenCandidate =
            scratchParent
                .appendingPathComponent(
                    ".\(AppPaths.appName)",
                    isDirectory: true
                )

        let extractedRoot: URL

        if FileManager.default.fileExists(
            atPath: visibleCandidate.path
        ) {

            extractedRoot = visibleCandidate

        } else if FileManager.default.fileExists(
            atPath: hiddenCandidate.path
        ) {

            extractedRoot = hiddenCandidate

        } else {

            throw LibraryBackupError.importFailed(
                "This file doesn't look like a TandaComposer backup."
            )
        }

        try FileManager.default.createDirectory(
            at: AppPaths.internalRoot,
            withIntermediateDirectories: true
        )

        // ditto with no --keepParent merges SOURCE's contents into an
        // existing DESTINATION folder — overwriting same-named files,
        // leaving everything else in ~/.TandaComposer untouched.
        let mergeProcess =
            Process()

        mergeProcess.executableURL =
            URL(fileURLWithPath: "/usr/bin/ditto")

        mergeProcess.arguments = [
            extractedRoot.path,
            AppPaths.internalRoot.path
        ]

        let mergeErrorPipe =
            Pipe()

        mergeProcess.standardError =
            mergeErrorPipe

        try mergeProcess.run()
        mergeProcess.waitUntilExit()

        guard mergeProcess.terminationStatus == 0 else {

            let message =
                String(
                    data: mergeErrorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )
                ?? "ditto failed with status \(mergeProcess.terminationStatus)"

            throw LibraryBackupError.importFailed(message)
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


// MARK: - Backup Error

private enum LibraryBackupError: LocalizedError {

    case exportFailed(String)
    case importFailed(String)

    var errorDescription: String? {

        switch self {

        case .exportFailed(let message):
            return "Could not create the backup:\n\(message)"

        case .importFailed(let message):
            return "Could not import the backup:\n\(message)"
        }
    }
}
