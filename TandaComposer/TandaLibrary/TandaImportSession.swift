//
//  TandaImportSession.swift
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
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Support types

struct TandaImportFolder: Identifiable {

    /// The folder name inside the ZIP ("" = top level).
    let name: String
    let count: Int

    var id: String { name }

    var display: String {
        name.isEmpty ? "(no folder)" : name
    }
}

struct TandaImportSummary {

    var imported = 0
    var skippedExisting = 0
    var failed: [String] = []
}

// MARK: - Session

/// State of "Import Tandas from ZIP": the ZIP, its orchestra folders,
/// and the evaluated Tandas of the folder being looked at.
final class TandaImportSession: ObservableObject {

    @Published private(set) var zipName = ""

    /// Changes with every loaded ZIP, so the window can reset itself.
    @Published private(set) var loadID = UUID()

    @Published private(set) var folders: [TandaImportFolder] = []

    /// Relative paths of files in the ZIP that could not be read.
    @Published private(set) var unreadable: [String] = []

    @Published private(set) var selectedFolder: String?

    /// The Tandas of `selectedFolder`.
    @Published private(set) var entries: [TandaImportEntry] = []

    @Published private(set) var isMatching = false

    /// Ready Tandas the user wants to import.
    @Published private(set) var checked: Set<UUID> = []

    private var scan = SharedTandaScan()
    private var existing: [ExistingTanda] = []
    private var cache: [String: [TandaImportEntry]] = [:]
    private var generation = 0

    var tandaCount: Int {
        scan.tandas.count
    }

    var checkedReadyCount: Int {
        entries.filter {
            checked.contains($0.id) && $0.status == .ready
        }.count
    }

    // MARK: Load

    func load(zipURL: URL) throws {

        let result = try TandaZipImporter.read(zipURL: zipURL)

        generation += 1

        scan = result
        existing = TandaImportResolver.loadExisting()
        cache = [:]
        entries = []
        checked = []
        selectedFolder = nil
        isMatching = false
        unreadable = result.unreadable
        zipName = zipURL.lastPathComponent
        loadID = UUID()

        folders =
            Dictionary(grouping: result.tandas, by: { $0.folder })
                .map {
                    TandaImportFolder(
                        name: $0.key,
                        count: $0.value.count
                    )
                }
                .sorted {
                    $0.name.localizedStandardCompare($1.name)
                        == .orderedAscending
                }
    }

    // MARK: Select a folder

    /// Matches the Tandas of one folder with the TrackLibrary (in the
    /// background, once per folder).
    func select(
        folder: String,
        libraryStore: LibraryStore,
        settings: AppSettings
    ) {

        guard folder != selectedFolder else {
            return
        }

        selectedFolder = folder

        if let cached = cache[folder] {
            entries = cached
            return
        }

        entries = []
        isMatching = true

        generation += 1
        let token = generation

        let tandas = scan.tandas.filter { $0.folder == folder }
        let songs = libraryStore.songs
        let missing = libraryStore.missingSongIDs
        let existingSnapshot = existing
        let orchestraSource = settings.orchestraSource
        let singerSource = settings.singerSource
        let autoPick = settings.autoPickBestFile

        Task.detached(priority: .userInitiated) {

            let evaluated =
                TandaImportResolver.evaluate(
                    tandas,
                    library: songs,
                    orchestraSource: orchestraSource,
                    singerSource: singerSource,
                    autoPickBestFile: autoPick,
                    missingSongIDs: missing,
                    existing: existingSnapshot
                )

            await MainActor.run {

                guard token == self.generation else {
                    return
                }

                var result = evaluated

                // Where each ready Tanda would be saved.
                for index in result.indices
                where result[index].status == .ready {

                    let place =
                        TandaSaver.resolvedLocation(
                            for: result[index].songs,
                            settings: settings
                        )

                    result[index].location =
                        Self.shortLocation(
                            folder: place.folder,
                            name: place.name
                        )
                }

                self.cache[folder] = result
                self.entries = result

                self.checked.formUnion(
                    result
                        .filter { $0.status == .ready }
                        .map { $0.id }
                )

                self.isMatching = false
            }
        }
    }

    // MARK: Check / uncheck

    func toggle(_ id: UUID) {

        guard entries.contains(where: {
            $0.id == id && $0.status == .ready
        }) else {
            return
        }

        if checked.contains(id) {
            checked.remove(id)
        } else {
            checked.insert(id)
        }
    }

    // MARK: Choose a track by hand

    /// Sets (or, when it is already the choice, takes back) the track of
    /// one line, then recomputes the Tanda. A Tanda that becomes ready
    /// is checked for import.
    func setChoice(
        _ song: Song,
        line lineID: UUID,
        entry entryID: UUID,
        libraryStore: LibraryStore,
        settings: AppSettings
    ) {

        guard let folder = selectedFolder,
              let entryIndex =
                entries.firstIndex(where: { $0.id == entryID }),
              let lineIndex =
                entries[entryIndex].lines
                    .firstIndex(where: { $0.id == lineID })
        else {
            return
        }

        var entry = entries[entryIndex]

        switch entry.status {
        case .imported, .failed:
            return
        default:
            break
        }

        var line = entry.lines[lineIndex]

        if line.song?.normalizedPath == song.normalizedPath {

            line.song = nil
            line.note = "no track chosen"
            line.chosenByUser = false

        } else {

            line.song = song
            line.note = "chosen by you"
            line.chosenByUser = true
        }

        entry.lines[lineIndex] = line

        entry =
            TandaImportResolver.refreshed(
                entry,
                missingSongIDs: libraryStore.missingSongIDs,
                existing: existing
            )

        if entry.status == .ready {

            let place =
                TandaSaver.resolvedLocation(
                    for: entry.songs,
                    settings: settings
                )

            entry.location =
                Self.shortLocation(
                    folder: place.folder,
                    name: place.name
                )

            checked.insert(entry.id)

        } else {

            checked.remove(entry.id)
        }

        entries[entryIndex] = entry
        cache[folder] = entries
    }

    // MARK: Import

    /// Saves every checked, ready Tanda of the selected folder.
    ///
    /// `TandaSaver` posts `.tandaSaved` after each save, which makes the
    /// Tanda list reload itself.
    func importChecked(
        libraryStore: LibraryStore,
        settings: AppSettings
    ) -> TandaImportSummary {

        var summary = TandaImportSummary()

        guard let folder = selectedFolder else {
            return summary
        }

        var known = existing
        var updated = entries

        for index in updated.indices {

            let entry = updated[index]

            guard checked.contains(entry.id),
                  entry.status == .ready
            else {
                continue
            }

            checked.remove(entry.id)

            let paths = Set(entry.songs.map { $0.normalizedPath })

            // Two Tandas of the ZIP with the same tracks.
            if let same = known.first(where: { $0.paths == paths }) {

                updated[index].status = .exists(same.name)
                summary.skippedExisting += 1
                continue
            }

            do {

                let url =
                    try TandaSaver.save(
                        songs: entry.songs,
                        existingTandas: [],
                        missingSongIDs: libraryStore.missingSongIDs,
                        settings: settings
                    )

                let name = url.deletingPathExtension().lastPathComponent

                updated[index].status =
                    .imported(
                        Self.shortLocation(
                            folder: url.deletingLastPathComponent(),
                            name: name
                        )
                    )

                known.append(ExistingTanda(name: name, paths: paths))
                summary.imported += 1

            } catch {

                updated[index].status =
                    .failed(error.localizedDescription)

                summary.failed.append(
                    "\(entry.shared.name): \(error.localizedDescription)"
                )
            }
        }

        existing = known
        entries = updated
        cache[folder] = updated

        return summary
    }

    // MARK: Helpers

    /// "Biagi/Acuna/Biagi_Tango_Acuna" from a folder below the
    /// Tandas folder and a name.
    private static func shortLocation(
        folder: URL,
        name: String
    ) -> String {

        let root = AppPaths.tandasFolder.path

        var path = folder.path

        if path.hasPrefix(root) {
            path = String(path.dropFirst(root.count))
        }

        path = path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )

        return path.isEmpty ? name : path + "/" + name
    }
}

// MARK: - Actions

enum TandaImportActions {

    /// Asks for a ZIP and loads it. True when there is something to
    /// show in the window.
    @discardableResult
    static func chooseZip(
        session: TandaImportSession
    ) -> Bool {

        let panel = NSOpenPanel()

        panel.title = "Import Tandas from ZIP"

        panel.message =
            "Choose a ZIP made with Tools → Export TandaLibrary for Sharing."

        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return false
        }

        do {

            try session.load(zipURL: url)

        } catch {

            present(
                title: "ZIP Could Not Be Read",
                text: error.localizedDescription
            )

            return false
        }

        guard session.tandaCount > 0 else {

            present(
                title: "No Tandas Found",
                text:
                    "The ZIP contains no readable text or M3U8 files."
                    + (session.unreadable.isEmpty
                        ? ""
                        : "\n\nCould not be read:\n"
                            + session.unreadable
                                .prefix(10)
                                .joined(separator: "\n"))
            )

            return false
        }

        return true
    }

    static func present(
        title: String,
        text: String
    ) {

        let alert = NSAlert()

        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning

        alert.runModal()
    }
}
