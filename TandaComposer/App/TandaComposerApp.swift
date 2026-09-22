//
//  TandaComposerApp.swift
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
//  TandaComposerApp.swift
//  TandaComposer
//

import SwiftUI
import AppKit

@main
struct TandaComposerApp: App {

    private let environment: AppEnvironment

    @StateObject private var settings: AppSettings
    @StateObject private var switchConfirmationCenter = SwitchConfirmationCenter()
    @StateObject private var audioOutputManager = AudioOutputManager.shared

    @Environment(\.openWindow)
    private var openWindow

    init() {

        NSWindow.allowsAutomaticWindowTabbing = false

        // AppSettings has to load — and AppPaths.currentLibraryName
        // has to be primed from it — BEFORE AppEnvironment() runs:
        // that's what determines which TrackLibrary's subtree
        // (database, Setlists, Smartlists, Tandas) everything below
        // resolves against. Explicit StateObject construction here,
        // rather than the usual `= AppSettings()` default-value form,
        // guarantees this ordering instead of relying on SwiftUI's
        // (here, undocumented for this exact case) property-wrapper
        // initialization timing.
        let loadedSettings =
            AppSettings()

        _settings =
            StateObject(
                wrappedValue: loadedSettings
            )

        AppPaths.currentLibraryName =
            loadedSettings.currentLibraryName

        environment = AppEnvironment()
    }

    var body: some Scene {

        WindowGroup {

            ContentView()
                .environmentObject(settings)
                .environmentObject(audioOutputManager)
                .environmentObject(environment.libraryStore)
                .environmentObject(environment.playlistStore)
                .environmentObject(environment.scanner)
                .environmentObject(environment.smartlistStore)
                .environmentObject(switchConfirmationCenter)
                .preferredColorScheme(settings.colorScheme)
                .onAppear {
                    startApplication()
                    installVolumeMountObservers()
                }
                .sheet(item: $switchConfirmationCenter.request) { request in

                    SaveBeforeSwitchDialog(request: request) {
                        switchConfirmationCenter.request = nil
                    }
                }
        }

        .commands {

            CommandGroup(replacing: .newItem) { }

            PlaylistCommands(
                playlistStore: environment.playlistStore,
                libraryStore: environment.libraryStore,
                switchConfirmationCenter: switchConfirmationCenter
            )

            LibraryCommands(
                libraryStore: environment.libraryStore,
                switchConfirmationCenter: switchConfirmationCenter,
                playlistStore: environment.playlistStore,
                smartlistStore: environment.smartlistStore,
                settings: settings
            )

            SmartlistCommands(
                smartlistStore: environment.smartlistStore
            )

            RescanCommands(
                db: environment.db,
                libraryStore: environment.libraryStore,
                playlistStore: environment.playlistStore,
                smartlistStore: environment.smartlistStore
            )

            MaintenanceCommands()

            CommandGroup(replacing: .appInfo) {

                Button("About TandaComposer") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(replacing: .help) {

                Button("TandaComposer Help") {
                    openWindow(id: "help-en")
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
        }

        WindowGroup(
            "About TandaComposer",
            id: "about"
        ) {

            AboutView()
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }
        .windowResizability(.contentSize)

        WindowGroup(
            "Edit Smartlist",
            for: String.self
        ) { $nodeID in

            if let nodeID {

                SmartListEditorWindowView(
                    nodeID: nodeID
                )
                .environmentObject(environment.smartlistStore)
                .preferredColorScheme(settings.colorScheme)
            }
        }

        Settings {

            SettingsView()
                .environmentObject(settings)
                .environmentObject(audioOutputManager)
        }

        WindowGroup(
            id: "duplicate-finder"
        ) {

            DuplicateFinderView()
                .environmentObject(environment.libraryStore)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }
        .windowResizability(.contentSize)

        WindowGroup(
            id: "rescan-library"
        ) {

            RescanLibraryView()
                .environmentObject(environment.libraryStore)
                .environmentObject(environment.scanner)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }

        WindowGroup(
            id: "import-sources"
        ) {

            ImportSourcesView()
                .environmentObject(environment.libraryStore)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }
        .windowResizability(.contentSize)

        WindowGroup(
            id: "rescan-setlist"
        ) {

            RescanSetlistView()
                .environmentObject(environment.libraryStore)
                .environmentObject(environment.playlistStore)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }
        .windowResizability(.contentSize)

        WindowGroup(
            id: "rescan-tandas"
        ) {

            RescanTandaView()
                .environmentObject(environment.libraryStore)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }
        .windowResizability(.contentSize)

        WindowGroup(
            id: "rescan-saved-setlists"
        ) {

            RescanSavedSetlistsView()
                .environmentObject(environment.libraryStore)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }
        .windowResizability(.contentSize)

        WindowGroup(
            id: "maintenance"
        ) {

            MaintenanceView()
                .environmentObject(environment.libraryStore)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }
        .windowResizability(.contentSize)

        WindowGroup(
            id: "help-en"
        ) {

            HelpWindowView(resourceName: "help_en")
                .preferredColorScheme(settings.colorScheme)
        }
    }

    // MARK: - Application Start

    private func startApplication() {

        do {

            try environment.libraryStore.reload()

        } catch {

            print(
                "LIBRARY LOAD ERROR:",
                error.localizedDescription
            )
        }

        // The active TrackLibrary at last quit failed to open (see
        // AppEnvironment.init()) — the app is currently running on a
        // temporary in-memory database. Tell the user and let them
        // pick a different Library or create a new one right away,
        // rather than leaving them stuck on a Library that silently
        // isn't really there.
        if let failedLibraryName = environment.libraryStore.startupLibraryError {

            LibraryActions.recoverFromStartupLibraryError(
                failedLibraryName: failedLibraryName,
                libraryStore: environment.libraryStore,
                playlistStore: environment.playlistStore,
                smartlistStore: environment.smartlistStore,
                settings: settings
            )
        }

        guard let lastSetlist = UserDefaults.standard.string(
            forKey: AppPaths.lastPlaylistDefaultsKey
        ) else {
            return
        }

        do {

            try environment.playlistStore.load(
                playlistName: lastSetlist
            )

        } catch {

            print(
                "LAST SETLIST LOAD ERROR:",
                error.localizedDescription
            )
        }
    }


    // =============================================================
    // MARK: - Volume Mount / Wake Observers
    //
    // Reconnecting a USB drive that holds imported music files didn't
    // update anything by itself — the TrackLibrary/Setlist/TandaLibrary
    // "missing" (red dot) status is only ever re-checked in
    // LibraryStore.reload() (specifically refreshMissingSongIDs(),
    // which just re-runs FileManager.fileExists(atPath:) for every
    // Song already in the DB), and nothing called that when a volume
    // appeared.
    //
    // This does NOT do what "Rescan TrackLibrary" does — no folder
    // walking, no new-file discovery, nothing written. It only
    // re-checks paths the Library already knows about, so it's safe
    // to run automatically with no confirmation step, unlike Rescan.
    //
    // Once missingSongIDs updates, everything downstream already
    // reacts on its own: PlaylistView has `.onChange(of: libraryStore.
    // missingSongIDs)` re-resolving Setlist entry statuses, and
    // TandaLibraryView/LibraryTableView/SmartlistView read
    // libraryStore.missingSongIDs directly in their body, so SwiftUI
    // re-renders them for free — nothing else needed there.
    // =============================================================

    private func installVolumeMountObservers() {

        let workspace = NSWorkspace.shared

        // A drive was connected/mounted.
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { _ in

            Task { @MainActor in
                refreshMissingStatus()
            }
        }

        // Mac woke from sleep — a drive that was already mounted
        // before sleep may only become reachable again a moment
        // after wake, so retry a couple of times with a short delay
        // rather than checking exactly once, right when the drive
        // might not have finished remounting yet.
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in

            Task { @MainActor in

                refreshMissingStatus()

                try? await Task.sleep(for: .milliseconds(1200))
                refreshMissingStatus()

                try? await Task.sleep(for: .milliseconds(2500))
                refreshMissingStatus()
            }
        }
    }

    @MainActor
    private func refreshMissingStatus() {

        // Don't interrupt an active import — it will leave
        // missingSongIDs in a correct state on its own once it
        // finishes.
        guard !environment.scanner.isScanning else {
            return
        }

        do {

            try environment.libraryStore.reload()

        } catch {

            print(
                "VOLUME MOUNT REFRESH FAILED:",
                error.localizedDescription
            )
        }
    }
}

// ================================================================
// MARK: - AppEnvironment
// ================================================================

@MainActor
final class AppEnvironment {

    let db: DatabaseManager
    let libraryStore: LibraryStore
    let playlistStore: PlaylistStore
    let scanner: LibraryScanner
    let smartlistStore: SmartlistStore

    init() {

        let libraryPath: String

        do {

            libraryPath = try DatabaseManager.startupStorePath()

        } catch {

            // Should only happen if ~/.TandaComposer itself is
            // unusable (disk full, permissions, etc — there's no
            // removable-media case anymore, everything lives on the
            // boot drive). Never crash: fall back to an in-memory
            // database so the app stays usable for this session.
            print(
                "Could not initialize the library:",
                error.localizedDescription
            )

            do {

                db = try DatabaseManager()
                libraryStore = LibraryStore(db: db)
                playlistStore = PlaylistStore(db: db)
                scanner = LibraryScanner(db: db)
                smartlistStore = SmartlistStore()

                print(
                    "TandaComposer started with a temporary in-memory database."
                )

                return

            } catch {

                // DatabaseManager's in-memory initialization should
                // normally never fail. We cannot construct the
                // required objects without a valid database, so this
                // is reported clearly rather than using fatalError().
                print(
                    "CRITICAL DATABASE ERROR:",
                    error.localizedDescription
                )

                db = try! DatabaseManager()
                libraryStore = LibraryStore(db: db)
                playlistStore = PlaylistStore(db: db)
                scanner = LibraryScanner(db: db)
                smartlistStore = SmartlistStore()

                return
            }
        }

        // Name of the TrackLibrary that failed to open, if any — kept
        // outside the do/catch below so it can be attached to
        // libraryStore afterward (LibraryStore doesn't exist yet at
        // this point in init).
        let failedLibraryName: String?

        do {

            db = try DatabaseManager(
                path: libraryPath
            )

            failedLibraryName = nil

        } catch {

            print(
                "Could not open library database:",
                error.localizedDescription
            )

            failedLibraryName = URL(fileURLWithPath: libraryPath)
                .deletingPathExtension()
                .lastPathComponent

            do {

                db = try DatabaseManager()

                print(
                    "Using temporary in-memory database."
                )

            } catch {

                print(
                    "Could not create in-memory database:",
                    error.localizedDescription
                )

                db = try! DatabaseManager()
            }
        }

        libraryStore = LibraryStore(
            db: db
        )

        if let failedLibraryName {

            // Do NOT call setCurrentLibraryName(from: libraryPath)
            // here — that would make libraryStore claim to be "on"
            // the very Library that just failed to open, even though
            // `db` above is actually a throwaway in-memory database
            // disconnected from that path (and from that Library's
            // Setlists/Tandas/Smartlists subtree). Surface the
            // failure instead; startApplication() shows it and offers
            // Open/New Library. currentLibraryName/currentLibraryPath
            // stay at their defaults until the user resolves it.
            libraryStore.startupLibraryError = failedLibraryName

        } else {

            libraryStore.setCurrentLibraryName(
                from: libraryPath
            )
        }

        playlistStore = PlaylistStore(db: db)

        scanner = LibraryScanner(
            db: db
        )

        smartlistStore = SmartlistStore()
    }
}
