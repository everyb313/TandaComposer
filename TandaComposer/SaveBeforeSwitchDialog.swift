//
//  SaveBeforeSwitchDialog.swift
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

/// Sheet shown before a Library or Playlist is about to be replaced
/// (New… / Load…). Offers to save the current one under a name first
/// — prefilled with its current name, editable — or to discard it.
struct SaveBeforeSwitchDialog: View {

    let request: SwitchConfirmationRequest
    let onClose: () -> Void

    @State private var name: String
    @State private var showingOverwriteWarning = false


    init(
        request: SwitchConfirmationRequest,
        onClose: @escaping () -> Void
    ) {

        self.request = request
        self.onClose = onClose

        _name = State(
            initialValue: request.suggestedName
        )
    }


    private var kindLabel: String {

        switch request.kind {

        case .library:
            return "Library"

        case .playlist:
            return "Setlist"
        }
    }


    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    var body: some View {

        VStack(alignment: .leading, spacing: 16) {

            Text("Save current \(kindLabel)?")
                .font(.headline)

            Text(
                "Give the current \(kindLabel.lowercased()) a name " +
                "to keep it, or discard it without saving."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            TextField(
                "\(kindLabel) name",
                text: $name
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                attemptSave()
            }

            HStack {

                Button("Don't Save", role: .destructive) {
                    request.onDiscard()
                    onClose()
                }

                Spacer()

                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    attemptSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .alert(
            "Overwrite \(kindLabel)?",
            isPresented: $showingOverwriteWarning
        ) {

            Button("Cancel", role: .cancel) {
            }

            Button("Overwrite", role: .destructive) {
                request.onSave(trimmedName)
                onClose()
            }

        } message: {

            Text(
                "A \(kindLabel.lowercased()) named " +
                "\"\(trimmedName)\" already exists internally " +
                "and will be overwritten."
            )
        }
    }


    private func attemptSave() {

        guard !trimmedName.isEmpty else {
            return
        }

        if request.existingNames.contains(trimmedName) {

            showingOverwriteWarning = true

        } else {

            request.onSave(trimmedName)
            onClose()
        }
    }
}
