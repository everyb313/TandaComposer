//
//  TandaLibraryView.swift
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
import UniformTypeIdentifiers

struct TandaLibraryView:
    View {

    let folderSelection:
        TandaFolderSelection

    /// Local dance-type filter controlled by the A / T / V / M / X
    /// buttons in ContentView's Library header.
    ///
    /// The binding is deliberately only presentation/filter state.
    /// It does not alter TandaStore, the Tanda JSON files, or the
    /// existing folder-selection mechanism.
    @Binding
    var danceFilter:
        TandaDanceFilter

    /// Passed in from ContentView (hoisted there, shared with
    /// TandaFolderTreeView too) instead of owned here — this view used
    /// to have its own `@StateObject var store = TandaStore()`, which
    /// meant every switch to this display mode created a BRAND NEW
    /// TandaStore, re-reading every single Tanda JSON file from disk
    /// synchronously, even switching back to a view you'd just been
    /// on a moment earlier. Owning it one level up means it survives
    /// mode switches and only reloads when something actually calls
    /// for it (Tanda saved/deleted/rescanned).
    @ObservedObject
    var store:
        TandaStore

    // Gates the Delete Tanda button — same lock LibraryTableView's own
    // Add Files button respects, so Tandas can't be deleted while the
    // Library is locked either (e.g. mid-set).
    @EnvironmentObject
    private var libraryStore:
        LibraryStore

    // Read for the Setlist-to-Tanda drop: the songs saved are whatever
    // is CURRENTLY selected in the Setlist at drop time, exactly like
    // the Save Tanda button — the drag itself carries no song data,
    // see onDrop below and SetlistView's pasteboardWriterForRow.
    @EnvironmentObject
    private var setlistStore:
        SetlistStore

    // Needed here (not just in TandaSongRow) for saveSetlistSelectionAsTanda()
    // -> TandaSaver.save(settings:), which resolves the Orchestra/Singer
    // folder naming.
    @EnvironmentObject
    private var settings:
        AppSettings

    // Independent of Library's own `setInsertionMode` — each view owns
    // its toggle locally (same pattern SmartListFilteredLibraryView
    // already uses), since Tracks and Tandas are never visible at the
    // same time anyway (swapped via the same libraryColumn switch).
    @State
    private var insertionMode:
        SetInsertionMode = .add

    // Set by single-clicking a Tanda's HEADER (not the whole block, not
    // song rows — those already have their own double-click-to-play).
    // `Tanda.sourceURL` is its stable identity (see Tanda.swift).
    @State
    private var selectedTandaURL:
        URL?

    @State
    private var pendingDeleteTanda:
        Tanda?

    @State
    private var deleteErrorMessage:
        String?

    @State
    private var saveErrorMessage:
        String?

    // Drop-hover visual feedback for the Setlist-to-Tanda drag — shared
    // across the background lane AND every TandaBlock, so exactly one
    // border can show at a time. See SetlistDropTarget's doc comment
    // above for why this is one value instead of independent booleans.
    @State
    private var currentDropTarget:
        SetlistDropTarget?

    // "Library is locked" hint shown while a Setlist drag hovers over (or
    // is released on) the Tanda Library while it's locked. Visible for
    // a short moment after the LAST such event rather than until an
    // exit callback — dropExited doesn't fire reliably for this drag
    // (see SetlistToTandaDropDelegate), so a hint that waited for one
    // could get stuck on screen.
    @State
    private var isShowingLockedHint =
        false

    @State
    private var lockedHintTask:
        Task<Void, Never>?

    // Status data (Status dots + bottom-bar counts) — starts empty and
    // fills in asynchronously AFTER the first frame, not before it.
    // Used to be computed synchronously inline in `body`, which meant
    // the whole view (even the plain Tanda/song list, which doesn't
    // need this at all) waited for a full Dictionary build from
    // ~8,000 Library songs before anything appeared on screen at all.
    // `nil` deliberately means "not computed yet" and is treated as
    // neutral (no dot) rather than "not in library" — see
    // `TandaBlock.status(for:)` — so switching to this tab never
    // flashes every track blue for a moment before the real data lands.
    @State
    private var libraryByID:
        [Int64: Song]?

    @State
    private var libraryByPath:
        [String: Song]?

    @State
    private var statusCounts =
        TandaLibraryStatusCounts()


    var body:
        some View {

        VStack(
            spacing:
                0
        ) {

            ScrollView(
                [.horizontal, .vertical]
            ) {

                // LazyVStack, not VStack — with a plain VStack here,
                // SwiftUI has to construct and lay out EVERY TandaBlock
                // (header, comment field, all song rows, drag handlers)
                // for all ~100 Tandas immediately, regardless of how
                // many are actually visible in the viewport.
                // That's independent of (and apparently bigger than)
                // the status-dot computation deferred above — this was
                // very likely the real remaining cost behind "switch
                // feels the same". LazyVStack only builds the blocks
                // that are actually on/near screen.
                LazyVStack(
                    alignment:
                        .leading,
                    spacing:
                        8
                ) {

                    ForEach(
                        filteredTandas
                    ) { tanda in

                        HStack(
                            spacing:
                                8
                        ) {

                            // =========================================
                            // NEW-TANDA LANE
                            //
                            // Runs alongside EVERY row (not just once at
                            // the top) so the "drop here to create a new
                            // Tanda" target is always within reach of
                            // wherever you're scrolled to — dropping
                            // directly on a Tanda block appends to it
                            // instead (TandaBlock's own onDrop below).
                            // This view draws no border/onDrop itself —
                            // it's plain empty space that belongs to the
                            // ScrollView's own onDrop by simply not being
                            // claimed by anything else, so hovering here
                            // triggers the SAME feedback as the ScrollView
                            // background (see the .overlay/.onDrop moved
                            // onto the ScrollView itself, below).
                            NewTandaLaneMarker()

                            TandaBlock(
                                tanda:
                                    tanda,
                                insertionMode:
                                    insertionMode,
                                isSelected:
                                    tanda.sourceURL ==
                                        selectedTandaURL,
                                libraryByID:
                                    libraryByID,
                                libraryByPath:
                                    libraryByPath,
                                missingSongIDs:
                                    libraryStore.missingSongIDs,
                                currentDropTarget:
                                    $currentDropTarget,
                                onSelectHeader: {

                                    // Toggle: clicking the header of the
                                    // ALREADY-selected Tanda deselects
                                    // it, rather than only ever being
                                    // able to select a DIFFERENT one to
                                    // get away from the current
                                    // selection.
                                    //
                                    // Also drops any leftover drop-hover
                                    // target: a drag that ended without
                                    // dropExited firing would otherwise
                                    // leave a stale accepted-state ring.
                                    currentDropTarget = nil

                                    if selectedTandaURL == tanda.sourceURL {
                                        selectedTandaURL = nil
                                    } else {
                                        selectedTandaURL = tanda.sourceURL
                                    }
                                },
                                onCommitComment: { newComment in

                                    do {
                                        try TandaLibraryActions.commitComment(
                                            newComment,
                                            for: tanda,
                                            store: store
                                        )
                                    } catch {
                                        saveErrorMessage = error.localizedDescription
                                    }
                                },
                                onDeleteSong: { songIndex in

                                    do {
                                        try TandaLibraryActions.deleteSong(
                                            at: songIndex,
                                            from: tanda,
                                            store: store
                                        )
                                    } catch {
                                        saveErrorMessage = error.localizedDescription
                                    }
                                },
                                onDropAppend: {

                                    do {
                                        try TandaLibraryActions.appendSetlistSelectionToTanda(
                                            tanda,
                                            store: store,
                                            libraryStore: libraryStore,
                                            setlistStore: setlistStore
                                        )
                                    } catch {
                                        saveErrorMessage = error.localizedDescription
                                    }
                                },
                                onLockedDropAttempt: {

                                    showLockedHint()
                                }
                            )
                        }
                    }
                }
                .padding(
                    8
                )
            }


            // =====================================================
            // SETLIST → TANDA (SAVE AS TANDA BY DROP)
            //
            // Attached to the ScrollView itself (list content only)
            // rather than the whole TandaLibraryView pane — moved here
            // from the outer VStack specifically so the accepted-drop
            // border matches "the table + the new-Tanda lane", not the
            // Set-header row or the bottom bar too, AND so it tracks
            // the ScrollView's own (viewport-sized) frame rather than
            // the LazyVStack's full, mostly-off-screen-while-scrolled
            // content height — attaching it inside the ScrollView, to
            // the LazyVStack, would mean the border's edges are
            // themselves scrolled out of view most of the time. The
            // drag itself carries no song data (see SetlistView's
            // pasteboardWriterForRow) — it's only a trigger. What
            // actually gets saved is whatever is CURRENTLY selected in
            // the Setlist at the moment of the drop, exactly like the
            // Save Tanda button. Drop position within this area is
            // irrelevant as long as it isn't a specific TandaBlock
            // (which appends instead, via ITS OWN onDrop — see
            // TandaBlock/SetlistToTandaDropDelegate — which SwiftUI
            // resolves to in preference to this one whenever the drop
            // point is actually over a block).
            // =====================================================

            .overlay(
                setlistDropFeedback(
                    isTargeted:
                        currentDropTarget == .background,
                    isLocked:
                        libraryStore.isLocked,
                    cornerRadius:
                        8
                )
            )
            // Single "+" hint for the new-Tanda lane — one, centered
            // on the ScrollView's own fixed viewport, NOT one per row
            // (that looked cluttered with a long Tanda list). Its
            // horizontal offset (8 + half the lane width) centers it
            // within the lane column, matching the LazyVStack's own
            // 8pt padding above. Hidden entirely while the Library is
            // locked — dropping here wouldn't work anyway (same lock
            // that gates Delete Tanda etc.), so showing it would just
            // invite a drop that's guaranteed to fail.
            .overlay(
                alignment:
                    .leading
            ) {

                if !libraryStore.isLocked {

                    Image(
                        systemName: "plus"
                    )
                    .font(
                        .system(size: 15, weight: .bold)
                    )
                    .foregroundStyle(
                        currentDropTarget == .background
                        ? Color.accentColor
                        : Color.secondary.opacity(0.35)
                    )
                    .frame(
                        width: NewTandaLaneMarker.width
                    )
                    .padding(
                        .leading,
                        8
                    )
                }
            }
            // "Library is locked" hint — shown while a Setlist drag
            // hovers over / is released on the Tanda Library while
            // it's locked (see showLockedHint). Not hit-testable, so
            // it can never get in the way of the drop targets under it.
            .overlay(
                alignment:
                    .top
            ) {

                if isShowingLockedHint &&
                    libraryStore.isLocked {

                    Label(
                        "Library is locked — unlock it to add tracks",
                        systemImage:
                            "lock.fill"
                    )
                    .font(
                        .system(size: 12, weight: .semibold)
                    )
                    .foregroundStyle(
                        .white
                    )
                    .padding(
                        .horizontal,
                        12
                    )
                    .padding(
                        .vertical,
                        6
                    )
                    .background(
                        Color.orange,
                        in: Capsule()
                    )
                    .padding(
                        .top,
                        10
                    )
                    .allowsHitTesting(
                        false
                    )
                    .transition(
                        .opacity
                    )
                }
            }
            .animation(
                .easeInOut(duration: 0.15),
                value:
                    isShowingLockedHint
            )
            .onDrop(
                of:
                    [.text],
                delegate:
                    SetlistToTandaDropDelegate(
                        isLocked:
                            libraryStore.isLocked,
                        target:
                            .background,
                        current:
                            $currentDropTarget,
                        onDrop: {

                            do {
                                try TandaLibraryActions.saveSetlistSelectionAsTanda(
                                    store: store,
                                    libraryStore: libraryStore,
                                    setlistStore: setlistStore,
                                    settings: settings
                                )
                            } catch {
                                saveErrorMessage = error.localizedDescription
                            }
                        },
                        onLockedAttempt: {

                            showLockedHint()
                        }
                    )
            )
            // The accepted-state drop ring is only drawn while
            // unlocked, so a stale `currentDropTarget` (a drag that
            // ended without dropExited — see SetlistToTandaDropDelegate)
            // stays invisible while locked and used to pop up as a
            // second, inner border around a Tanda the moment the
            // Library was unlocked. Nothing is being dragged when the
            // lock is toggled, so there is never a valid target to keep.
            .onChange(
                of:
                    libraryStore.isLocked
            ) { _, _ in

                currentDropTarget = nil
            }


            Divider()


            // =====================================================
            // BOTTOM BAR
            // =====================================================

            HStack {

                Text(
                    "\(filteredTandas.count) tanda(s)"
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )

                if statusCounts.missing > 0 {

                    Label(
                        "\(statusCounts.missing) missing",
                        systemImage:
                            "octagon.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help(
                        "File not found on disk at last TrackLibrary rescan. If the file moved, run \"Rescan TrackLibrary\", then \"Rescan TandaLibrary\" to re-link it here."
                    )
                }

                if statusCounts.notInLibrary > 0 {

                    Label(
                        "\(statusCounts.notInLibrary) not in library",
                        systemImage:
                            "questionmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .help(
                        "This track's Library entry no longer exists (removed or never imported)."
                    )
                }

                if statusCounts.stale > 0 {

                    Label(
                        "\(statusCounts.stale) outdated",
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(
                        "The TrackLibrary already found this file at a new location, but this Tanda hasn't been re-linked to it yet — it will fail to play. Run \"Rescan TandaLibrary\" (Tools menu) to fix it."
                    )
                }


                Spacer()


                // =====================================================
                // DELETE TANDA
                //
                // Acts on the currently SELECTED Tanda (single-click on
                // its header). Disabled with nothing selected.
                // =====================================================

                Button(
                    role:
                        .destructive
                ) {

                    pendingDeleteTanda =
                        selectedTanda

                } label: {

                    Label(
                        "Delete Tanda",
                        systemImage:
                            "trash"
                    )
                }
                .disabled(
                    selectedTanda == nil ||
                    libraryStore.isLocked
                )
                .help(
                    libraryStore.isLocked
                    ? "Unlock the Library to delete Tandas"
                    : selectedTanda == nil
                    ? "Select a Tanda first"
                    : "Delete the selected Tanda"
                )


                // =====================================================
                // ADD / INSERT TO SET
                //
                // Same style/component as Library's toggle
                // (SmartListFilteredLibraryView.swift) — sets the
                // mode for the NEXT drag of a Tanda block into the
                // Setlist, exactly like Library: this button doesn't
                // itself add anything, dragging does.
                // =====================================================

                Toggle(
                    isOn:
                        Binding(
                            get: {

                                insertionMode == .insert
                            },
                            set: { isInsert in

                                insertionMode =
                                    isInsert
                                    ? .insert
                                    : .add
                            }
                        )
                ) {

                    Label(
                        insertionMode.buttonTitle,
                        systemImage:
                            insertionMode.systemImage
                    )
                }
                .toggleStyle(
                    SetInsertionToggleStyle()
                )
                .help(
                    insertionMode.helpText
                )
            }
            .padding(
                8
            )
        }
        .confirmationDialog(
            "Delete Tanda \"\(pendingDeleteTanda?.name ?? "")\"?",
            isPresented:
                .constant(
                    pendingDeleteTanda != nil
                ),
            presenting:
                pendingDeleteTanda
        ) { tanda in

            Button(
                "Delete",
                role:
                    .destructive
            ) {

                do {
                    try TandaLibraryActions.deleteTanda(tanda, store: store)
                    if selectedTandaURL == tanda.sourceURL {
                        selectedTandaURL = nil
                    }
                } catch {
                    deleteErrorMessage = error.localizedDescription
                }
                pendingDeleteTanda = nil
            }

            Button(
                "Cancel",
                role:
                    .cancel
            ) {

                pendingDeleteTanda =
                    nil
            }

        } message: { _ in

            Text(
                "This permanently deletes the Tanda's saved file. This cannot be undone."
            )
        }
        .alert(
            "Couldn't Delete Tanda",
            isPresented:
                .constant(
                    deleteErrorMessage != nil
                ),
            presenting:
                deleteErrorMessage
        ) { _ in

            Button(
                "OK"
            ) {

                deleteErrorMessage =
                    nil
            }

        } message: { message in

            Text(
                message
            )
        }
        .alert(
            "Couldn't Save Tanda",
            isPresented:
                .constant(
                    saveErrorMessage != nil
                ),
            presenting:
                saveErrorMessage
        ) { _ in

            Button(
                "OK"
            ) {

                saveErrorMessage =
                    nil
            }

        } message: { message in

            Text(
                message
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    AppNotification.tandaSaved
            )
        ) { _ in

            store.reload()

            Task {
                let result = TandaLibraryStatusResolver.resolve(
                    tandas: filteredTandas,
                    libraryStore: libraryStore
                )
                libraryByID = result.libraryByID
                libraryByPath = result.libraryByPath
                statusCounts = result.counts
            }
        }
        .task(
            id:
                TandaLibraryTaskTrigger(
                    songIDs:
                        libraryStore.songs.map(\.id),
                    missingSongIDs:
                        libraryStore.missingSongIDs,
                    tandaCount:
                        filteredTandas.count
                )
        ) {
            let result = TandaLibraryStatusResolver.resolve(
                tandas: filteredTandas,
                libraryStore: libraryStore
            )
            libraryByID = result.libraryByID
            libraryByPath = result.libraryByPath
            statusCounts = result.counts
        }
    }

    // MARK: - Locked-Library Hint

    private func showLockedHint() {
        isShowingLockedHint = true

        lockedHintTask?.cancel()

        lockedHintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            guard !Task.isCancelled else {
                return
            }

            isShowingLockedHint = false
        }
    }


    private var selectedTanda:
        Tanda? {

        filteredTandas.first {
            $0.sourceURL ==
                selectedTandaURL
        }
    }


    private var filteredTandas: [Tanda] {
        TandaLibraryFiltering.filteredTandas(
            store: store,
            folderSelection: folderSelection,
            danceFilter: danceFilter
        )
    }
}
