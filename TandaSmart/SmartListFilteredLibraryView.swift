//
//  SmartListFilteredLibraryView.swift
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

import SwiftUI
import AppKit

/// Right column of the 3-column layout.
///
/// The Library lock is independent from the Smartlist lock.
struct SmartListFilteredLibraryView:
    View {

    @EnvironmentObject private var libraryStore:
        LibraryStore

    @EnvironmentObject private var playlistStore:
        PlaylistStore

    @EnvironmentObject private var switchConfirmationCenter:
        SwitchConfirmationCenter

    @EnvironmentObject private var scanner:
        LibraryScanner


    let selection:
        SmartlistSelection

    /// Local A/T/V/M/X filter from the TrackLibrary header. It is used
    /// only when `selection` is `.showAll`; an active Smartlist always
    /// takes precedence and is the sole TrackLibrary filter.
    let danceFilter:
        TandaDanceFilter

    let onAddFiles:
        () -> Void


    @State private var tableSelection =
        Set<Int64?>()

    @State private var libraryErrorMessage:
        String?

    /// Controls how Library songs are dragged into the Setlist.
    @State private var setInsertionMode:
        SetInsertionMode = .add

    @State private var isShowingCleanUpSheet =
        false

    @State private var cleanUpErrorMessage:
        String?


    var body: some View {

        VStack(
            spacing:
                0
        ) {

            LibraryTableView(
                songs:
                    filteredSongs,
                missingSongIDs:
                    libraryStore.missingSongIDs,
                selection:
                    $tableSelection,
                insertionMode:
                    setInsertionMode
            )


            Divider()


            HStack {

                Text(
                    "\(filteredSongs.count) song(s)"
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )

                if !libraryStore.missingSongIDs.isEmpty {

                    Text(
                        "\(libraryStore.missingSongIDs.count) missing"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                }


                Spacer()


                // MARK: Clean Up Missing Links

                if !libraryStore.missingSongIDs.isEmpty {

                    Button {

                        isShowingCleanUpSheet = true

                    } label: {

                        Label(
                            "Clean Up Missing Links…",
                            systemImage:
                                "trash"
                        )
                    }
                    .disabled(
                        libraryStore.isLocked
                    )
                    .help(
                        libraryStore.isLocked
                        ? "Unlock the Library to clean up missing tracks"
                        : "Remove tracks that were not found on disk at the last check from the Library"
                    )
                }


                // MARK: Add Files

                Button {

                    onAddFiles()

                } label: {

                    if scanner.isScanning {

                        Label(
                            "Adding…",
                            systemImage:
                                "folder.badge.plus"
                        )
                        .foregroundColor(
                            Color.red.opacity(0.6)
                        )

                    } else {

                        Label(
                            "Add Files",
                            systemImage:
                                "folder.badge.plus"
                        )
                    }
                }
                .disabled(
                    libraryStore.isLocked
                    || scanner.isScanning
                )
                .help(
                    libraryStore.isLocked
                    ? "Unlock the Library to import files"
                    : scanner.isScanning
                    ? "Import already in progress"
                    : "Import a folder of audio files"
                )


                // MARK: Save As…

                Button {

                    LibraryActions.saveLibraryLocally(
                        libraryStore:
                            libraryStore
                    )

                } label: {

                    Label(
                        "Save As…",
                        systemImage:
                            "square.and.arrow.down.on.square"
                    )
                }
                .disabled(
                    libraryStore.isLocked ||
                    libraryStore.songs.isEmpty
                )
                .help(
                    libraryStore.isLocked
                    ? "Unlock the Library to save it"
                    : "Save the current Library internally under a different name"
                )


                // MARK: Add / Insert to Set

                Toggle(
                    isOn:
                        Binding(
                            get: {
                                setInsertionMode == .insert
                            },
                            set: { isInsert in
                                setInsertionMode =
                                    isInsert
                                    ? .insert
                                    : .add
                            }
                        )
                ) {

                    Label(
                        setInsertionMode.buttonTitle,
                        systemImage:
                            setInsertionMode.systemImage
                    )
                }
                .toggleStyle(
                    SetInsertionToggleStyle()
                )
                .help(
                    setInsertionMode.helpText
                )
            }
            .padding(
                8
            )
        }

        // MARK: Error

        .alert(
            "Library",
            isPresented:
                Binding(
                    get: {
                        libraryErrorMessage != nil
                    },
                    set: { value in

                        if !value {

                            libraryErrorMessage =
                                nil
                        }
                    }
                )
        ) {

            Button(
                "OK"
            ) {

                libraryErrorMessage =
                    nil
            }

        } message: {

            Text(
                libraryErrorMessage ?? ""
            )
        }

        // MARK: Clean Up Missing Links Sheet

        .sheet(
            isPresented:
                $isShowingCleanUpSheet
        ) {

            CleanUpMissingLinksView(
                missingSongs:
                    libraryStore.songs.filter {
                        $0.id.map(
                            libraryStore.missingSongIDs.contains
                        ) ?? false
                    },
                onCancel: {
                    isShowingCleanUpSheet = false
                },
                onConfirm: {
                    confirmCleanUp()
                }
            )
        }

        .alert(
            "Couldn't Clean Up Library",
            isPresented:
                Binding(
                    get: {
                        cleanUpErrorMessage != nil
                    },
                    set: { value in

                        if !value {
                            cleanUpErrorMessage = nil
                        }
                    }
                )
        ) {

            Button("OK") {
                cleanUpErrorMessage = nil
            }

        } message: {

            Text(
                cleanUpErrorMessage ?? ""
            )
        }
    }


    // MARK: - Clean Up Missing Links

    private func confirmCleanUp() {

        let ids =
            libraryStore.missingSongIDs

        isShowingCleanUpSheet = false

        do {

            try libraryStore.deleteSongs(
                ids: ids
            )

        } catch {

            cleanUpErrorMessage =
                error.localizedDescription
        }
    }


    // MARK: - Filtered Songs

    private var filteredSongs:
        [Song] {

        switch selection {

        case .showAll:

            return filterByDanceType(
                libraryStore.songs
            )


        case .node(let node)
            where !node.isFolder:

            let smartlistFiltered =
                node.ruleSet.map {

                    SmartListFilter.apply(
                        $0,
                        to:
                            libraryStore.songs
                    )

                } ?? libraryStore.songs

            // The smartlist's own filter is always applied first.
            // The A/T/V/M/X dance filter is applied ON TOP of that
            // ONLY when the smartlist's name doesn't already encode
            // a single defined dance type (mirrors ContentView's
            // trackDanceFilterButtonsShouldShow) — otherwise a stale
            // danceFilter selection left over from Show All could
            // silently narrow a defined-genre Smartlist's results
            // even while its buttons appear disabled.
            return hasDefinedGenre(node)
                ? smartlistFiltered
                : filterByDanceType(smartlistFiltered)


        default:

            return libraryStore.songs
        }
    }


    // MARK: - Smartlist Defined-Genre Check
    //
    // Naming convention: ###_<genre>_<artist>_<albumartist>_<year>.
    // Genre component exactly "T"/"V"/"M" (case-insensitive) counts as
    // defined. Anything else — "TVM"/"All"/"Mix", or a name that
    // doesn't match this pattern at all — counts as not defined.
    private func hasDefinedGenre(
        _ node: SmartlistNode
    ) -> Bool {

        let components =
            node.name.components(
                separatedBy: "_"
            )

        guard components.count >= 2 else {
            return false
        }

        let genreToken =
            components[1]
                .trimmingCharacters(
                    in: .whitespaces
                )
                .lowercased()

        let definedGenreTokens:
            Set<String> = ["t", "v", "m"]

        return definedGenreTokens.contains(
            genreToken
        )
    }


    // MARK: - Track Dance-Type Filter

    /// Applies the TrackLibrary A/T/M/V/X selection. This filter is
    /// deliberately used only for Show All. When a Smartlist is active,
    /// the Smartlist rule set remains the sole active filter.
    ///
    /// Matching is substring-based ("contains"), against a genre tag
    /// normalized once per song (case- and diacritic-insensitive).
    /// Milonga also covers Candombe, Foxtrot, and Otra — Tandas of
    /// those genres are conventionally grouped with Milonga. X (Various
    /// Genres) is not its own tag to match against; it's the
    /// complement of T/M/V — anything (including an empty/missing
    /// genre tag) that matches none of the three.
    private func filterByDanceType(
        _ songs: [Song]
    ) -> [Song] {

        switch danceFilter {

        case .all:

            return songs

        case .tango:

            return songs.filter {
                isTango(
                    normalizedGenre($0.genre)
                )
            }

        case .vals:

            return songs.filter {
                isVals(
                    normalizedGenre($0.genre)
                )
            }

        case .milonga:

            return songs.filter {
                isMilonga(
                    normalizedGenre($0.genre)
                )
            }

        case .variousGenres:

            return songs.filter {

                let genre =
                    normalizedGenre($0.genre)

                return !isTango(genre)
                    && !isVals(genre)
                    && !isMilonga(genre)
            }
        }
    }


    /// Case- and diacritic-insensitive, whitespace-trimmed. Computed
    /// once per song rather than inside every isXXX() call.
    private func normalizedGenre(
        _ genre: String?
    ) -> String {

        (genre ?? "")
            .folding(
                options: [
                    .diacriticInsensitive,
                    .caseInsensitive
                ],
                locale:
                    nil
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }

    private func isTango(
        _ normalizedGenre: String
    ) -> Bool {

        normalizedGenre.contains(
            "tango"
        )
    }

    private func isVals(
        _ normalizedGenre: String
    ) -> Bool {

        normalizedGenre.contains(
            "vals"
        )
    }

    /// Milonga, Candombe, Foxtrot, and Otra are all grouped under the
    /// Milonga bucket.
    private func isMilonga(
        _ normalizedGenre: String
    ) -> Bool {

        normalizedGenre.contains("milonga")
            || normalizedGenre.contains("candombe")
            || normalizedGenre.contains("foxtrot")
            || normalizedGenre.contains("otra")
    }
}


// MARK: - Set Insertion Mode

enum SetInsertionMode {

    case add
    case insert


    var buttonTitle:
        String {

        switch self {

        case .add:
            return "Add to Set"

        case .insert:
            return "Insert to Set"
        }
    }


    var systemImage:
        String {

        switch self {

        case .add:
            return "plus"

        case .insert:
            return "arrow.left.to.line"
        }
    }


    var helpText:
        String {

        switch self {

        case .add:

            return
                "Drag selected songs to add them to the end of the Setlist"

        case .insert:

            return
                "Drag selected songs to insert them at a position in the Setlist"
        }
    }
}


/// Background/border swap between the two `SetInsertionMode` states —
/// deliberately inverted (bg <-> border) rather than just recoloring
/// one element, so "Add" and "Insert" read as visually distinct, not
/// as one lit up and one dim.
struct SetInsertionToggleStyle: ToggleStyle {

    func makeBody(configuration: Configuration) -> some View {

        Button {

            configuration.isOn.toggle()

        } label: {

            configuration.label
                .padding(
                    .horizontal,
                    12
                )
                .padding(
                    .vertical,
                    5
                )
                .background(
                    RoundedRectangle(
                        cornerRadius:
                            8
                    )
                    .fill(
                        configuration.isOn
                        ? Color.blue
                        : Color(
                            red: 0.4,
                            green: 0.7,
                            blue: 1.0
                        )
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: 8
                    )
                    .stroke(
                        configuration.isOn
                        ? Color(
                            red: 0.4,
                            green: 0.7,
                            blue: 1.0
                        )
                        : Color.blue,
                        lineWidth: 3.5
                    )
                )
                .foregroundStyle(
                    .white
                )
        }
        .buttonStyle(
            .plain
        )
    }
}
