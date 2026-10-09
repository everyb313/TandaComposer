//
//  LibraryActions+Backup.swift
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

// MARK: - Backup export / import

extension LibraryActions {

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
        setlistStore: SetlistStore,
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

        setlistStore.refreshAfterExternalDataChange()

        NotificationCenter.default.post(
            name: AppNotification.tandaComposerBackupImported,
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
