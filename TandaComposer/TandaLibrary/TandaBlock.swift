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




struct TandaBlock:
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

    /// Fired when a Setlist drag hovers over or is released on THIS
    /// block while the Library is locked — the parent shows its
    /// "Library is locked" hint. Passed straight through to this
    /// block's SetlistToTandaDropDelegate.
    let onLockedDropAttempt:
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
    // TrackLibrary — same meaning, same source data, as SetlistView's
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

                // =================================================
                // TITLE / TRACK COUNT — the select/deselect target
                //
                // Deliberately its OWN tap target, not the whole
                // header row — the comment field below needs the
                // row's old click-through behavior preserved (see its
                // own comment), and a plain toggle on the whole row
                // would mean clicking into an ALREADY-selected Tanda's
                // comment field to edit it also deselects it in the
                // same click. Narrowing the toggle to just this
                // title/count group avoids that; the row-wide
                // background highlight below is untouched, only the
                // CLICKABLE area for select/deselect is smaller now.
                // =================================================

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
                }
                .contentShape(
                    Rectangle()
                )
                .onTapGesture {

                    onSelectHeader()
                }


                // =================================================
                // COMMENT
                //
                // Inline, right next to the track count. No longer
                // shares a gesture with the select/deselect toggle at
                // all — that now lives ONLY on the title/track-count
                // group above, specifically so clicking in here to
                // edit the comment never also toggles this Tanda's
                // selection off (see that group's own comment).
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
                            AppNotification.tandaPreviewSongDoubleClicked,
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
                        onDropAppend,
                    onLockedAttempt:
                        onLockedDropAttempt
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
        // SetlistView recognizes this String as TandaDragPayload,
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
