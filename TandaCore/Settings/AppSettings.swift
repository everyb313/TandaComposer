//
//  AppSettings.swift
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

//
//  AppSettings.swift
//  TandaComposer
//

import Foundation
import Combine
import SwiftUI


// =============================================================
// MARK: - Appearance
// =============================================================

enum AppearanceMode:
    String,
    Codable,
    CaseIterable,
    Identifiable {

    case light
    case dark
    case auto

    var id: String {
        rawValue
    }

    var displayName: String {

        switch self {

        case .light:
            return "Light"

        case .dark:
            return "Dark"

        case .auto:
            return "Auto"
        }
    }
}


// =============================================================
// MARK: - Tag Source (Orchestra / Singer)
// =============================================================

/// Tango tagging conventions vary per user/collection: some put the
/// orchestra name in the Artist tag and the singer in AlbumArtist;
/// others use Grouping for one or the other. Rather than assume one
/// convention, the app resolves "Orchestra" and "Singer" from
/// whichever raw tag field the user designates here — independently
/// configurable, so e.g. Orchestra can come from Artist while Singer
/// comes from Grouping.
enum TagSource:
    String,
    Codable,
    CaseIterable,
    Identifiable {

    case artist
    case albumArtist
    case grouping

    var id: String {
        rawValue
    }

    var displayName: String {

        switch self {

        case .artist:
            return "Artist"

        case .albumArtist:
            return "AlbumArtist"

        case .grouping:
            return "Grouping"
        }
    }
}


// =============================================================
// MARK: - AppSettings
// =============================================================

@MainActor
final class AppSettings:
    ObservableObject {


    // =============================================================
    // MARK: Appearance
    // =============================================================

    @Published var appearanceMode:
        AppearanceMode = .auto


    var colorScheme:
        ColorScheme? {

        switch appearanceMode {

        case .light:
            return .light

        case .dark:
            return .dark

        case .auto:
            return nil
        }
    }


    // =============================================================
    // MARK: Application Version
    // =============================================================

    var appVersion:
        String {

        Bundle.main.object(
            forInfoDictionaryKey:
                "CFBundleShortVersionString"
        ) as? String
        ?? "0.1.0"
    }


    var buildNumber:
        String {

        Bundle.main.object(
            forInfoDictionaryKey:
                "CFBundleVersion"
        ) as? String
        ?? "1"
    }


    // =============================================================
    // MARK: Main Split View
    // =============================================================

    @Published var setPaneWidth:
        Double = 200

    @Published var libraryPaneWidth:
        Double = 600

    @Published var smartlistsPaneWidth:
        Double = 100

    @Published var currentLibraryPaneWidth:
        Double = 600


    // =============================================================
    // MARK: Tag Source (Orchestra / Singer)
    // =============================================================

    @Published var orchestraSource:
        TagSource = .artist

    @Published var singerSource:
        TagSource = .albumArtist


    // =============================================================
    // MARK: Current TrackLibrary
    // =============================================================

    /// The name of the TrackLibrary to reopen on next launch. This is
    /// the ONE field in this file that isn't a UI preference — it's
    /// also mirrored into `AppPaths.currentLibraryName` (a plain
    /// static var) so path resolution can use it before/without
    /// needing an `AppSettings` instance around; see that property's
    /// doc comment for why. `LibraryStore`'s switch/create/reset
    /// methods update `AppPaths.currentLibraryName` directly and
    /// immediately (synchronously, since other stores need it right
    /// away); the App-layer call sites in `LibraryActions` are
    /// responsible for also updating THIS field and calling `save()`
    /// afterwards, so the choice survives a relaunch.
    @Published var currentLibraryName:
        String = AppPaths.defaultLibraryName


    // =============================================================
    // MARK: Settings File
    // =============================================================

    /// Settings are ALWAYS stored in the permanent internal
    /// application-support directory.
    ///
    /// This is intentional: changing the Library Location must not
    /// make the settings file disappear or move.
    ///
    /// Deliberately a direct child of `AppPaths.root`
    /// (`AppPaths.appSettingsFile`), not nested in its own "Settings"
    /// subfolder as before — `currentLibraryName` above has to be
    /// readable before any per-TrackLibrary subtree is even chosen,
    /// so this file can't live inside one.
    private let fileURL:
        URL


    // =============================================================
    // MARK: Init
    // =============================================================

    init() {

        fileURL =
            AppPaths.appSettingsFile

        load()
    }


    // =============================================================
    // MARK: Load
    // =============================================================

    func load() {

        do {

            let data =
                try Data(
                    contentsOf:
                        fileURL
                )

            let values =
                try JSONDecoder()
                    .decode(
                        SettingsData.self,
                        from:
                            data
                    )


            if
                let value =
                    values.setPaneWidth,
                value.isFinite,
                value > 1
            {
                setPaneWidth =
                    value
            }


            if
                let value =
                    values.libraryPaneWidth,
                value.isFinite,
                value > 1
            {
                libraryPaneWidth =
                    value
            }


            if
                let value =
                    values.smartlistsPaneWidth,
                value.isFinite,
                value > 1
            {
                smartlistsPaneWidth =
                    value
            }


            if
                let raw =
                    values.appearanceMode,
                let mode =
                    AppearanceMode(
                        rawValue:
                            raw
                    )
            {
                appearanceMode =
                    mode
            }


            if
                let raw =
                    values.orchestraSource,
                let source =
                    TagSource(
                        rawValue:
                            raw
                    )
            {
                orchestraSource =
                    source
            }


            if
                let raw =
                    values.singerSource,
                let source =
                    TagSource(
                        rawValue:
                            raw
                    )
            {
                singerSource =
                    source
            }


            if
                let name =
                    values.currentLibraryName,
                !name.isEmpty
            {
                currentLibraryName =
                    name
            }

            // Keep AppPaths' static cache in sync too — mainly
            // matters if `load()` is ever called again after startup
            // (TandaComposerApp.init() already primes AppPaths from
            // this same value before AppEnvironment() is built, so
            // this is a safety net, not the primary wiring).
            AppPaths.currentLibraryName =
                currentLibraryName


            print(
                "LOAD OK:",
                "panes:",
                setPaneWidth,
                libraryPaneWidth,
                smartlistsPaneWidth
            )

        } catch {

            print(
                "LOAD FAILED:",
                error.localizedDescription
            )
        }
    }


    // =============================================================
    // MARK: Save
    // =============================================================

    func save() {

        let values =
            SettingsData(

                setPaneWidth:
                    setPaneWidth,

                libraryPaneWidth:
                    libraryPaneWidth,

                smartlistsPaneWidth:
                    smartlistsPaneWidth,

                appearanceMode:
                    appearanceMode.rawValue,

                orchestraSource:
                    orchestraSource.rawValue,

                singerSource:
                    singerSource.rawValue,

                currentLibraryName:
                    currentLibraryName
            )


        do {

            let folder =
                fileURL
                    .deletingLastPathComponent()

            try FileManager.default.createDirectory(
                at:
                    folder,
                withIntermediateDirectories:
                    true
            )

            let data =
                try JSONEncoder()
                    .encode(
                        values
                    )

            try data.write(
                to:
                    fileURL,
                options:
                    .atomic
            )

            print(
                "Saving settings:",
                fileURL.path
            )

        } catch {

            print(
                "SAVE FAILED:",
                error.localizedDescription
            )
        }
    }
}


// =============================================================
// MARK: - Codable Settings
// =============================================================

private struct SettingsData:
    Codable {

    let setPaneWidth:
        Double?

    let libraryPaneWidth:
        Double?

    let smartlistsPaneWidth:
        Double?

    let appearanceMode:
        String?

    let orchestraSource:
        String?

    let singerSource:
        String?

    let currentLibraryName:
        String?
}
