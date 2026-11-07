//
//  TandaLibraryExportActions.swift
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

/// TandaLibrary export actions.
///
/// Live path: `exportJSONZip` (Tools → Export → "TandaLibrary (JSON-ZIP)…").
/// `exportForSharing` (text / M3U8 ZIP) is temporarily kept as dead code.
enum TandaLibraryExportActions {

    // MARK: - Dead code (text / M3U8 ZIP)
    //
    // Formerly Tools → Export → "TandaLibrary (ZIP)…". Not exposed in the
    // UI for now; kept so we can revive it without digging in history.

    static func exportForSharing(
        libraryStore: LibraryStore,
        settings: AppSettings
    ) {

        let panel = NSSavePanel()

        panel.title = "Export TandaLibrary (ZIP)"

        panel.message =
            "Creates a ZIP with your Tandas to give to another DJ who also uses TandaComposer. It contains one file per Tanda, in the same folders as your TandaLibrary. Your TandaLibrary and your music files are not changed."

        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFileName()

        let popup =
            NSPopUpButton(frame: .zero, pullsDown: false)

        popup.addItems(
            withTitles: [
                "Text files (.txt) — recommended for sharing",
                "M3U8 playlists (.m3u8) — for other players"
            ]
        )

        let label =
            NSTextField(labelWithString: "Format:")

        let accessory =
            NSStackView(views: [label, popup])

        accessory.orientation = .horizontal
        accessory.spacing = 8

        accessory.edgeInsets =
            NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        accessory.setFrameSize(accessory.fittingSize)
        panel.accessoryView = accessory

        guard
            panel.runModal() == .OK,
            let destination = panel.url
        else {
            return
        }

        let format: TandaExportFormat =
            popup.indexOfSelectedItem == 1 ? .m3u8 : .text

        let stagingParent =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        // The single top-level folder inside the ZIP.
        let stagingRoot =
            stagingParent
                .appendingPathComponent(
                    "Tandas",
                    isDirectory: true
                )

        defer {
            try? FileManager.default.removeItem(at: stagingParent)
        }

        do {

            try FileManager.default.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: true
            )

            let summary =
                try TandaLibraryExporter.export(
                    to: stagingRoot,
                    format: format,
                    orchestraSource: settings.orchestraSource,
                    singerSource: settings.singerSource,
                    songsByID: libraryStore.songsByID,
                    songsByPath: libraryStore.songsByNormalizedPath,
                    missingSongIDs: libraryStore.missingSongIDs
                )

            guard summary.tandaCount > 0 else {

                present(
                    title: "No Tandas to Export",
                    text:
                        summary.unreadableFiles.isEmpty
                            ? "The TandaLibrary has no saved Tandas."
                            : "None of the Tanda files could be read:\n"
                                + summary.unreadableFiles
                                    .prefix(10)
                                    .joined(separator: "\n")
                )

                return
            }

            try TandaLibraryExporter.zip(
                folder: stagingRoot,
                to: destination
            )

            presentSummary(
                summary,
                destination: destination
            )

        } catch {

            present(
                title: "Export Failed",
                text: error.localizedDescription
            )
        }
    }

    // MARK: - Messages

    private static func presentSummary(
        _ summary: TandaExportSummary,
        destination: URL
    ) {

        var lines: [String] = [
            "\(summary.tandaCount) Tandas (\(summary.trackCount) tracks) in \(summary.folderCount) folders were exported to \"\(destination.lastPathComponent)\"."
        ]

        if summary.notInLibraryCount > 0 {
            lines.append(
                "\(summary.notInLibraryCount) tracks are not in your TrackLibrary; their tags come from the saved Tanda."
            )
        }

        if summary.missingFileCount > 0 {
            lines.append(
                "\(summary.missingFileCount) tracks have a missing file on disk. They are included anyway."
            )
        }

        if !summary.unreadableFiles.isEmpty {

            lines.append(
                "\(summary.unreadableFiles.count) Tanda files could not be read and were skipped:\n"
                + summary.unreadableFiles
                    .prefix(10)
                    .joined(separator: "\n")
            )
        }

        let alert = NSAlert()

        alert.messageText = "TandaLibrary Exported"
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.alertStyle = .informational

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show in Finder")

        if alert.runModal() == .alertSecondButtonReturn {

            NSWorkspace.shared.activateFileViewerSelecting(
                [destination]
            )
        }
    }

    private static func present(
        title: String,
        text: String
    ) {

        let alert = NSAlert()

        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning

        alert.runModal()
    }

    // MARK: - JSON ZIP (live)
    //
    // Tools → Export → "TandaLibrary (JSON-ZIP)…". See
    // TandaLibraryJSONExporter for what goes into the ZIP.

    private static let jsonZipFolderKey =
        "TandaLibraryJSONZipLastFolder"

    static func exportJSONZip() {

        let panel =
            NSSavePanel()

        panel.title =
            "Export TandaLibrary (JSON ZIP)"

        panel.message = """
            Saves all your Tandas exactly as they are stored — one \
            JSON file per Tanda in your Orchestra / Singer folders — \
            in one ZIP file. The files contain the complete song \
            data, including the file paths on this Mac. If the name \
            is already taken, the number is counted up.
            """

        panel.allowedContentTypes =
            [.zip]

        panel.canCreateDirectories =
            true

        panel.isExtensionHidden =
            false

        let note =
            NSTextField(
                wrappingLabelWithString: """
                    Orchestra = \(TandaConventions.orchestra.displayName), \
                    Singer = \(TandaConventions.singer.displayName) \
                    (from Settings). Older Tanda files that do not \
                    record this yet get it added in the ZIP only; \
                    your own files stay unchanged.
                    """
            )

        note.font =
            .systemFont(ofSize: NSFont.smallSystemFontSize)

        note.textColor =
            .secondaryLabelColor

        note.preferredMaxLayoutWidth =
            440

        note.sizeToFit()

        panel.accessoryView =
            note

        let defaultName =
            defaultFileName()

        if let folder = lastJSONZipFolder() {

            panel.directoryURL = folder

            panel.nameFieldStringValue =
                TandaLibraryJSONExporter.firstFreeURL(
                    for:
                        folder
                            .appendingPathComponent(defaultName)
                            .appendingPathExtension("zip")
                )
                .lastPathComponent

        } else {

            panel.nameFieldStringValue =
                defaultName + ".zip"
        }

        guard
            panel.runModal() == .OK,
            let selected = panel.url
        else {
            return
        }

        // Never overwrite: a name that is already taken gets the next
        // free number.
        let destination =
            TandaLibraryJSONExporter.firstFreeURL(for: selected)

        let fm = FileManager.default

        let temp =
            fm.temporaryDirectory
                .appendingPathComponent(
                    "TandaComposer-JSONZip-\(UUID().uuidString)",
                    isDirectory: true
                )

        defer {
            try? fm.removeItem(at: temp)
        }

        do {

            let staging =
                temp.appendingPathComponent("Tandas", isDirectory: true)

            let summary =
                try TandaLibraryJSONExporter.export(to: staging)

            guard summary.tandaCount > 0 else {

                present(
                    title: "Nothing to export",
                    text: "There are no Tandas in the TandaLibrary."
                )

                return
            }

            try TandaLibraryExporter.zip(
                folder: staging,
                to: destination
            )

            UserDefaults.standard.set(
                destination.deletingLastPathComponent().path,
                forKey: jsonZipFolderKey
            )

            presentJSONSummary(
                summary,
                fileName: destination.lastPathComponent
            )

        } catch {

            present(
                title: "Export failed",
                text: error.localizedDescription
            )
        }
    }

    private static func lastJSONZipFolder() -> URL? {

        guard
            let path = UserDefaults.standard.string(
                forKey: jsonZipFolderKey
            ),
            FileManager.default.fileExists(atPath: path)
        else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func presentJSONSummary(
        _ summary: TandaLibraryJSONExporter.Summary,
        fileName: String
    ) {

        var lines: [String] = [
            "\(summary.tandaCount) Tandas in "
                + "\(summary.folderCount) folders were saved in "
                + "“\(fileName)”."
        ]

        if summary.stampedCount > 0 {
            lines.append(
                "\(summary.stampedCount) older Tanda files did not "
                + "record the Orchestra / Singer setting yet; it was "
                + "added in the ZIP only."
            )
        }

        if !summary.unreadableFiles.isEmpty {
            lines.append(
                "Not exported (not readable as a Tanda):\n"
                + summary.unreadableFiles.prefix(10)
                    .map { "• \($0)" }
                    .joined(separator: "\n")
                + (summary.unreadableFiles.count > 10 ? "\n…" : "")
            )
        }

        let alert = NSAlert()

        alert.messageText = "TandaLibrary exported"
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.alertStyle =
            summary.unreadableFiles.isEmpty ? .informational : .warning

        alert.runModal()
    }

    private static func defaultFileName() -> String {

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return "TandaLibrary \(formatter.string(from: Date()))"
    }
}
