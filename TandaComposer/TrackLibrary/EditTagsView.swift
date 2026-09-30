//
//  EditTagsView.swift
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


// MARK: - Edit Tags
//
// Form-only — deliberately doesn't call TagEditingActions itself (that
// stays the caller's job, same delegation shape as
// CleanUpMissingLinksView's onConfirm), so this view has no async
// work, no progress state, nothing to get wrong about ordering. The
// caller is expected to dismiss the sheet and kick off
// TagEditingActions.apply(...) in the background once onApply fires.
//
// Works for one song OR many at once. Each field starts prefilled
// ONLY if every one of `songs` already shares the exact same value
// for it; otherwise it starts blank with a "Multiple Values" prompt
// instead of a normal placeholder, so a blank field never gets
// confused for "they're all already blank".
//
// A field left blank at Apply time always means "leave unchanged" —
// same as a nil TagChanges field everywhere else in this app. There's
// no way through this sheet to explicitly blank out a tag across many
// songs at once; that's a deliberate simplification, not an oversight
// (see TagEditingActions' own doc comment).

struct EditTagsView: View {

    let songs: [Song]

    let onCancel: () -> Void
    let onApply: (TagChanges) -> Void


    @State
    private var title = ""

    @State
    private var artist = ""

    @State
    private var albumArtist = ""

    @State
    private var genre = ""

    @State
    private var year = ""

    @State
    private var comment = ""


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            HStack {

                Text(
                    songs.count == 1
                    ? "Edit Tags"
                    : "Edit Tags (\(songs.count) tracks)"
                )
                .font(.title2)
                .bold()

                Spacer()
            }
            .padding(8)

            Divider()

            Text(
                "Leave a field blank to leave it unchanged. For multiple tracks with different values, a field starts blank (\"Multiple Values\") — typing something there sets it for ALL selected tracks."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
            .padding(8)


            // =====================================================
            // FIELDS
            // =====================================================

            Form {

                field(
                    "Title",
                    text: $title,
                    isMixed: isMixed(\.title)
                )

                field(
                    "Orchestra (Artist)",
                    text: $artist,
                    isMixed: isMixed(\.artist)
                )

                field(
                    "Singer (AlbumArtist)",
                    text: $albumArtist,
                    isMixed: isMixed(\.albumArtist)
                )

                field(
                    "Genre",
                    text: $genre,
                    isMixed: isMixed(\.genre)
                )

                field(
                    "Year",
                    text: $year,
                    isMixed: isYearMixed
                )

                field(
                    "Comment",
                    text: $comment,
                    isMixed: isMixed(\.comment)
                )
            }
            .padding(8)


            Divider()

            HStack {

                Spacer()

                Button("Cancel") {
                    onCancel()
                }

                Button("Apply") {
                    onApply(changes)
                }
                .disabled(
                    changes.isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
            .padding(8)
        }
        .frame(
            minWidth: 420,
            minHeight: 360
        )
        .onAppear {
            prefill()
        }
    }


    // MARK: - One Field Row

    @ViewBuilder
    private func field(
        _ label: String,
        text: Binding<String>,
        isMixed: Bool
    ) -> some View {

        TextField(
            label,
            text: text,
            prompt:
                isMixed
                ? Text("Multiple Values")
                : nil
        )
    }


    // MARK: - Prefill

    private func prefill() {

        title = commonString(\.title)
        artist = commonString(\.artist)
        albumArtist = commonString(\.albumArtist)
        genre = commonString(\.genre)
        year = commonYear()
        comment = commonString(\.comment)
    }

    private func commonString(
        _ keyPath: KeyPath<Song, String?>
    ) -> String {

        let values =
            Set(
                songs.map {
                    $0[keyPath: keyPath] ?? ""
                }
            )

        return values.count == 1
            ? (values.first ?? "")
            : ""
    }

    private func commonYear() -> String {

        let values =
            Set(
                songs.map(\.year)
            )

        guard
            values.count == 1,
            let onlyYear = values.first,
            let year = onlyYear
        else {
            return ""
        }

        return String(year)
    }

    private func isMixed(
        _ keyPath: KeyPath<Song, String?>
    ) -> Bool {

        Set(
            songs.map {
                $0[keyPath: keyPath] ?? ""
            }
        )
        .count > 1
    }

    private var isYearMixed: Bool {

        Set(
            songs.map(\.year)
        )
        .count > 1
    }


    // MARK: - Changes

    /// Blank fields become nil (— "leave unchanged", see the type-level
    /// doc comment above). `year` is left as a plain String here — the
    /// Int parsing happens once, downstream, in TagEditingActions.
    private var changes: TagChanges {

        TagChanges(
            title: title.isEmpty ? nil : title,
            artist: artist.isEmpty ? nil : artist,
            albumArtist: albumArtist.isEmpty ? nil : albumArtist,
            genre: genre.isEmpty ? nil : genre,
            year: year.isEmpty ? nil : year,
            comment: comment.isEmpty ? nil : comment
        )
    }
}
