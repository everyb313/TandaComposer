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
import AppKit
import UniformTypeIdentifiers


// MARK: - Tanda Dance Filter

enum TandaDanceFilter:
    String,
    CaseIterable,
    Identifiable,
    Equatable {

    case all
    case tango
    case vals
    case milonga
    case variousGenres

    var id:
        Self {
        self
    }

    var title:
        String {

        switch self {

        case .all:
            return "A"

        case .tango:
            return "T"

        case .vals:
            return "V"

        case .milonga:
            return "M"

        case .variousGenres:
            return "X"
        }
    }

    var helpText:
        String {

        switch self {

        case .all:
            return "Show all dance types"

        case .tango:
            return "Show Tango only"

        case .vals:
            return "Show Vals only"

        case .milonga:
            return "Show Milonga only"

        case .variousGenres:
            return "Show VariousGenres only"
        }
    }

    /// Exact second component expected in the Tanda filename.
    ///
    /// Examples:
    ///
    /// Artist_Tango_...json
    /// Artist_Vals_...json
    /// Artist_Milonga_...json
    /// Artist_VariousGenres_...json
    ///
    /// The third component, such as VariousSingers, is deliberately
    /// not used for dance-type filtering.
    var filenameComponent:
        String? {

        switch self {

        case .all:
            return nil

        case .tango:
            return "Tango"

        case .vals:
            return "Vals"

        case .milonga:
            return "Milonga"

        case .variousGenres:
            return "VariousGenres"
        }
    }
}


// MARK: - Shared "Setlist → Tanda" Drop Handling
//
// Both drop targets in this file (TandaLibraryView's own background —
// "create a new Tanda" — and each individual TandaBlock — "append to
// this Tanda") accept a drag carrying the "setlist-to-tanda" marker
// and share this exact logic; only WHAT happens on a successful drop
// differs, passed in via `onDrop`.

/// Identifies which SINGLE "Setlist → Tanda" drop target currently has
/// an active drag hovering over it — the background lane (create new)
/// or one specific TandaBlock (append). Using one shared value instead
/// of independent per-target booleans is what guarantees exactly one
/// blue border shows at a time: whichever target's dropUpdated fires
/// most recently simply overwrites this, automatically "turning off"
/// whichever OTHER target was previously set — without needing
/// dropExited (unreliable for this drag on macOS, see below) to fire
/// on the one being left. Two independent booleans could easily both
/// end up true at once (background stuck true from before + a
/// TandaBlock now also true), which is exactly the double-border bug
/// this replaces.
private enum SetlistDropTarget: Equatable {
    case background
    case tanda(URL)
}

// Uses the DropDelegate protocol rather than the isTargeted-closure
// form of .onDrop specifically so dropUpdated(info:) can return an
// explicit `.forbidden` DropProposal while the Library is locked.
// THAT is what makes macOS show the system "not allowed" cursor
// during hover instead of the misleading "+N" badge — the old
// closure-form code only rejected the drop AFTER it was released
// (inside the closure's own `guard !libraryStore.isLocked else {
// return false }`), which is too late to affect the hover cursor;
// the "+N" had already been shown for the whole hover.
//
// One more macOS quirk this delegate works around: dropEntered/
// dropExited turned out not to fire reliably for this kind of drag,
// while dropUpdated (confirmed by the cursor itself correctly
// flipping color) does, continuously, while hovering. So dropUpdated
// below is the ONLY reliable place `current` gets set — there's no
// dropEntered override at all, and dropExited (kept anyway, for the
// cases where it does fire) is explicitly best-effort.

private struct SetlistToTandaDropDelegate: DropDelegate {

    let isLocked: Bool
    /// Which target THIS delegate instance represents (.background for
    /// TandaLibraryView's own drop zone, .tanda(url) for one TandaBlock).
    let target: SetlistDropTarget
    /// The one shared "currently hovered target" — see
    /// SetlistDropTarget's doc comment above for why this is a single
    /// value instead of a per-target Bool.
    let current: Binding<SetlistDropTarget?>
    let onDrop: () -> Void

    /// Best-effort cleanup (see the struct-level note above) — only
    /// clears if WE are still the current target, so a stale/late
    /// call for a target you've already left doesn't wipe out
    /// whatever you've since moved onto.
    func dropExited(info: DropInfo) {

        if current.wrappedValue == target {
            current.wrappedValue = nil
        }
    }

    /// The reliable source of both the hover cursor feedback AND the
    /// border feedback (see the struct-level note above for why this,
    /// not dropEntered, is where `current` gets set). Unconditionally
    /// overwriting `current` with our own `target` on every call is
    /// what makes setlistDropFeedback's accepted-state ring appear for
    /// exactly one target at a time — moving onto a different target
    /// just overwrites this again.
    func dropUpdated(info: DropInfo) -> DropProposal? {

        current.wrappedValue = target

        return DropProposal(
            operation:
                isLocked
                ? .forbidden
                : .copy
        )
    }

    func validateDrop(info: DropInfo) -> Bool {

        !isLocked &&
        info.hasItemsConforming(
            to: [.text]
        )
    }

    func performDrop(info: DropInfo) -> Bool {

        current.wrappedValue = nil

        guard !isLocked else {
            return false
        }

        guard
            let provider =
                info.itemProviders(for: [.text]).first
        else {
            return false
        }

        _ =
            provider.loadObject(
                ofClass:
                    NSString.self
            ) { reading, _ in

                guard
                    let marker =
                        reading as? String,
                    marker == "setlist-to-tanda"
                else {
                    return
                }

                DispatchQueue.main.async {

                    onDrop()
                }
            }

        return true
    }
}


/// Accent-colored ring shown while a "Setlist → Tanda" drag hovers
/// over a target that would actually accept it (Library unlocked).
/// Shown nothing while locked — Part A (SetlistToTandaDropDelegate's
/// `.forbidden` DropProposal, which drives the system cursor itself)
/// is the sole locked-state feedback; a previous version of this also
/// drew a red ring + text message here for the locked case, removed
/// again as redundant/not rendering usefully in practice.
@ViewBuilder
private func setlistDropFeedback(
    isTargeted: Bool,
    isLocked: Bool,
    cornerRadius: CGFloat
) -> some View {

    if isTargeted && !isLocked {

        RoundedRectangle(
            cornerRadius: cornerRadius
        )
        .stroke(
            Color.accentColor,
            lineWidth: 3
        )
        .padding(4)
    }
}


/// The permanent "drop here to create a new Tanda" lane running
/// alongside every row in the Tanda Library — see the ForEach in
/// TandaLibraryView.body for why this needs to run the FULL height of
/// the list rather than appearing once. Draws no border/onDrop of its
/// own; it's deliberately plain empty space that the ScrollView's own
/// onDrop (see setlistDropFeedback/SetlistToTandaDropDelegate above)
/// picks up simply because nothing else claims it.
/// The permanent "drop here to create a new Tanda" lane running
/// alongside every row in the Tanda Library — see the ForEach in
/// TandaLibraryView.body for why this needs to run the FULL height of
/// the list rather than appearing once. Just a plain tintable rectangle,
/// no icon of its own — the single "+" hint lives once, centered on the
/// ScrollView's own (viewport-fixed) overlay below, not repeated per
/// row. Draws no border/onDrop of its own; it's deliberately plain
/// empty space that the ScrollView's own onDrop (see
/// setlistDropFeedback/SetlistToTandaDropDelegate above) picks up
/// simply because nothing else claims it.
/// The permanent "drop here to create a new Tanda" lane running
/// alongside every row in the Tanda Library — see the ForEach in
/// TandaLibraryView.body for why this needs to run the FULL height of
/// the list rather than appearing once. Completely empty on purpose —
/// no per-row fill/tint — the ONLY visual feedback for this lane is
/// the single "+" and the big accent border, both centered/drawn once
/// on the ScrollView's own overlay below, not repeated per row.
private struct NewTandaLaneMarker: View {

    static let width: CGFloat = 36

    var body: some View {

        Color.clear
            .frame(
                width: Self.width
            )
    }
}


// MARK: - Tanda Library View

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
    // see onDrop below and PlaylistView's pasteboardWriterForRow.
    @EnvironmentObject
    private var playlistStore:
        PlaylistStore

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
        StatusCounts()


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

                                    selectedTandaURL =
                                        tanda.sourceURL
                                },
                                onCommitComment: { newComment in

                                    commitComment(
                                        newComment,
                                        for: tanda
                                    )
                                },
                                onDeleteSong: { songIndex in

                                    deleteSong(
                                        at: songIndex,
                                        from: tanda
                                    )
                                },
                                onDropAppend: {

                                    appendSetlistSelectionToTanda(
                                        tanda
                                    )
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
            // drag itself carries no song data (see PlaylistView's
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

                            saveSetlistSelectionAsTanda()
                        }
                    )
            )


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

                deleteTanda(
                    tanda
                )
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
                    .tandaSaved
            )
        ) { _ in

            store.reload()

            Task {
                await refreshStatus()
            }
        }
        .task(
            id:
                TaskTrigger(
                    songIDs:
                        libraryStore.songs.map(\.id),
                    missingSongIDs:
                        libraryStore.missingSongIDs,
                    tandaCount:
                        filteredTandas.count
                )
        ) {

            await refreshStatus()
        }
    }

    /// `.task(id:)` restarts its work whenever this value changes —
    /// bundles everything `refreshStatus()` actually depends on so it
    /// re-runs exactly when the Library or the visible Tandas change,
    /// no more and no less.
    private struct TaskTrigger: Equatable {
        let songIDs: [Int64?]
        let missingSongIDs: Set<Int64>
        let tandaCount: Int
    }


    // MARK: - Save Setlist Selection As Tanda

    private func saveSetlistSelectionAsTanda() {

        guard
            !libraryStore.isLocked
        else {
            return
        }


        let songs =
            playlistStore.selectedRowIndexes.compactMap {
                index -> Song? in

                playlistStore.songs.indices.contains(index)
                    ? playlistStore.songs[index]
                    : nil
            }

        do {

            try TandaSaver.save(
                songs:
                    songs,
                existingTandas:
                    store.tandas,
                missingSongIDs:
                    libraryStore.missingSongIDs,
                settings:
                    settings
            )

        } catch {

            saveErrorMessage =
                error.localizedDescription
        }
    }


    // MARK: - Append Setlist Selection To Existing Tanda
    //
    // Counterpart to saveSetlistSelectionAsTanda() above — triggered
    // by dropping the Setlist selection directly onto a SPECIFIC
    // TandaBlock (its own onDrop, see TandaBlock below) rather than
    // onto the view's general background. Same "drag carries no song
    // data, read the Setlist's current selection at drop time" shape.

    private func appendSetlistSelectionToTanda(
        _ tanda:
            Tanda
    ) {

        guard
            !libraryStore.isLocked
        else {
            return
        }


        let songs =
            playlistStore.selectedRowIndexes.compactMap {
                index -> Song? in

                playlistStore.songs.indices.contains(index)
                    ? playlistStore.songs[index]
                    : nil
            }

        do {

            try store.addSongs(
                songs,
                to: tanda,
                missingSongIDs: libraryStore.missingSongIDs
            )

        } catch {

            saveErrorMessage =
                error.localizedDescription
        }
    }


    // MARK: - Delete Song From Tanda

    private func deleteSong(
        at songIndex:
            Int,
        from tanda:
            Tanda
    ) {

        do {

            try store.removeSong(
                at: songIndex,
                from: tanda
            )

        } catch {

            saveErrorMessage =
                error.localizedDescription
        }
    }


    // MARK: - Comment

    private func commitComment(
        _ newComment:
            String,
        for tanda:
            Tanda
    ) {

        // No-op if unchanged — avoids a pointless disk write (and a
        // spurious .tandaSaved-triggered reload elsewhere) every time
        // the field simply loses focus without being edited.
        guard
            newComment != tanda.comment
        else {
            return
        }

        do {

            try store.updateComment(
                for: tanda,
                to: newComment
            )

        } catch {

            saveErrorMessage =
                error.localizedDescription
        }
    }


    // MARK: - Delete

    private func deleteTanda(
        _ tanda:
            Tanda
    ) {

        do {

            try store.delete(
                tanda
            )

            if selectedTandaURL ==
                tanda.sourceURL {

                selectedTandaURL =
                    nil
            }

        } catch {

            deleteErrorMessage =
                error.localizedDescription
        }

        pendingDeleteTanda =
            nil
    }


    // MARK: - Selected Tanda

    private var selectedTanda:
        Tanda? {

        filteredTandas.first {
            $0.sourceURL ==
                selectedTandaURL
        }
    }


    // MARK: - Status Refresh (Deferred)
    //
    // Builds the Library-by-id Dictionary AND the status counts
    // together, off the synchronous `body` path — called from
    // `.task`/`.onChange` below, never inline in `body`, so switching
    // to this tab always shows the Tanda list itself immediately and
    // lets the red/blue/orange dots and counts fill in a moment later
    // instead of blocking the whole view on an 8,000-entry Dictionary
    // build first.
    private struct StatusCounts {
        var missing = 0
        var notInLibrary = 0
        var stale = 0
    }

    private func refreshStatus() async {

        // A plain (non-detached) Task inherits this view's actor
        // context, so this still runs on the MainActor — but critically
        // it runs on the NEXT run-loop turn, after SwiftUI has already
        // committed the first frame with the Tanda list visible. That
        // alone is what makes the tab switch feel instant: the actual
        // amount of work is unchanged, only WHEN it happens relative to
        // the first paint.
        //
        // Reuses LibraryStore's own cached lookups (built once there
        // whenever `songs` changes) instead of rebuilding an
        // equivalent Dictionary here on every refresh.
        let byID =
            libraryStore.songsByID

        let byPath =
            libraryStore.songsByNormalizedPath

        var counts = StatusCounts()

        for tanda in filteredTandas {

            // A Tanda copied in from a DIFFERENT TrackLibrary carries
            // that library's song ids — independently auto-incremented,
            // so a matching id here would be coincidence, not
            // identity, and would silently count/display the WRONG
            // song's status. `trustID` gates that: false skips id
            // matching entirely for this Tanda's songs, falling
            // through to path matching only (see
            // LibraryReferenceResolver).
            let trustID =
                tanda.savedAgainstLibraryName == AppPaths.currentLibraryName

            for song in tanda.songs {

                let resolution =
                    LibraryReferenceResolver.resolve(
                        song,
                        byID: byID,
                        byPath: byPath,
                        missingSongIDs: libraryStore.missingSongIDs,
                        trustID: trustID
                    )

                guard resolution.live != nil else {
                    counts.notInLibrary += 1
                    continue
                }

                if resolution.isMissing {

                    counts.missing += 1

                } else if resolution.pathChanged {

                    counts.stale += 1
                }
            }
        }

        libraryByID = byID
        libraryByPath = byPath
        statusCounts = counts
    }


    // MARK: - Filtered Tandas
    //
    // Filtering is deliberately performed in TWO stages:
    //
    // 1. Existing TandaFolderTreeView folder selection
    // 2. Local A/T/V/M/X dance-type filter
    //
    // The dance filter therefore acts as an ADD-ON to the existing
    // artist/folder preselection mechanism.
    //
    // Filename convention:
    //
    //     Artist_DanceType_ThirdComponent.json
    //
    // Examples:
    //
    //     Biagi_Tango_Duval.json
    //         -> Tango
    //
    //     Demare_Vals_Beron.json
    //         -> Vals
    //
    //     Federico_Milonga_VariousSingers.json
    //         -> Milonga
    //
    //     Rodriguez_VariousGenres_VariousSingers.json
    //         -> VariousGenres
    //
    //     Donato_Tango_VariousSingers.json
    //         -> Tango, NOT VariousGenres
    //
    // Only the SECOND underscore-separated filename component is
    // examined. The third component (`VariousSingers`, etc.) has
    // absolutely no effect on the dance filter.
    private var filteredTandas:
        [Tanda] {

        let folderFilteredTandas:
            [Tanda]

        switch folderSelection {

        case .showAll:

            folderFilteredTandas =
                store.tandas

        case .folder(let path):

            folderFilteredTandas =
                store.tandas.filter {

                    $0.sourceFolder == path ||
                    $0.sourceFolder.hasPrefix(
                        "\(path)/"
                    )
                }
        }

        let danceFilteredTandas:
            [Tanda]

        if let requiredComponent =
            danceFilter.filenameComponent {

            danceFilteredTandas =
                folderFilteredTandas.filter { tanda in

                    let filename =
                        tanda.sourceURL
                            .deletingPathExtension()
                            .lastPathComponent

                    let components =
                        filename.split(
                            separator:
                                "_",
                            omittingEmptySubsequences:
                                false
                        )

                    // Expected filename structure:
                    //
                    // Artist_DanceType_ThirdComponent
                    //
                    // We require at least two components because
                    // component #2 is the dance type.
                    guard
                        components.count >= 2
                    else {
                        return false
                    }

                    return components[1] ==
                        requiredComponent
                }

        } else {

            // A = all dance types, but STILL only within the
            // currently selected folder.
            danceFilteredTandas =
                folderFilteredTandas
        }

        // Alphabetical by displayed name, regardless of the
        // (essentially arbitrary, filesystem-enumeration-order)
        // order `store.tandas` itself is in.
        return danceFilteredTandas.sorted {

            $0.name.localizedStandardCompare(
                $1.name
            ) == .orderedAscending
        }
    }
}


// MARK: - Tanda Block

private struct TandaBlock:
    View {

    let tanda:
        Tanda

    let insertionMode:
        SetInsertionMode

    let isSelected:
        Bool

    let libraryByID:
        [Int64: Song]?

    let libraryByPath:
        [String: Song]?

    let missingSongIDs:
        Set<Int64>

    /// The ONE shared "which target is currently hovered" state from
    /// TandaLibraryView — see SetlistDropTarget's doc comment for why
    /// this is passed in rather than each TandaBlock keeping its own
    /// independent @State (that's exactly what let two borders show
    /// at once before).
    let currentDropTarget:
        Binding<SetlistDropTarget?>

    let onSelectHeader:
        () -> Void

    let onCommitComment:
        (String) -> Void

    /// Removes the song at this index (within `tanda.songs`) from
    /// the Tanda — the per-row delete button below.
    let onDeleteSong:
        (Int) -> Void

    /// Fired when the current Setlist selection is dropped directly
    /// onto THIS block (as opposed to the Tanda Library's general
    /// background, which creates a brand-new Tanda instead — see
    /// TandaLibraryView's own onDrop). The drag carries no song data;
    /// this only triggers the parent to read the Setlist's current
    /// selection.
    let onDropAppend:
        () -> Void

    // Local editable copy — TextField needs a two-way Binding, and
    // `tanda` is a `let` parameter here (owned/passed down by the
    // parent's ForEach), so this mirrors it for editing and only
    // reports back via onCommitComment when the user actually commits
    // an edit (submit or focus loss), not on every keystroke.
    @State
    private var commentDraft:
        String = ""

    @FocusState
    private var commentFieldIsFocused:
        Bool

    /// Whether THIS Tanda is the one currently hovered for an append
    /// drop — computed from the shared `currentDropTarget`, not its
    /// own @State (see that property's doc comment above).
    private var isTargetedForAppend:
        Bool {

        currentDropTarget.wrappedValue ==
            .tanda(tanda.sourceURL)
    }

    /// Whether Tanda A's "selected" indicators — the accent border AND
    /// the per-row delete "x"s — should currently show. Both are tied
    /// to this ONE property (not to `isSelected` directly) so they
    /// always change together, never one without the other:
    /// - Not selected at all → false, always.
    /// - Selected, no Setlist drag active right now → true.
    /// - Selected, AND a drag is currently hovering somewhere ELSE
    ///   (the background lane, or a different Tanda) → false. Seeing
    ///   this Tanda's "you can delete tracks here" x's while a drag is
    ///   visibly aimed at a DIFFERENT Tanda would be a stale, confusing
    ///   signal — so both stand down together while that's happening.
    /// - Selected, AND the drag is hovering THIS Tanda (about to
    ///   append here) → true. Being the current drop target doesn't
    ///   conflict with being selected — they're about the same block,
    ///   so both stay visible (deliberately chosen; the alternative of
    ///   also hiding them here was considered and rejected).
    private var showsSelectionState:
        Bool {

        guard isSelected else {
            return false
        }

        guard
            let target = currentDropTarget.wrappedValue
        else {
            return true
        }

        return target == .tanda(tanda.sourceURL)
    }

    // Gates the append-drop and the per-row delete button, same lock
    // as everything else that mutates a Tanda (Delete Tanda, Add
    // Files, the "create new Tanda" drop).
    @EnvironmentObject
    private var libraryStore:
        LibraryStore

    /// Fixed width of the leading delete-button column, shared between
    /// the column header (as a leading spacer) and every song row, so
    /// the two stay aligned regardless of whether the button is
    /// currently visible.
    private static let deleteColumnWidth: CGFloat = 20

    // Read to highlight whichever row (if any) matches the song
    // currently loaded in the preview player — the SwiftUI equivalent
    // of NSTableView's automatic native row-selection highlight that
    // Library gets "for free" on double-click, which this view has no
    // built-in counterpart for since it isn't an NSTableView.
    @EnvironmentObject
    private var previewPlayer:
        PreviewPlayer

    // Needed for the column header's "(Artist)"/"(AlbumArtist)"/
    // "(Grouping)" suffix on the Orchestra/Singer columns — see
    // LibraryColumnDefaults.headerTitle(for:settings:) below.
    @EnvironmentObject
    private var settings:
        AppSettings


    // Computed (not a stored `let`) so that if the user drags Tracks'
    // columns while the app is running and then switches to Tandas,
    // this picks up the latest saved order/widths instead of a stale
    // snapshot from when the view was first created.
    private var columns: [(String, CGFloat)] {

        // Leading Status column — same fixed width as Tracks' own
        // Status column (LibraryColumnDefaults.statusColumnWidth),
        // rendering a red/blue dot per song (see TandaSongRow) instead
        // of the blank spacer this used to be.
        //
        // The old "#" index column stays commented out here; re-add it
        // instead of/alongside the Status column if the index comes
        // back.
        /* [("#", LibraryColumnDefaults.leadingColumnWidth)] + */
        [("", LibraryColumnDefaults.statusColumnWidth)] +
        LibraryColumnDefaults.currentColumns()
    }


    // MARK: - Status
    //
    // Live status of a saved Tanda's song against the CURRENT
    // TrackLibrary — same meaning, same source data, as PlaylistView's
    // Status column, plus one extra state Setlist doesn't currently
    // surface: `.notInLibrary` (blue) if this song's id isn't in the
    // Library at all, `.fileMissing` (red) if it is but the file
    // wasn't found on disk at last Library rescan, `.staleReference`
    // (orange) if the Library knows this id and it's NOT missing, but
    // its current path no longer matches what this Tanda has saved —
    // i.e. the Library already found the file at a new location, but
    // this Tanda's own reference hasn't been re-linked to it yet and
    // will fail to play as-is, `.resolved` (no dot) otherwise.
    // Purely a display computation — unlike Setlist, a Tanda's own
    // saved data isn't touched by this; fixing a stale reference still
    // requires "Rescan TandaLibrary" (Tools menu), which is the only
    // thing that rewrites the Tanda's file.
    //
    // `libraryByID == nil` means the background status refresh (see
    // `TandaLibraryView.refreshStatus()`) hasn't completed yet — treated
    // as `.resolved` (no dot) rather than `.notInLibrary`, so switching
    // to this tab never flashes every track blue for a moment before
    // the real data lands a beat later.
    private func status(
        for song:
            Song
    ) -> SetlistEntryStatus {

        guard let libraryByID else {
            return .resolved
        }

        // Same rationale as TandaLibraryView.refreshStatus(): this
        // Tanda's own song ids are only trustworthy if it was last
        // saved against the currently active TrackLibrary — otherwise
        // an id match here would be coincidence (two independent
        // databases both assigning small integers from scratch), not
        // the same song, and would show the wrong dot entirely.
        let trustID =
            tanda.savedAgainstLibraryName == AppPaths.currentLibraryName

        let resolution =
            LibraryReferenceResolver.resolve(
                song,
                byID: libraryByID,
                byPath: libraryByPath ?? [:],
                missingSongIDs: missingSongIDs,
                trustID: trustID
            )

        guard resolution.live != nil else {
            return .notInLibrary
        }

        guard !resolution.isMissing else {
            return .fileMissing
        }

        guard !resolution.pathChanged else {
            return .staleReference
        }

        return .resolved
    }


    var body:
        some View {

        VStack(
            alignment:
                .leading,
            spacing:
                0
        ) {

            // =====================================================
            // TANDA HEADER
            //
            // Compact by design: this block repeats once PER TANDA
            // (unlike Tracks, which has a single table-wide header),
            // so its height directly multiplies the table's total
            // visible length. Kept deliberately small/tight to limit
            // that per-group overhead.
            // =====================================================

            HStack {

                Text(
                    tanda.name
                )
                .font(
                    .headline
                )
                .fontWeight(
                    .semibold
                )


                Text(
                    "\(tanda.songs.count) tracks"
                )
                .font(
                    .caption2
                )
                .foregroundStyle(
                    .secondary
                )


                // =================================================
                // COMMENT
                //
                // Inline, right next to the track count. The row's
                // own select-on-click below uses simultaneousGesture
                // (not onTapGesture) specifically so it doesn't
                // intercept the click a user needs to focus/type into
                // this field — onTapGesture claims the touch
                // exclusively, simultaneousGesture lets both fire.
                // =================================================

                TextField(
                    "Add a comment…",
                    text:
                        $commentDraft
                )
                .textFieldStyle(
                    .plain
                )
                .font(
                    .headline
                )
                .foregroundStyle(
                    .secondary
                )
                .focused(
                    $commentFieldIsFocused
                )
                .onSubmit {

                    onCommitComment(
                        commentDraft
                    )
                }
                .onChange(
                    of: commentFieldIsFocused
                ) { wasFocused, isFocused in

                    if wasFocused, !isFocused {

                        onCommitComment(
                            commentDraft
                        )
                    }
                }
                .onAppear {

                    commentDraft =
                        tanda.comment
                }
                .onChange(
                    of: tanda.comment
                ) { _, newValue in

                    // Keeps the field in sync if the comment changes
                    // from elsewhere (e.g. Tanda Rescan rewriting the
                    // file, or this same Tanda edited in another
                    // window) — but not while the user is actively
                    // typing in THIS field, which would otherwise
                    // clobber their in-progress edit.
                    if !commentFieldIsFocused {

                        commentDraft =
                            newValue
                    }
                }


                Spacer()
            }
            .padding(
                .horizontal,
                8
            )
            .padding(
                .vertical,
                4
            )
            .background(
                isSelected
                ? Color.accentColor.opacity(
                    0.15
                )
                : Color.clear
            )
            .contentShape(
                Rectangle()
            )
            .simultaneousGesture(
                TapGesture(
                    count:
                        1
                )
                .onEnded {

                    onSelectHeader()
                }
            )


            Divider()


            // =====================================================
            // COLUMN HEADER
            // =====================================================

            HStack(
                spacing:
                    0
            ) {

                // Matches the delete-button column's fixed width in
                // the song rows below — without this, the header's
                // text columns would start deleteColumnWidth too far
                // left compared to the actual row content next to it.
                Color.clear
                    .frame(
                        width:
                            Self.deleteColumnWidth
                    )

                ForEach(
                    columns,
                    id:
                        \.0
                ) { column in

                    Text(
                        LibraryColumnDefaults.headerTitle(
                            for: column.0,
                            settings: settings
                        )
                    )
                    .font(
                        .caption2
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .frame(
                        width:
                            column.1,
                        alignment:
                            .leading
                    )
                }
            }
            .padding(
                .horizontal,
                8
            )
            .padding(
                .vertical,
                2
            )


            Divider()


            // =====================================================
            // SONGS
            // =====================================================

            ForEach(
                Array(
                    tanda.songs.enumerated()
                ),
                id:
                    \.offset
            ) { index, song in

                HStack(
                    spacing:
                        0
                ) {

                    // =============================================
                    // REMOVE FROM TANDA
                    //
                    // Own fixed-width leading column, kept in exact
                    // sync with the header's spacer column below
                    // (Self.deleteColumnWidth) so the two rows stay
                    // aligned. The leading padding here mirrors the
                    // block's own header/column-header inset (8pt),
                    // so the X has real breathing room from the
                    // card's left edge instead of sitting flush
                    // against it — the button's own frame width is
                    // shrunk by that same 8pt so the TOTAL column
                    // width (padding + button) still matches
                    // deleteColumnWidth exactly.
                    //
                    // Always present in the layout (so column
                    // alignment stays stable even while hidden) but
                    // only visible/interactive when this Tanda is the
                    // selected/active one, the Library is unlocked,
                    // and removing wouldn't drop the Tanda below the
                    // 3-track minimum — same pattern as other
                    // lock-gated controls elsewhere in this view.
                    // Opacity (not just `.disabled`) also checks the
                    // lock, so re-locking the Library hides it again
                    // instead of leaving a dead-looking but
                    // still-visible X behind.

                    Button {

                        onDeleteSong(
                            index
                        )

                    } label: {

                        Image(
                            systemName:
                                "xmark"
                        )
                        .foregroundStyle(
                            .red
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                    .padding(
                        .leading,
                        8
                    )
                    .frame(
                        width:
                            Self.deleteColumnWidth,
                        alignment:
                            .leading
                    )
                    .opacity(
                        showsSelectionState &&
                        !libraryStore.isLocked
                        ? 1
                        : 0
                    )
                    .disabled(
                        !showsSelectionState
                        || libraryStore.isLocked
                        || tanda.songs.count <= 3
                    )
                    .help(
                        libraryStore.isLocked
                        ? "Unlock the Library to edit Tandas"
                        : tanda.songs.count <= 3
                        ? "A Tanda needs at least 3 tracks — delete the whole Tanda instead"
                        : "Remove this track from the Tanda"
                    )


                    TandaSongRow(
                        index:
                            index,
                        song:
                            song,
                        status:
                            status(
                                for:
                                    song
                            ),
                        columns:
                            columns
                    )
                }
                .background(
                    song == previewPlayer.currentSong
                    ? Color.accentColor.opacity(
                        0.18
                    )
                    : Color.clear
                )
                .contentShape(
                    Rectangle()
                )
                .onTapGesture(
                    count:
                        2
                ) {

                    NotificationCenter.default.post(
                        name:
                            .tandaPreviewSongDoubleClicked,
                        object:
                            song
                    )
                }


                if index <
                    tanda.songs.count - 1 {

                    Divider()
                }
            }
        }
        .fixedSize(
            horizontal:
                true,
            vertical:
                false
        )
        // Selection border (from clicking the header) — tied to the
        // same `showsSelectionState` as the per-row delete "x"s above,
        // so both always change together (see that property's doc
        // comment for the exact cases). Falls back to the plain
        // unselected look whenever they're standing down; the
        // selection itself isn't cleared, just visually stood down —
        // it reappears exactly as it was once showsSelectionState goes
        // back to true (drag ends, or moves onto this Tanda itself).
        .overlay(
            RoundedRectangle(
                cornerRadius:
                    6
            )
            .stroke(
                showsSelectionState
                ? Color.accentColor
                : Color.secondary.opacity(
                    0.25
                ),
                lineWidth:
                    showsSelectionState
                    ? 2
                    : 1
            )
        )


        // =========================================================
        // SETLIST → THIS TANDA (APPEND BY DROP)
        //
        // Dropping directly onto a specific block appends to THAT
        // Tanda, as opposed to TandaLibraryView's own background
        // onDrop (drop anywhere else in the scroll area) which
        // creates a brand-new Tanda. SwiftUI resolves the drop to
        // whichever onDrop is on the deepest view under the pointer,
        // so this naturally takes priority over the background one
        // without any extra mode/flag.
        // =========================================================

        .overlay(
            setlistDropFeedback(
                isTargeted:
                    isTargetedForAppend,
                isLocked:
                    libraryStore.isLocked,
                cornerRadius:
                    6
            )
        )
        .onDrop(
            of:
                [.text],
            delegate:
                SetlistToTandaDropDelegate(
                    isLocked:
                        libraryStore.isLocked,
                    target:
                        .tanda(tanda.sourceURL),
                    current:
                        currentDropTarget,
                    onDrop:
                        onDropAppend
                )
        )


        // =========================================================
        // COMPLETE TANDA DRAG
        //
        // IMPORTANT:
        // We deliberately use ONLY a normal String representation.
        //
        // The previous registerDataRepresentation(...) caused
        // macOS to request a dynamic UTI such as:
        //
        // dyn.agu80g55...
        //
        // and then failed to load it.
        //
        // PlaylistView recognizes this String as TandaDragPayload,
        // which now embeds the current insertionMode alongside the
        // song IDs (see TandaDragPayload.swift) — still just ONE
        // string, so this stays exactly as reliable as before.
        //
        // A Tanda is always dragged as a COMPLETE Tanda.
        // =========================================================

        .onDrag {

            let payload =
                TandaDragPayload.encode(
                    tanda,
                    mode:
                        insertionMode,
                    byID:
                        libraryByID ?? [:],
                    byPath:
                        libraryByPath ?? [:],
                    missingSongIDs:
                        missingSongIDs
                )


            return NSItemProvider(
                object:
                    NSString(
                        string:
                            payload
                    )
            )
        }
    }
}


// MARK: - Song Row

private struct TandaSongRow:
    View {

    let index:
        Int

    let song:
        Song

    let status:
        SetlistEntryStatus

    let columns:
        [(String, CGFloat)]

    @EnvironmentObject
    private var settings:
        AppSettings


    var body:
        some View {

        HStack(
            spacing:
                0
        ) {

            ForEach(
                columns,
                id:
                    \.0
            ) { column in

                if column.0 ==
                    "" {

                    statusIndicator(
                        width:
                            column.1
                    )

                } else {

                    value(
                        text(
                            for:
                                column.0
                        ),
                        width:
                            column.1
                    )
                }
            }
        }
        .padding(
            .horizontal,
            8
        )
        .padding(
            .vertical,
            3
        )
    }


    // MARK: - Status Indicator
    //
    // Mirrors LibraryTableView/PlaylistView's Status column: red
    // octagon for a file the Library couldn't find on disk at last
    // rescan, blue question mark for a song this Tanda references that
    // isn't in the current Library at all, nothing for a song that
    // resolves cleanly.

    @ViewBuilder
    private func statusIndicator(
        width:
            CGFloat
    ) -> some View {

        Group {

            if status == .fileMissing {

                Image(
                    systemName:
                        "octagon.fill"
                )
                .foregroundStyle(
                    Color.red
                )
                .help(
                    "File not found on disk"
                )

            } else if status == .notInLibrary {

                Image(
                    systemName:
                        "questionmark.circle.fill"
                )
                .foregroundStyle(
                    Color.blue
                )
                .help(
                    "Not found in the current Library — showing saved info"
                )

            } else if status == .staleReference {

                Image(
                    systemName:
                        "exclamationmark.triangle.fill"
                )
                .foregroundStyle(
                    Color.orange
                )
                .help(
                    "The TrackLibrary already found this file at a new location, but this Tanda hasn't been re-linked to it yet — it will fail to play. Run \"Rescan TandaLibrary\" (Tools menu) to fix it."
                )

            } else {

                Color.clear
            }
        }
        .font(
            .system(
                size:
                    8
            )
        )
        .frame(
            width:
                width,
            alignment:
                .leading
        )
    }


    // MARK: - Value For Column
    //
    // Renders values by COLUMN NAME rather than by fixed position, so
    // the row always lines up with the header — no matter what order
    // `columns` is currently in (i.e. whatever order/width the user has
    // Tracks set to via LibraryColumnDefaults.currentColumns()).

    private func text(
        for columnName:
            String
    ) -> String {

        switch columnName {

        case "#":
            return "\(index + 1)"

        case "Title":
            return song.title ?? song.filename

        case "Orchestra":
            return song.resolvedOrchestra(using: settings) ?? ""

        case "Singer":
            return song.resolvedSinger(using: settings) ?? ""

        case "Album":
            return song.album ?? ""

        case "Genre":
            return song.genre ?? ""

        case "Year":
            return yearString(song.year)

        case "Type":
            return song.fileType ?? ""

        case "SRate":
            return sampleRateString(song.sampleRate)

        case "R128 Gain":
            return replayGainString(song.replayGain)

        case "Duration":
            return durationString(song.duration)

        case "Grouping":
            return song.grouping ?? ""

        case "Comment":
            return song.comment ?? ""

        default:
            return ""
        }
    }


    // MARK: - Value

    private func value(
        _ text:
            String,
        width:
            CGFloat
    ) -> some View {

        Text(
            text
        )
        .font(
            .system(
                size:
                    LibraryColumnDefaults.rowFontSize
            )
        )
        .lineLimit(
            1
        )
        .truncationMode(
            .tail
        )
        .frame(
            width:
                width,
            alignment:
                .leading
        )
    }


    // MARK: - Year

    private func yearString(
        _ value:
            Int?
    ) -> String {

        guard
            let value
        else {
            return ""
        }

        return String(
            value
        )
    }


    // MARK: - Sample Rate

    private func sampleRateString(
        _ value:
            Int?
    ) -> String {

        guard
            let value
        else {
            return ""
        }

        return String(
            format:
                "%.1f kHz",
            Double(value) / 1000.0
        )
    }


    // MARK: - Replay Gain

    private func replayGainString(
        _ value:
            Double?
    ) -> String {

        guard
            let value
        else {
            return ""
        }

        return String(
            format:
                "%.1f dB",
            value
        )
    }


    // MARK: - Duration

    private func durationString(
        _ value:
            Int?
    ) -> String {

        guard
            let value
        else {
            return ""
        }

        return String(
            format:
                "%d:%02d",
            value / 60,
            value % 60
        )
    }
}

