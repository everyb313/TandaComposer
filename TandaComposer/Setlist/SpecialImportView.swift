//
//  SpecialImportView.swift
//  TandaComposer
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
//  Manual stage of the M3U8 import: lines with an exact path match are
//  adopted, for every other line the same-named TrackLibrary tracks are
//  listed (same column layout as Find Duplicates) and the user ticks
//  the one to adopt.
//
//  Marks and colours:
//    - Leading column, open circle  = candidate, click to use it
//    - Leading column, green check  = candidate chosen for the import
//    - Leading column, outlined green check
//                                   = auto-picked best file (a suggestion;
//                                     click to remove it)
//    - Leading column, grey check   = exact path match (always imported)
//    - Light blue row               = last track listened to
//                                     (double-click a row to preview)
//

import SwiftUI

// MARK: - Special Import View

struct SpecialImportView: View {

    @EnvironmentObject
    private var session: SpecialImportSession

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @EnvironmentObject
    private var setlistStore: SetlistStore

    @EnvironmentObject
    private var settings: AppSettings

    @Environment(\.dismiss)
    private var dismiss

    /// Hides what is done: exact matches, chosen and skipped tracks.
    /// Tracks still to do and auto-picked suggestions stay visible.
    @State
    private var hideDone = false

    /// The track most recently double-clicked for preview (also when
    /// the preview was started in another window). It only colours a
    /// row light blue; it does not follow the player, so stopping
    /// playback does not clear it.
    @State
    private var previewedSongID: Int64?

    /// Width of the leading column that carries the check marks. Only
    /// this window uses it; the shared 5 pt spacer of the Library and
    /// Find Duplicates is left alone.
    private static let markColumnWidth: CGFloat = 26

    // Same columns as the Library / Find Duplicates, with a wider
    // leading column for the check marks.
    private var columns: [(String, CGFloat)] {

        [
            (
                "",
                Self.markColumnWidth
            )
        ]
        +
        LibraryColumnDefaults.currentColumns()
    }

    private var visibleRows: [SpecialImportRow] {

        hideDone
            ? session.rows.filter {
                $0.state == .open || $0.state == .autoPicked
            }
            : session.rows
    }

    // MARK: - Body

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            header

            Divider()

            if session.isPreparing {

                VStack {

                    Spacer()

                    ProgressView("Matching tracks…")

                    Spacer()
                }
                .frame(maxWidth: .infinity)

            } else if session.rows.isEmpty {

                VStack {

                    Spacer()

                    Text("Nothing to import.")
                        .foregroundStyle(.secondary)

                    Spacer()
                }

            } else {

                ScrollView(
                    [.horizontal, .vertical]
                ) {

                    LazyVStack(
                        alignment: .leading,
                        spacing: 8
                    ) {

                        ForEach(
                            visibleRows
                        ) { row in

                            SpecialImportRowBlock(
                                row: row,
                                columns: columns,
                                previewedSongID: previewedSongID
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .tandaPreviewSongDoubleClicked
            )
        ) { notification in

            previewedSongID =
                (notification.object as? Song)?.id
        }
        // Freely resizable: the window opens at the Library pane
        // width, but min/max no longer pin it to that size.
        .frame(
            minWidth: 480,
            idealWidth:
                max(
                    settings.currentLibraryPaneWidth,
                    400
                ),
            maxWidth: .infinity,
            minHeight: 420,
            idealHeight: 640,
            maxHeight: .infinity
        )
    }

    // MARK: - Header

    private var header: some View {

        VStack(
            alignment: .leading,
            spacing: 4
        ) {

            HStack {

                Text("Pick Tracks")
                    .font(.title2)
                    .bold()

                Text(session.sourceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Toggle(
                    "Hide done",
                    isOn: $hideDone
                )
                .toggleStyle(.checkbox)

                Button(role: .cancel) {

                    session.reset()
                    dismiss()

                } label: {

                    Text("Cancel")
                }

                Button {

                    create()

                } label: {

                    Label(
                        "Create Setlist",
                        systemImage: "checkmark"
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    session.adoptedSongs.isEmpty
                )
            }

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private var statusLine: String {

        let matched = session.count(of: .matched)
        let chosen = session.count(of: .chosen)
        let autoPicked = session.count(of: .autoPicked)
        let open = session.count(of: .open)
        let skipped = session.count(of: .skipped)

        var counts =
            "\(matched) exact · \(chosen) chosen · "

        if autoPicked > 0 {
            counts += "\(autoPicked) auto-picked · "
        }

        counts += "\(open) to do · \(skipped) skipped. "

        return
            "\(session.rows.count) track(s): "
            + counts
            + "Tracks still to do and skipped tracks are left out of the new Setlist."
    }

    // MARK: - Create

    private func create() {

        let created =
            SetlistActions.createSetlistFromSpecialImport(
                session: session,
                setlistStore: setlistStore,
                libraryStore: libraryStore
            )

        if created {
            dismiss()
        }
    }
}


// MARK: - Row Block

private struct SpecialImportRowBlock: View {

    let row: SpecialImportRow

    let columns: [(String, CGFloat)]

    let previewedSongID: Int64?

    @EnvironmentObject
    private var session: SpecialImportSession

    @EnvironmentObject
    private var libraryStore: LibraryStore

    @EnvironmentObject
    private var settings: AppSettings

    private var contentWidth: CGFloat {

        columns.reduce(0) { $0 + $1.1 }
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            blockHeader

            Divider()

            if row.autoMatched {

                if let song = row.chosenSong {

                    SpecialImportSongRow(
                        song: song,
                        columns: columns,
                        mark: .automatic,
                        isPreviewed: isPreviewed(song),
                        isMissing: isMissing(song),
                        onToggle: nil
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {

                        preview(song)
                    }
                }

            } else if row.candidates.isEmpty {

                Text(
                    "No track with this name in the TrackLibrary."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)

            } else {

                columnHeader

                Divider()

                ForEach(
                    Array(
                        row.candidates.enumerated()
                    ),
                    id: \.offset
                ) { index, song in

                    SpecialImportSongRow(
                        song: song,
                        columns: columns,
                        mark: mark(for: song),
                        isPreviewed: isPreviewed(song),
                        isMissing: isMissing(song),
                        onToggle: {

                            toggleChoice(song)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {

                        // Listen before deciding.
                        preview(song)
                    }

                    if index < row.candidates.count - 1 {

                        Divider()
                    }
                }
            }
        }
        .fixedSize(
            horizontal: true,
            vertical: false
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    borderColor
                )
        )
        .opacity(
            row.isSkipped ? 0.5 : 1
        )
    }

    // MARK: Block header

    private var blockHeader: some View {

        HStack(spacing: 8) {

            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)

            VStack(
                alignment: .leading,
                spacing: 1
            ) {

                HStack(spacing: 6) {

                    Text(
                        "\(row.track.sourceIndex + 1)."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Text(row.sourceTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let duration = row.track.duration,
                       duration > 0
                    {

                        Text(
                            String(
                                format: "%d:%02d",
                                duration / 60,
                                duration % 60
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                if let path = row.track.path {

                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
            }

            Spacer(minLength: 8)

            if !row.autoMatched,
               row.chosenSong != nil,
               !row.isSkipped
            {

                Button("Undo") {

                    session.clearChoice(for: row.id)
                }
                .controlSize(.small)
            }

            Button(
                row.isSkipped ? "Include" : "Skip"
            ) {

                session.setSkipped(
                    !row.isSkipped,
                    for: row.id
                )
            }
            .controlSize(.small)
        }
        .frame(
            width: contentWidth,
            alignment: .leading
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: Column header

    private var columnHeader: some View {

        HStack(spacing: 0) {

            ForEach(
                columns,
                id: \.0
            ) { column in

                Text(
                    LibraryColumnDefaults.headerTitle(
                        for: column.0,
                        settings: settings
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(
                    width: column.1,
                    alignment: .leading
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: Helpers

    private func mark(for song: Song) -> SpecialImportMark {

        guard isChosen(song) else {
            return .open
        }

        return row.state == .autoPicked ? .autoPicked : .chosen
    }

    private func isChosen(_ song: Song) -> Bool {

        row.chosenSong?.id == song.id
            && row.chosenSong != nil
            && !row.isSkipped
    }

    private func isPreviewed(_ song: Song) -> Bool {

        song.id != nil
            && previewedSongID == song.id
    }

    private func preview(_ song: Song) {

        NotificationCenter.default.post(
            name: .tandaPreviewSongDoubleClicked,
            object: song
        )
    }

    private func toggleChoice(_ song: Song) {

        if isChosen(song) {
            session.clearChoice(for: row.id)

        } else {

            session.choose(song, for: row.id)
        }
    }

    private func isMissing(_ song: Song) -> Bool {

        guard let id = song.id else {
            return false
        }

        return libraryStore.missingSongIDs.contains(id)
    }

    private var statusSymbol: String {

        switch row.state {

        case .matched, .chosen:
            return "checkmark.circle.fill"

        case .autoPicked:
            return "checkmark.circle"

        case .open:
            return "questionmark.circle.fill"

        case .skipped:
            return "minus.circle.fill"
        }
    }

    private var statusColor: Color {

        switch row.state {

        case .matched, .chosen, .autoPicked:
            return .green

        case .open:
            return .orange

        case .skipped:
            return .secondary
        }
    }

    private var borderColor: Color {

        row.state == .open
            ? Color.orange.opacity(0.6)
            : Color.secondary.opacity(0.25)
    }
}


// MARK: - Mark

/// What the leading column of a candidate row shows.
private enum SpecialImportMark {

    /// Candidate, not chosen: open circle, click to use it.
    case open

    /// Candidate chosen for the import: green check, click to undo.
    case chosen

    /// Suggested by "Auto-pick best file": outlined green check,
    /// click to remove.
    case autoPicked

    /// Exact path match: grey check, always imported, not clickable.
    case automatic
}


// MARK: - Song Row

private struct SpecialImportSongRow: View {

    let song: Song

    let columns: [(String, CGFloat)]

    let mark: SpecialImportMark

    /// Last track listened to with a double-click.
    let isPreviewed: Bool

    let isMissing: Bool

    /// Called by the circle in the leading column. Nil for rows whose
    /// mark is not clickable.
    let onToggle: (() -> Void)?

    @EnvironmentObject
    private var settings: AppSettings

    var body: some View {

        HStack(spacing: 0) {

            ForEach(
                columns,
                id: \.0
            ) { column in

                if column.0.isEmpty {

                    markCell(width: column.1)

                } else {

                    Text(
                        text(for: column.0)
                    )
                    .font(
                        .system(
                            size: LibraryColumnDefaults.rowFontSize
                        )
                    )
                    .foregroundStyle(
                        isMissing ? Color.red : Color.primary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(
                        width: column.1,
                        alignment: .leading
                    )
                    .help(
                        text(for: column.0)
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        // Light blue = last previewed track, as in the other tables.
        // Whether a track is chosen is shown by the mark, not the row.
        .background(
            isPreviewed
                ? Color.accentColor.opacity(0.22)
                : Color.clear
        )
    }

    // MARK: Leading mark

    @ViewBuilder
    private func markCell(width: CGFloat) -> some View {

        switch mark {

        case .automatic:

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: markSize))
                .foregroundStyle(Color.secondary)
                .frame(width: width)
                .help(
                    "Exact path match — included in the new Setlist"
                )

        case .open, .chosen, .autoPicked:

            Button {

                onToggle?()

            } label: {

                Image(systemName: markSymbol)
                    .font(.system(size: markSize))
                    .foregroundStyle(markColor)
                    .frame(width: width)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(markHelp)
        }
    }

    private var markSymbol: String {

        switch mark {

        case .chosen:
            return "checkmark.circle.fill"

        case .autoPicked:
            return "checkmark.circle"

        case .open, .automatic:
            return "circle"
        }
    }

    private var markColor: Color {

        switch mark {

        case .chosen, .autoPicked:
            return .green

        case .open, .automatic:
            return Color.secondary.opacity(0.6)
        }
    }

    private var markHelp: String {

        switch mark {

        case .chosen:
            return "Remove this choice"

        case .autoPicked:

            if let type = song.fileType, !type.isEmpty {
                return "Auto-picked best file (\(type)) — click to remove"
            }

            return "Auto-picked best file — click to remove"

        case .open, .automatic:
            return "Use this track"
        }
    }

    private var markSize: CGFloat {

        LibraryColumnDefaults.rowFontSize + 3
    }

    private func text(
        for columnName: String
    ) -> String {

        if columnName.isEmpty {
            return ""
        }

        return LibraryColumnDefaults.displayValue(
            for: columnName,
            song: song,
            settings: settings
        )
    }
}
