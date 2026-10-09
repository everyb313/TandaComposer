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
enum SetlistDropTarget: Equatable {
    case background
    case tanda(URL)
}

// Uses the DropDelegate protocol rather than the isTargeted-closure
// form of .onDrop specifically so dropUpdated(info:) can return an
// explicit `.forbidden` DropProposal while the Library is locked,
// instead of the closure form's "accept the hover, reject only after
// release" behavior (which is too late to affect the hover cursor).
//
// Two macOS/SwiftUI quirks this delegate works around:
//
// 1. dropEntered/dropExited turned out not to fire reliably for this
//    kind of drag, while dropUpdated does, continuously, while
//    hovering. So dropUpdated below is the ONLY reliable place
//    `current` gets set — there's no dropEntered override at all, and
//    dropExited (kept anyway, for the cases where it does fire) is
//    explicitly best-effort.
//
// 2. SwiftUI only calls dropEntered/dropUpdated/dropExited for drags
//    that validateDrop ACCEPTED. validateDrop used to reject while the
//    Library was locked — which silenced dropUpdated entirely, so
//    nothing could react to a drag hovering over a locked Library (no
//    hint was possible, and the red cursor seen then most likely came
//    from that rejection, not from the `.forbidden` proposal below,
//    which never ran). validateDrop now only checks the drag's type;
//    the lock is enforced in dropUpdated (`.forbidden`) and
//    performDrop (returns false), and `onLockedAttempt` tells the
//    parent so it can show a "Library is locked" hint.

struct SetlistToTandaDropDelegate: DropDelegate {

    let isLocked: Bool
    /// Which target THIS delegate instance represents (.background for
    /// TandaLibraryView's own drop zone, .tanda(url) for one TandaBlock).
    let target: SetlistDropTarget
    /// The one shared "currently hovered target" — see
    /// SetlistDropTarget's doc comment above for why this is a single
    /// value instead of a per-target Bool.
    let current: Binding<SetlistDropTarget?>
    let onDrop: () -> Void
    /// Called whenever a drag hovers over (dropUpdated) or is released
    /// on (performDrop) this target WHILE THE LIBRARY IS LOCKED — the
    /// parent shows a short "Library is locked" hint in response.
    /// Never called while unlocked.
    let onLockedAttempt: () -> Void

    /// Best-effort cleanup (see the struct-level note above) — only
    /// clears if WE are still the current target, so a stale/late
    /// call for a target you've already left doesn't wipe out
    /// whatever you've since moved onto.
    func dropExited(info: DropInfo) {

        if current.wrappedValue == target {
            current.wrappedValue = nil
        }
    }

    /// The reliable source of the hover cursor feedback, the border
    /// feedback, AND the locked-Library hint (see the struct-level
    /// notes above).
    ///
    /// While locked: only reports the attempt and answers `.forbidden`
    /// — deliberately does NOT touch `current`, so a locked hover never
    /// draws the accepted-state ring or stands down the selected
    /// Tanda's own border/x's, and can't leave a stale `current`
    /// behind if the drag ends without dropExited firing.
    ///
    /// While unlocked: unconditionally overwrites `current` with our
    /// own `target` on every call, which is what makes
    /// setlistDropFeedback's accepted-state ring appear for exactly
    /// one target at a time — moving onto a different target just
    /// overwrites this again.
    func dropUpdated(info: DropInfo) -> DropProposal? {

        if isLocked {

            onLockedAttempt()

            return DropProposal(
                operation: .forbidden
            )
        }

        current.wrappedValue = target

        return DropProposal(
            operation: .copy
        )
    }

    /// True only for a drag that started in the Setlist table — it
    /// carries SetlistDragMarker's pasteboard type. A Tanda dragged
    /// out of this very Library is plain text too, so the `.text`
    /// check alone can't tell the two apart; without this, dragging a
    /// Tanda toward the Setlist made the "Library is locked" hint
    /// appear while the drag was still hovering over this Library.
    private var isSetlistRowDrag: Bool {

        NSPasteboard(name: .drag)
            .types?
            .contains(SetlistDragMarker.pasteboardType) == true
    }

    /// Type check plus origin check — the lock is NOT checked here
    /// anymore, see note 2 in the struct-level comment above for why.
    func validateDrop(info: DropInfo) -> Bool {

        info.hasItemsConforming(
            to: [.text]
        )
        && isSetlistRowDrag
    }

    func performDrop(info: DropInfo) -> Bool {

        current.wrappedValue = nil

        guard !isLocked else {

            // May not be reached at all if the system refuses to
            // deliver a drop it was told is `.forbidden` — the hover
            // hint from dropUpdated is the primary signal; this just
            // extends it if the release does arrive.
            onLockedAttempt()

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
/// Draws nothing while locked — the locked-state feedback is the
/// separate "Library is locked" hint banner on the ScrollView (see
/// showLockedHint below), driven by the delegate's onLockedAttempt.
/// An earlier attempt drew a red ring + message from THIS function
/// instead, but never appeared: at that point validateDrop was still
/// rejecting locked drags, so no hover callback ever ran to trigger it.
@ViewBuilder
func setlistDropFeedback(
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
struct NewTandaLaneMarker: View {

    static let width: CGFloat = 36

    var body: some View {

        Color.clear
            .frame(
                width: Self.width
            )
    }
}


// MARK: - Tanda Library View

