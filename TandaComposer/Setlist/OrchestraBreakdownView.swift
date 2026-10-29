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
import Charts

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

    private struct YearEntry: Identifiable {
        let year: Int
        let count: Int

        var id: Int { year }
    }

    /// Counts setlist song entries by the recording year stored in each
    /// song's metadata. Entries without a year and Cortinas are omitted.
    private var songsByYear: [YearEntry] {
        var counts: [Int: Int] = [:]

        for song in songs where !isCortina(song) {
            guard let year = song.year else { continue }
            counts[year, default: 0] += 1
        }

        return counts
            .map { YearEntry(year: $0.key, count: $0.value) }
            .sorted { $0.year < $1.year }
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

    /// Constrains the horizontal scale to the years actually present in the data.
    /// When only one year exists, a small range around it is needed because a
    /// chart scale cannot meaningfully span a zero-width domain.
    private var songsByYearDomain: ClosedRange<Int> {
        let minYear = songsByYear.first!.year
        let maxYear = songsByYear.last!.year
        // Immer 1 Jahr Rand, damit die äußersten Balken nicht halb
        // abgeschnitten werden und das letzte Tick-Label nicht am Rand klebt.
        return (minYear - 1)...(maxYear + 1)
    }

    /// Jahre, an denen Gridlines und Beschriftungen der X-Achse stehen.
    /// Normal: alle 5 Jahre. Bei sehr kleinen Spannen jedes Jahr,
    /// bei sehr großen Spannen alle 10 Jahre (sonst überlappen die Labels).
    /// Die Ticks liegen immer auf Vielfachen der Schrittweite (1940, 1945, ...).
    private var xAxisTickYears: [Int] {
        let domain = songsByYearDomain
        let span = domain.upperBound - domain.lowerBound

        let step: Int
        switch span {
        case ...9:  step = 1
        case ...50: step = 5
        default:    step = 10
        }

        // Erstes Vielfaches der Schrittweite innerhalb der Domain
        let first = (domain.lowerBound + step - 1) / step * step
        return Array(stride(from: first, through: domain.upperBound, by: step))
    }

    /// Volle Jahreszahl beim ersten Tick und bei Jahrhundertwechseln,
    /// sonst nur die letzten beiden Stellen (z. B. 1935, 40, 45 ... 1995, 2000, 05).
    private func xAxisLabel(for year: Int) -> String {
        let isFirst = year == xAxisTickYears.first
        let isCenturyChange = year % 100 == 0

        if isFirst || isCenturyChange {
            return String(year)
        }
        return String(format: "%02d", year % 100)
    }

    /// Balkenfarbe nach Jahr (Grenzen jeweils inklusive).
    /// Grün (1938 bis 1948) hat Vorrang vor Gelb (1935 bis 1955).
    /// Ab 1956 orange, alle Jahre davor (bis 1934) behalten die Akzentfarbe.
    private func barColor(for year: Int) -> Color {
        switch year {
        case 1938...1948: return .green
        case 1935...1955: return .yellow
        case 1956...:     return .orange
        default:          return .accentColor
        }
    }

    /// Feste Balkenbreite in Punkten, abgeleitet aus der Zahl der Jahre
    /// in der Domain (Plotbreite grob 370 pt, ca. 15 % Lücke zwischen Balken).
    /// `.ratio` hat auf der Int-Achse keine Balken gezeichnet.
    private var barWidth: CGFloat {
        let domain = songsByYearDomain
        let span = max(1, domain.upperBound - domain.lowerBound)
        let perYear = 370.0 / Double(span)
        return CGFloat(min(max(perYear * 0.85, 2), 24))
    }

    // MARK: - Legend for year colors

    private var yearColorLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                legendItem(color: .accentColor, text: "1917 ...  1934 (Guardia Nueva) ")
                legendItem(
                    color: .yellow,
                    text: "1935 ... 1955 (Época de Oro)"
                )
            }

            HStack(spacing: 16) {
                legendItem(color: .green, text: "1938 ... 1948 (Década dorada)")
                legendItem(color: .orange, text: "1956 ... ")
            }
        }
        .font(.caption)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)

            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private var songsByYearChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Songs by Year")
                .font(.headline)

            yearColorLegend

            if songsByYear.isEmpty {
                Text("No songs with year metadata in the current Set.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(songsByYear) { entry in
                    BarMark(
                        x: .value("Year", entry.year),
                        y: .value("Song Number", entry.count),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(barColor(for: entry.year))
                }
                .chartXScale(domain: songsByYearDomain)
                .chartXAxis {
                    AxisMarks(values: xAxisTickYears) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let year = value.as(Int.self) {
                                Text(xAxisLabel(for: year))
                            }
                        }
                    }
                }
                // Platz rechts, damit das letzte Label nicht zu "..." gekürzt wird.
                .chartPlotStyle { plot in
                    plot.padding(.trailing, 16)
                }
                .chartXAxisLabel("Year")
                .chartYAxisLabel("Song Number")
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                // Chart füllt die verfügbare Höhe, damit X-Achse und
                // Achsenlabel innerhalb des Popovers liegen.
                .frame(maxHeight: .infinity)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 430, alignment: .topLeading)
        .padding(.top, 16)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    Text("No Tanda songs in the current Set.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
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
            .frame(width: 360, alignment: .topLeading)

            Divider()

            songsByYearChart
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        // Feste Gesamtgröße, damit das Popover nicht anhand der
        // ScrollView-Idealgröße zu klein berechnet wird.
        // Breite: 12 + 360 + 18 + Divider + 18 + 430 + 12 ≈ 851
        .frame(width: 860, height: 500, alignment: .topLeading)
    }
}
