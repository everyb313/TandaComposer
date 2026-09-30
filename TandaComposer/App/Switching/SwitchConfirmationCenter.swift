//
//  SwitchConfirmationCenter.swift
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

import Foundation
import Combine

/// What kind of thing is about to be replaced — only affects wording
/// in the dialog.
enum SwitchTargetKind {
    case library
    case playlist
}

/// One pending "about to replace the current Library/Playlist" request.
/// Identifiable so it can drive a SwiftUI `.sheet(item:)`.
struct SwitchConfirmationRequest: Identifiable {

    let id = UUID()

    let kind: SwitchTargetKind

    /// Name offered in the text field, editable by the user.
    let suggestedName: String

    /// Names that would collide (already-saved internal libraries or
    /// playlists) — used to show the overwrite warning.
    let existingNames: [String]

    /// Called when the user confirms saving under (possibly edited)
    /// `name`. Runs after any overwrite warning has been confirmed.
    let onSave: (_ name: String) -> Void

    /// Called when the user chooses "Don't Save".
    let onDiscard: () -> Void
}

/// Shared across the app (as an `@EnvironmentObject`) so that both
/// toolbar buttons and, later, menu bar commands can trigger the same
/// "save before replacing?" dialog without duplicating the UI.
@MainActor
final class SwitchConfirmationCenter: ObservableObject {

    @Published var request: SwitchConfirmationRequest?

    func ask(
        kind: SwitchTargetKind,
        suggestedName: String,
        existingNames: [String],
        onSave: @escaping (_ name: String) -> Void,
        onDiscard: @escaping () -> Void
    ) {

        request = SwitchConfirmationRequest(
            kind: kind,
            suggestedName: suggestedName,
            existingNames: existingNames,
            onSave: onSave,
            onDiscard: onDiscard
        )
    }
}
