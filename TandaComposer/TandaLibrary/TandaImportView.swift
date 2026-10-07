//
//  TandaImportView.swift
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
import AppKit
import SwiftUI

/// "Import Tandas from ZIP": orchestra folders on the left, the Tandas
/// of the chosen folder on the right, each with a status.
struct TandaImportView: View {

    @EnvironmentObject
    private var session: TandaImportSession

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @EnvironmentObject
    private var settings: AppSettings

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var selection: String?

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            header

            Divider()

            HSplitView {

                folderList
                    .frame(
                        minWidth: 200,
                        idealWidth: 240,
                        maxWidth: 380
                    )

                tandaList
                    .frame(minWidth: 520)
            }

            Divider()

            footer
        }
        .frame(minWidth: 900, minHeight: 520)
        .onChange(of: selection) { _, newValue in

            if let newValue {
                session.select(
                    folder: newValue,
                    libraryStore: libraryStore,
                    settings: settings
                )
            }
        }
        .onChange(of: session.loadID) { _, _ in

            selection = nil
        }
    }

    // MARK: - Header

    private var header: some View {

        HStack {

            VStack(alignment: .leading, spacing: 2) {

                Text(
                    session.zipName.isEmpty
                        ? "No ZIP loaded"
                        : session.zipName
                )
                .font(.headline)

                Text(
                    "Choose one folder (orchestra), look at its Tandas, then import the checked ones."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open ZIP…") {

                TandaImportActions.chooseZip(session: session)
            }
        }
        .padding(12)
    }

    // MARK: - Folders

    private var folderList: some View {

        List(session.folders, selection: $selection) { folder in

            HStack {

                Text(folder.display)
                    .lineLimit(1)

                Spacer()

                Text("\(folder.count)")
                    .foregroundStyle(.secondary)
            }
            .tag(folder.id)
        }
    }

    // MARK: - Tandas

    @ViewBuilder
    private var tandaList: some View {

        if session.selectedFolder == nil {

            placeholder("Choose a folder on the left.")

        } else if session.isMatching {

            VStack {

                Spacer()

                ProgressView(
                    "Matching Tandas with your TrackLibrary…"
                )

                Spacer()
            }
            .frame(maxWidth: .infinity)

        } else if session.entries.isEmpty {

            placeholder("This folder has no Tandas.")

        } else {

            ScrollView {

                LazyVStack(alignment: .leading, spacing: 0) {

                    ForEach(session.entries) { entry in

                        TandaImportRow(entry: entry)
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {

        VStack {

            Spacer()

            Text(text)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {

        HStack {

            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Close") {
                dismiss()
            }

            Button(importTitle) {
                runImport()
            }
            .disabled(session.checkedReadyCount == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var importTitle: String {

        let count = session.checkedReadyCount

        return count == 1
            ? "Import 1 Tanda"
            : "Import \(count) Tandas"
    }

    private var footerText: String {

        var ready = 0
        var needsHelp = 0
        var exists = 0
        var notPossible = 0

        for entry in session.entries {

            switch entry.status {
            case .ready: ready += 1
            case .needsHelp: needsHelp += 1
            case .exists: exists += 1
            case .notPossible: notPossible += 1
            case .imported, .failed: break
            }
        }

        var text =
            "\(ready) ready · \(needsHelp) need help · "
            + "\(exists) already exist · \(notPossible) not possible."

        if !session.unreadable.isEmpty {
            text +=
                " \(session.unreadable.count) file(s) in the ZIP could not be read."
        }

        return text
    }

    // MARK: - Import

    private func runImport() {

        let count = session.checkedReadyCount

        let confirm = NSAlert()

        confirm.messageText =
            count == 1
                ? "Import 1 Tanda?"
                : "Import \(count) Tandas?"

        confirm.informativeText =
            "They will be saved in the TandaLibrary of \"\(AppPaths.currentLibraryName)\". Folder and name come from your own tags, so they can differ from the ZIP. Imported Tandas can only be removed one by one — a backup first (Tools → Export Backup…) is a good idea."

        confirm.addButton(withTitle: "Import")
        confirm.addButton(withTitle: "Cancel")

        guard confirm.runModal() == .alertFirstButtonReturn else {
            return
        }

        let summary =
            session.importChecked(
                libraryStore: libraryStore,
                settings: settings
            )

        var lines: [String] = [
            "\(summary.imported) imported."
        ]

        if summary.skippedExisting > 0 {
            lines.append(
                "\(summary.skippedExisting) skipped: the same tracks were already imported."
            )
        }

        if !summary.failed.isEmpty {
            lines.append(
                "Not imported:\n"
                + summary.failed
                    .prefix(10)
                    .joined(separator: "\n")
            )
        }

        let done = NSAlert()

        done.messageText = "Import Finished"
        done.informativeText = lines.joined(separator: "\n\n")
        done.alertStyle = .informational

        done.runModal()
    }
}

// MARK: - Row

private struct TandaImportRow: View {

    let entry: TandaImportEntry

    @EnvironmentObject
    private var session: TandaImportSession

    @EnvironmentObject
    private var settings: AppSettings

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @State
    private var expanded = false

    /// Size of the text in the track list and the status line.
    private let trackFont = Font.callout

    var body: some View {

        VStack(alignment: .leading, spacing: 4) {

            HStack(spacing: 8) {

                checkbox

                Image(systemName: icon)
                    .foregroundStyle(color)

                Text(entry.shared.name)
                    .font(.headline)
                    .lineLimit(1)

                if !entry.shared.subfolder.isEmpty {

                    Text(entry.shared.subfolder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(toggleTitle) {
                    expanded.toggle()
                }
                .buttonStyle(.link)
            }

            Text(statusText)
                .font(trackFont)
                .foregroundStyle(color)
                .padding(.leading, 28)

            if expanded {

                VStack(alignment: .leading, spacing: 8) {

                    ForEach(entry.lines) { line in
                        lineView(line)
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)

        Divider()
    }

    // MARK: Pieces

    @ViewBuilder
    private var checkbox: some View {

        if entry.status == .ready {

            Toggle(
                "",
                isOn: Binding(
                    get: { session.checked.contains(entry.id) },
                    set: { _ in session.toggle(entry.id) }
                )
            )
            .labelsHidden()

        } else {

            Color.clear
                .frame(width: 20, height: 1)
        }
    }

    private var toggleTitle: String {

        if case .needsHelp = entry.status {
            return expanded ? "Hide tracks" : "Choose tracks"
        }

        return expanded ? "Hide tracks" : "Show tracks"
    }

    /// Tracks can be changed until the Tanda has been imported.
    private var isEditable: Bool {

        switch entry.status {
        case .imported, .failed:
            return false
        default:
            return true
        }
    }

    private func lineView(
        _ line: TandaImportLine
    ) -> some View {

        VStack(alignment: .leading, spacing: 4) {

            HStack(alignment: .top, spacing: 6) {

                Text("\(line.number).")
                    .font(trackFont)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {

                    Text(line.text)
                        .font(trackFont)
                        .foregroundStyle(.secondary)

                    if let song = line.song {

                        Text(summary(of: song) + " — " + line.note)
                            .font(trackFont)

                    } else {

                        Text(line.note)
                            .font(trackFont)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if showsPicker(for: line) {

                VStack(alignment: .leading, spacing: 3) {

                    ForEach(line.candidates, id: \.normalizedPath) {
                        candidate in

                        candidateRow(candidate, in: line)
                    }
                }
                .padding(.leading, 30)
            }
        }
    }

    /// Candidates are offered while a line is open, when several files
    /// are possible, and to take back a choice made by hand.
    private func showsPicker(
        for line: TandaImportLine
    ) -> Bool {

        isEditable
            && !line.candidates.isEmpty
            && (line.song == nil
                || line.candidates.count > 1
                || line.chosenByUser)
    }

    private func candidateRow(
        _ candidate: Song,
        in line: TandaImportLine
    ) -> some View {

        let isChosen =
            line.song?.normalizedPath == candidate.normalizedPath

        return HStack(spacing: 6) {

            Button {

                session.setChoice(
                    candidate,
                    line: line.id,
                    entry: entry.id,
                    libraryStore: libraryStore,
                    settings: settings
                )

            } label: {

                Image(
                    systemName:
                        !isChosen
                            ? "circle"
                            : (line.chosenByUser
                                ? "checkmark.circle.fill"
                                : "checkmark.circle")
                )
                .foregroundStyle(
                    isChosen
                        ? Color.green
                        : Color.secondary.opacity(0.6)
                )
            }
            .buttonStyle(.plain)
            .help(
                isChosen
                    ? "Click to take this choice back"
                    : "Use this track"
            )

            Text(summary(of: candidate))
                .font(trackFont)
        }
    }

    private func summary(of song: Song) -> String {

        [
            song.title,
            song.rawTagValue(for: settings.orchestraSource),
            song.rawTagValue(for: settings.singerSource),
            song.year.map { String($0) },
            song.duration.map {
                String(format: "%d:%02d", $0 / 60, $0 % 60)
            },
            song.fileType,
            song.sampleRate.map {
                String(format: "%.1f kHz", Double($0) / 1000)
            }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var icon: String {

        switch entry.status {
        case .ready: return "checkmark.circle"
        case .needsHelp: return "questionmark.circle"
        case .exists: return "equal.circle"
        case .notPossible: return "xmark.circle"
        case .imported: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var color: Color {

        switch entry.status {
        case .ready, .imported: return .green
        case .needsHelp: return .orange
        case .exists: return .secondary
        case .notPossible, .failed: return .red
        }
    }

    private var statusText: String {

        switch entry.status {

        case .ready:
            return "Ready — will be saved as "
                + (entry.location ?? "…")

        case .needsHelp(let reason):
            return "Needs help — " + reason

        case .exists(let name):
            return "Already in your TandaLibrary as \"\(name)\""

        case .notPossible(let reason):
            return "Not possible — " + reason

        case .imported(let place):
            return "Imported as " + place

        case .failed(let reason):
            return "Not imported — " + reason
        }
    }
}
