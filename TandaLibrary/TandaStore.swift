//
//  TandaStore.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 23.08.26.
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


import Foundation
import Combine


/// Result of a `TandaStore.applyRescan(_:)` run.
struct TandaRescanSummary {

    var fixedReferenceCount = 0
    var updatedTandaCount = 0
    var failedWrites: [(url: URL, error: Error)] = []
}


/// One Tanda whose songs a rescan WOULD update — a preview, computed
/// by `previewRescan(byID:byPath:missingSongIDs:)`. Nothing is written to
/// disk until this is handed to `applyRescan(_:)`.
struct TandaRescanFix {
    let tanda: Tanda
    let updatedSongs: [Song]
    let fixedSongCount: Int
}


final class TandaStore:
    ObservableObject {

    @Published
    private(set) var tandas: [Tanda]

    /// `AppPaths.tandasFolder` — follows the currently active
    /// TrackLibrary now, so unlike before this is NOT cached; it must
    /// be re-read on every `reload()` in case the active library
    /// changed since the last one.
    private var tandasRoot:
        URL {
        AppPaths.tandasFolder
    }


    init() {

        self.tandas =
            []

        reload()
    }


    // MARK: - Reload

    /// Re-scans `Tandas/` from disk and replaces `tandas` with the
    /// result. Called from init(), and again whenever a Tanda is saved
    /// elsewhere in the app (see the `.tandaSaved` notification
    /// listener in TandaLibraryView) — this store only scans once at
    /// creation otherwise, so without this a newly-saved Tanda would
    /// only show up the next time TandaLibraryView itself is recreated
    /// (e.g. after switching away from and back to Tandas mode).
    func reload() {

        let fileManager =
            FileManager.default

        // Tandas now live one level down, in a per-artist subdirectory
        // (Tandas/<Artist>/<name>.json — see TandaStorage.ensureTanda-
        // Folder(forArtist:) in PlaylistView.swift), so this has to walk
        // subdirectories too, not just list the top-level folder.
        guard
            let enumerator =
                fileManager.enumerator(
                    at:
                        tandasRoot,
                    includingPropertiesForKeys:
                        nil
                )
        else {
            self.tandas = []
            return
        }

        let files =
            enumerator.compactMap {
                $0 as? URL
            }


        self.tandas =
            files
                .filter {
                    $0.pathExtension.lowercased() == "json"
                }
                .compactMap {
                    Self.loadTanda(
                        from:
                            $0,
                        tandasRoot:
                            tandasRoot
                    )
                }
    }


    // MARK: - Delete

    /// Removes the Tanda's underlying file from disk, then removes it
    /// from `tandas` (matched by `sourceURL`, its stable identity) so
    /// every view reading this store updates immediately — no separate
    /// reload/rescan needed.
    func delete(
        _ tanda:
            Tanda
    ) throws {

        try FileManager.default.removeItem(
            at:
                tanda.sourceURL
        )

        tandas.removeAll {
            $0.sourceURL == tanda.sourceURL
        }
    }


    // MARK: - Update Comment
    //
    // Rewrites the Tanda's saved file with a new comment (its songs and
    // name are unchanged) — for TandaLibraryView's editable comment
    // field. Updates the in-memory `tandas` entry too, so the UI
    // reflects the edit immediately without a full reload().

    func updateComment(
        for tanda:
            Tanda,
        to newComment:
            String
    ) throws {

        try TandaMetadataExporter.export(
            songs: tanda.songs,
            tandaName: tanda.name,
            to: tanda.sourceURL,
            comment: newComment
        )

        guard
            let index = tandas.firstIndex(
                where: { $0.sourceURL == tanda.sourceURL }
            )
        else {
            return
        }

        tandas[index].comment =
            newComment
    }


    // MARK: - Rescan References
    //
    // "Tanda Rescan" (Tools menu): mirrors PlaylistStore's rescan for
    // the same underlying reason — a saved Tanda holds a Song SNAPSHOT
    // per track, taken at save time. If the Track Library later
    // relocates that file (path changed, id unchanged — see
    // LibraryScanner.rescanLibrary), the Tanda's stored path goes
    // stale even though the file is still perfectly well-managed by
    // the Library.
    //
    // Split into a read-only preview and a separate apply step (same
    // shape as LibraryScanner.rescanLibrary/applyRescan and
    // PlaylistStore.previewRescan/applyRescan) so the Tools menu can
    // show what would change and let the user confirm before any
    // Tanda file on disk is actually rewritten.

    /// Read-only: diffs every loaded Tanda's songs against the Library
    /// and returns the fixes a rescan WOULD make. Doesn't touch any
    /// Tanda file or `tandas` itself.
    func previewRescan(
        byID: [Int64: Song],
        byPath: [String: Song],
        missingSongIDs: Set<Int64>
    ) -> [TandaRescanFix] {

        var fixes: [TandaRescanFix] = []

        for tanda in tandas {

            let trustID =
                tanda.savedAgainstLibraryName == AppPaths.currentLibraryName

            var fixedSongCount = 0

            let updatedSongs: [Song] =
                tanda.songs.map { song in

                    let resolution =
                        LibraryReferenceResolver.resolve(
                            song,
                            byID: byID,
                            byPath: byPath,
                            missingSongIDs: missingSongIDs,
                            trustID: trustID
                        )

                    guard
                        let live = resolution.live,
                        resolution.pathChanged
                    else {
                        return song
                    }

                    fixedSongCount += 1

                    return live
                }

            guard fixedSongCount > 0 else {
                continue
            }

            fixes.append(
                TandaRescanFix(
                    tanda: tanda,
                    updatedSongs: updatedSongs,
                    fixedSongCount: fixedSongCount
                )
            )
        }

        return fixes
    }

    /// Commits a previously-computed set of `TandaRescanFix`es (see
    /// `previewRescan(byID:byPath:missingSongIDs:)`) — rewrites each
    /// affected Tanda's JSON file on disk and updates `tandas` in
    /// memory to match.
    @discardableResult
    func applyRescan(
        _ fixes: [TandaRescanFix]
    ) -> TandaRescanSummary {

        var summary = TandaRescanSummary()

        guard !fixes.isEmpty else {
            return summary
        }

        var byURL: [URL: TandaRescanFix] = [:]

        for fix in fixes {
            byURL[fix.tanda.sourceURL] = fix
        }

        var resultingTandas: [Tanda] = []

        for tanda in tandas {

            guard let fix = byURL[tanda.sourceURL] else {
                resultingTandas.append(tanda)
                continue
            }

            do {

                try TandaMetadataExporter.export(
                    songs: fix.updatedSongs,
                    tandaName: tanda.name,
                    to: tanda.sourceURL,
                    comment: tanda.comment
                )

                summary.fixedReferenceCount += fix.fixedSongCount
                summary.updatedTandaCount += 1

                resultingTandas.append(
                    Tanda(
                        name: tanda.name,
                        songs: fix.updatedSongs,
                        comment: tanda.comment,
                        sourceFolder: tanda.sourceFolder,
                        sourceURL: tanda.sourceURL,
                        savedAgainstLibraryName: AppPaths.currentLibraryName
                    )
                )

            } catch {

                // Write failed — keep the tanda's old (still-stale but
                // at least intact) data rather than losing the file's
                // contents from this store's view.
                summary.failedWrites.append(
                    (url: tanda.sourceURL, error: error)
                )

                resultingTandas.append(tanda)
            }
        }

        tandas = resultingTandas

        return summary
    }


    // MARK: - Loading

    private static func loadTanda(
        from url:
            URL,
        tandasRoot:
            URL
    ) -> Tanda? {

        guard
            let export =
                try? TandaMetadataExporter.load(
                    from:
                        url
                )
        else {
            return nil
        }


        return Tanda(
            name:
                export.tandaName,
            songs:
                export.songs,
            comment:
                export.comment ?? "",
            sourceFolder:
                relativeFolder(
                    of:
                        url,
                    tandasRoot:
                        tandasRoot
                ),
            sourceURL:
                url,
            savedAgainstLibraryName:
                export.savedAgainstLibraryName
        )
    }


    /// The Tanda's containing folder, relative to `Tandas/` — e.g. a
    /// file at `.../Tandas/Biagi/foo.json` yields `"Biagi"`. Falls back
    /// to `""` for a file directly in `Tandas/` itself (not expected
    /// given current save logic, but handled gracefully).
    private static func relativeFolder(
        of fileURL:
            URL,
        tandasRoot:
            URL
    ) -> String {

        let folderURL =
            fileURL.deletingLastPathComponent()

        let rootComponents =
            tandasRoot.standardizedFileURL.pathComponents

        let folderComponents =
            folderURL.standardizedFileURL.pathComponents

        guard
            folderComponents.count >
                rootComponents.count,
            Array(
                folderComponents.prefix(
                    rootComponents.count
                )
            ) == rootComponents
        else {

            return ""
        }

        return folderComponents
            .dropFirst(
                rootComponents.count
            )
            .joined(
                separator:
                    "/"
            )
    }
}
