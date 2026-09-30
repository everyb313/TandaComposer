
//
//  OrchestraBreakdownView.swift
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

/// A one-off snapshot of how many Tandas in the active Setlist
/// belong to each Orchestra.
///
/// Tanda boundaries are determined by Cortinas:
/// - Everything between two Cortinas belongs to one Tanda.
/// - If all songs in that Tanda belong to the same orchestra,
///   that orchestra gets one Tanda.
/// - If songs from multiple orchestras occur within the same Tanda,
///   it is counted as one "Mixed" Tanda.
///
/// Special handling for the final track:
/// - If the final track has an orchestra already present in the
///   preceding Tanda, it remains part of that Tanda.
/// - If the final track has a different orchestra, it is treated
///   as a separate closing track and is not counted.
///
/// The view is deliberately NOT live: `songs` is evaluated from
/// whatever was passed in when the popover opened.

struct OrchestraBreakdownView: View {
    let songs: [Song]

    @EnvironmentObject private var settings: AppSettings

    private struct Entry: Identifiable {
        let orchestra: String
        let count: Int

        var id: String {
            orchestra
        }
    }

    // Cortinas are not tango songs and do not belong to an orchestra.
    // They also mark the boundary between two Tandas.
    private func isCortina(_ song: Song) -> Bool {
        (song.genre ?? "")
            .localizedCaseInsensitiveContains("cortina")
    }

    // Some tags are written "Troilo, Aníbal" while others simply
    // contain "Troilo". Both should be treated as the same orchestra.
    //
    // Taking everything before the first comma is deliberate and
    // deterministic. It does not attempt fuzzy matching.
    private func normalizedOrchestraName(_ raw: String?) -> String {
        guard
            let raw,
            !raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        else {
            return "Unknown"
        }

        let beforeComma =
            raw
                .split(separator: ",", maxSplits: 1)
                .first
                .map(String.init)
                ?? raw

        let trimmed =
            beforeComma
                .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    // These orchestras should be emphasized in the table.
    //
    // Matching is case-insensitive and deliberately uses search terms
    // rather than exact names, so "Di Sarli" matches "Sarli" and
    // "D'Arienzo" matches "Arienzo".
    private func isMajorOrchestra(_ orchestra: String) -> Bool {
        let searchTerms = [
            "Troilo",
            "Sarli",
            "Pugliese",
            "Arienzo"
        ]

        return searchTerms.contains {
            orchestra.localizedCaseInsensitiveContains($0)
        }
    }

    /// Counts Tandas by Orchestra.
    ///
    /// A Tanda is defined as all non-Cortina songs between two Cortinas.
    ///
    /// Example:
    ///
    ///     Troilo
    ///     Troilo
    ///     Troilo
    ///     Cortina
    ///
    /// counts as:
    ///
    ///     Troilo: 1
    ///
    /// Whereas:
    ///
    ///     Troilo
    ///     Di Sarli
    ///     Troilo
    ///     Cortina
    ///
    /// counts as:
    ///
    ///     Mixed: 1
    ///
    /// The final track has one special rule:
    ///
    ///     Di Sarli
    ///     Di Sarli
    ///     Pugliese
    ///
    /// becomes:
    ///
    ///     Di Sarli: 1
    ///
    /// because Pugliese is considered a separate closing track.
    ///
    /// If the final track's orchestra is already represented in the
    /// preceding Tanda, it remains part of that Tanda.
    private var entries: [Entry] {
        var tandaCounts: [String: Int] = [:]

        // All different orchestras encountered in the current Tanda.
        var currentOrchestras: Set<String> = []

        func finishTanda() {
            guard !currentOrchestras.isEmpty else {
                return
            }

            let key: String

            if currentOrchestras.count == 1 {
                key = currentOrchestras.first!
            } else {
                key = "Mixed"
            }

            tandaCounts[key, default: 0] += 1
            currentOrchestras.removeAll()
        }

        for (index, song) in songs.enumerated() {
            if isCortina(song) {
                finishTanda()
                continue
            }

            let orchestra =
                normalizedOrchestraName(
                    song.resolvedOrchestra(using: settings)
                )

            let isLastTrack = index == songs.count - 1

            // Special handling for the final track.
            //
            // If there is already a Tanda in progress and the final
            // track's orchestra has not appeared in that Tanda, treat
            // the final track as a separate closing track and ignore it.
            if isLastTrack,
               !currentOrchestras.isEmpty,
               !currentOrchestras.contains(orchestra) {
                break
            }

            currentOrchestras.insert(orchestra)
        }

        // Count the final Tanda, even if there is no trailing Cortina.
        finishTanda()

        return
            tandaCounts
                .map {
                    Entry(
                        orchestra: $0.key,
                        count: $0.value
                    )
                }
                .sorted {
                    if $0.count != $1.count {
                        return $0.count > $1.count
                    }

                    return $0.orchestra.localizedCaseInsensitiveCompare(
                        $1.orchestra
                    ) == .orderedAscending
                }
    }

    var body: some View {
        if entries.isEmpty {
            Text("No Tanda songs in the current Set.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: - Table Title

                Text("Tandas by Orchestra")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom, 8)

                // MARK: - Table

                ScrollView {
                    Grid(
                        horizontalSpacing: 0,
                        verticalSpacing: 0
                    ) {
                        // MARK: - Header

                        GridRow {
                            Text("Orchestra")
                                .font(.headline)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )

                            Text("# of Tandas")
                                .font(.headline)
                                .frame(
                                    width: 100,
                                    alignment: .trailing
                                )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.quaternary)

                        // MARK: - Rows

                        ForEach(entries) { entry in
                            GridRow {
                                Text(entry.orchestra)
                                    .fontWeight(
                                        isMajorOrchestra(entry.orchestra)
                                            ? .bold
                                            : .regular
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )

                                Text("\(entry.count)")
                                    .frame(
                                        width: 100,
                                        alignment: .trailing
                                    )
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)

                            Divider()
                        }
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                .quaternary,
                                lineWidth: 1
                            )
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .frame(maxHeight: 400)
            }
        }
    }
}
