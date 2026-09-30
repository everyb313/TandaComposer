//
//  SmartListEditorWindowView.swift
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

/// Content of the standalone Smartlist editor window (opened via
/// `openWindow(value: node.id)` from SmartListTreeView's context menu).
///
/// This window is independent from the main window.
struct SmartListEditorWindowView: View {
    let nodeID: String

    @EnvironmentObject private var store: SmartlistStore
    @Environment(\.dismiss) private var dismiss

    @State private var ruleSet: SmartListRuleSet?
    @State private var saveErrorMessage: String?

    /// Condition awaiting delete confirmation — set instead of removing immediately
    /// from the row's minus-circle button.
    @State private var pendingDeleteCondition: SmartlistCondition?

    var body: some View {
        Group {
            if let node = store.findNode(id: nodeID), !node.isFolder {

                if let ruleSet {
                    editor(
                        node: node,
                        ruleSet: Binding(
                            get: { ruleSet },
                            set: { self.ruleSet = $0 }
                        )
                    )
                } else {
                    Color.clear
                        .onAppear {
                            self.ruleSet =
                                node.ruleSet ??
                                SmartListRuleSet(
                                    name: node.name
                                )
                        }
                }

            } else {

                ContentUnavailableView(
                    "Smartlist Not Found",
                    systemImage: "questionmark.folder",
                    description: Text(
                        "It may have been deleted or moved."
                    )
                )
            }
        }
        .frame(
            minWidth: 480,
            minHeight: 320
        )

        // -------------------------------------------------------------
        // Window frame autosave
        // -------------------------------------------------------------

        .background(
            WindowFrameAutosave(
                name: "SmartlistEditorWindow"
            )
        )

        // -------------------------------------------------------------
        // Save error
        // -------------------------------------------------------------

        .alert(
            "Couldn't Save",
            isPresented: .constant(
                saveErrorMessage != nil
            ),
            presenting: saveErrorMessage
        ) { _ in

            Button("OK") {
                saveErrorMessage = nil
            }

        } message: { message in

            Text(message)
        }
    }


    // MARK: - Editor

    @ViewBuilder
    private func editor(
        node: SmartlistNode,
        ruleSet: Binding<SmartListRuleSet>
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            // ---------------------------------------------------------
            // Name
            // ---------------------------------------------------------

            TextField(
                "Name",
                text: ruleSet.name
            )
            .textFieldStyle(.roundedBorder)
            .font(.title3)


            // ---------------------------------------------------------
            // Match mode
            // ---------------------------------------------------------

            HStack {

                Text("Match")

                Picker(
                    "",
                    selection: ruleSet.matchMode
                ) {
                    ForEach(
                        SmartlistMatchMode.allCases
                    ) { mode in

                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Text(
                    "of the following conditions:"
                )

                Spacer()
            }


            // ---------------------------------------------------------
            // Conditions
            // ---------------------------------------------------------

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {

                    ForEach(
                        ruleSet.conditions
                    ) { condition in

                        ConditionRow(
                            condition: condition,
                            onDelete: {
                                pendingDeleteCondition = condition.wrappedValue
                            }
                        )
                    }
                }
            }


            // ---------------------------------------------------------
            // Add condition
            // ---------------------------------------------------------

            Button {

                ruleSet.wrappedValue.conditions.append(
                    SmartlistCondition(
                        field: .songName,
                        op: .contains,
                        value: ""
                    )
                )

            } label: {

                Label(
                    "Add Condition",
                    systemImage: "plus"
                )
            }


            Spacer(minLength: 0)


            // ---------------------------------------------------------
            // Bottom buttons
            // ---------------------------------------------------------

            HStack {

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {

                    do {
                        try store.save(
                            ruleSet.wrappedValue,
                            to: node
                        )

                        dismiss()

                    } catch {

                        saveErrorMessage =
                            error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.isLocked)
                .help(store.isLocked ? "Unlock smartlists (in the column header) to save changes" : "")
            }
        }
        .padding()
        .confirmationDialog(
            "Delete Condition?",
            isPresented: .constant(pendingDeleteCondition != nil),
            presenting: pendingDeleteCondition
        ) { condition in
            Button("Delete", role: .destructive) {
                ruleSet.wrappedValue.conditions.removeAll {
                    $0.id == condition.id
                }
                pendingDeleteCondition = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteCondition = nil
            }
        } message: { condition in
            Text("This condition will be removed: \(condition.field.displayName) \(condition.op.displayName) \"\(condition.value)\".")
        }
    }
}


// MARK: - Condition Row

private struct ConditionRow: View {

    @Binding var condition: SmartlistCondition

    let onDelete: () -> Void

    var body: some View {

        HStack {

            // ---------------------------------------------------------
            // Field
            // ---------------------------------------------------------

            Picker(
                "",
                selection: $condition.field
            ) {

                ForEach(
                    SmartlistField.allCases
                ) { field in

                    Text(field.displayName)
                        .tag(field)
                }
            }
            .frame(width: 110)
            .onChange(
                of: condition.field
            ) { _, newField in

                let validOperators =
                    SmartlistOperator
                        .validOperators(for: newField)

                if !validOperators.contains(
                    condition.op
                ) {
                    condition.op =
                        validOperators.first!
                }
            }


            // ---------------------------------------------------------
            // Operator
            // ---------------------------------------------------------

            Picker(
                "",
                selection: $condition.op
            ) {

                ForEach(
                    SmartlistOperator
                        .validOperators(
                            for: condition.field
                        )
                ) { op in

                    Text(op.displayName)
                        .tag(op)
                }
            }
            .frame(width: 130)


            // ---------------------------------------------------------
            // Value
            // ---------------------------------------------------------

            TextField(
                condition.op == .isBetween ||
                condition.op == .isNotBetween
                    ? "From"
                    : "Value",
                text: $condition.value
            )
            .textFieldStyle(.roundedBorder)


            // ---------------------------------------------------------
            // Second value
            // ---------------------------------------------------------

            if condition.op == .isBetween ||
               condition.op == .isNotBetween {

                Text("and")

                TextField(
                    "To",
                    text: Binding(
                        get: {
                            condition.secondValue ?? ""
                        },
                        set: {
                            condition.secondValue = $0
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }


            // ---------------------------------------------------------
            // Delete
            // ---------------------------------------------------------

            Button(
                role: .destructive,
                action: onDelete
            ) {
                Image(
                    systemName: "minus.circle"
                )
            }
            .buttonStyle(.plain)
        }
    }
}


// MARK: - Window Frame Autosave

/// Bridges to the hosting NSWindow to enable AppKit's built-in
/// frame autosave.
///
/// SwiftUI has no direct modifier for this.
///
/// `setFrameAutosaveName` persists the window's size and position
/// and restores it when another editor window with the same name
/// is created.
private struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)

        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            window.setFrameAutosaveName(name)
        }

        return view
    }

    func updateNSView(
        _ nsView: NSView,
        context: Context
    ) {
    }
}
