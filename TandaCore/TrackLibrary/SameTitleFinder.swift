//
//  SameTitleFinder.swift
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

import Foundation

// MARK: - Result types

/// One title and every track of the TrackLibrary that carries it.
public nonisolated struct SameTitleGroup: Identifiable, Equatable {

    /// The normalized title (the grouping key).
    public let id: String

    /// The title as written on the first selected track.
    public let title: String

    /// The selected tracks with this title, in selection order.
    public let anchors: [Song]

    /// Every track with this title: the anchors first, then the others
    /// by year, orchestra, singer.
    public let songs: [Song]

    /// Tracks with this title other than the selected ones.
    public var otherCount: Int {
        songs.count - anchors.count
    }
}

public nonisolated struct SameTitleResult: Equatable {

    /// One group per distinct title, in selection order, at most
    /// `SameTitleFinder.maxGroups`.
    public let groups: [SameTitleGroup]

    /// Distinct titles that did not fit into `groups`.
    public let omittedTitleCount: Int

    /// Selected tracks without any usable title.
    public let untitled: [Song]

    public var isEmpty: Bool {
        groups.isEmpty && untitled.isEmpty
    }
}


// MARK: - Finder

/// Finds the tracks of the TrackLibrary that have the same title as the
/// selected ones: the "?" button of the TrackLibrary header.
///
/// "Same title" is strict: equal after the shared normalization of
/// `TrackTextNormalizer` (case, accents, apostrophe variants, runs of
/// spaces). "Poema" and "Poema (remastered)" are different titles.
public nonisolated enum SameTitleFinder {

    /// More distinct titles than this are cut off and counted in
    /// `SameTitleResult.omittedTitleCount`.
    public static let maxGroups = 8

    /// The normalized title of a track, or nil when it has none. A track
    /// without a title tag is looked up by its file name (without suffix).
    public static func titleKey(of song: Song) -> String? {

        if let title = song.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           let key = TrackTextNormalizer.normalize(title) {

            return key
        }

        return TrackTextNormalizer.normalize(
            AudioFileSuffix.strip(song.filename).stem
        )
    }

    /// The title as shown: the tag, or the file name without suffix.
    public static func displayTitle(of song: Song) -> String {

        if let title = song.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {

            return title
        }

        return AudioFileSuffix.strip(song.filename).stem
    }

    /// - Parameters:
    ///   - selected: the selected tracks, in the order they are shown.
    ///   - library: every track of the TrackLibrary, regardless of the
    ///     active Smartlist or search filter.
    ///   - orchestraSource: where the orchestra is tagged (sorting only).
    ///   - singerSource: where the singer is tagged (sorting only).
    public static func find(
        for selected: [Song],
        in library: [Song],
        orchestraSource: TagSource = .artist,
        singerSource: TagSource = .albumArtist
    ) -> SameTitleResult {

        // 1. Group the selected tracks by title, in selection order.
        var keyOrder: [String] = []
        var anchorsByKey: [String: [Song]] = [:]
        var untitled: [Song] = []

        for song in selected {

            guard let key = titleKey(of: song) else {
                untitled.append(song)
                continue
            }

            if anchorsByKey[key] == nil {
                keyOrder.append(key)
            }

            anchorsByKey[key, default: []].append(song)
        }

        let shownKeys = Array(keyOrder.prefix(maxGroups))
        let omitted = max(0, keyOrder.count - maxGroups)
        let wanted = Set(shownKeys)

        // 2. The other tracks with those titles, from the whole library.
        let selectedPaths = Set(selected.map(\.normalizedPath))
        var othersByKey: [String: [Song]] = [:]

        if !wanted.isEmpty {

            for song in library {

                guard !selectedPaths.contains(song.normalizedPath),
                      let key = titleKey(of: song),
                      wanted.contains(key)
                else {
                    continue
                }

                othersByKey[key, default: []].append(song)
            }
        }

        // 3. One group per title.
        let groups = shownKeys.compactMap { key -> SameTitleGroup? in

            guard let anchors = anchorsByKey[key],
                  let first = anchors.first
            else {
                return nil
            }

            let others = (othersByKey[key] ?? []).sorted {
                isOrderedBefore(
                    $0,
                    $1,
                    orchestraSource: orchestraSource,
                    singerSource: singerSource
                )
            }

            // Keep the first selected track as the fixed anchor. Then move
            // the remaining tracks of that same orchestra directly after it;
            // preserve the existing relative order within both partitions.
            let anchorOrchestra = orchestraKey(
                for: first,
                source: orchestraSource
            )
            let remaining = Array(anchors.dropFirst()) + others

            let sameOrchestra: [Song]
            let otherOrchestras: [Song]

            if let anchorOrchestra {
                sameOrchestra = remaining.filter {
                    orchestraKey(for: $0, source: orchestraSource) == anchorOrchestra
                }
                otherOrchestras = remaining.filter {
                    orchestraKey(for: $0, source: orchestraSource) != anchorOrchestra
                }
            } else {
                // Missing orchestra metadata is not treated as a shared orchestra.
                sameOrchestra = []
                otherOrchestras = remaining
            }

            return SameTitleGroup(
                id: key,
                title: displayTitle(of: first),
                anchors: anchors,
                songs: [first] + sameOrchestra + otherOrchestras
            )
        }

        return SameTitleResult(
            groups: groups,
            omittedTitleCount: omitted,
            untitled: untitled
        )
    }

    // MARK: Order

    /// A normalized orchestra key using the user's configured tag source.
    /// Empty/missing values remain nil so unrelated unknown values are not
    /// incorrectly treated as the same orchestra.
    private static func orchestraKey(
        for song: Song,
        source: TagSource
    ) -> String? {

        guard let value = song.rawTagValue(for: source),
              let key = TrackTextNormalizer.normalize(value)
        else {
            return nil
        }

        return key
    }

    /// Year (unknown last), then orchestra, then singer, then path, so
    /// that the order never jumps around between two searches.
    private static func isOrderedBefore(
        _ lhs: Song,
        _ rhs: Song,
        orchestraSource: TagSource,
        singerSource: TagSource
    ) -> Bool {

        switch (lhs.year, rhs.year) {

        case let (left?, right?) where left != right:
            return left < right

        case (nil, _?):
            return false

        case (_?, nil):
            return true

        default:
            break
        }

        let orchestra = (lhs.rawTagValue(for: orchestraSource) ?? "")
            .localizedStandardCompare(rhs.rawTagValue(for: orchestraSource) ?? "")

        if orchestra != .orderedSame {
            return orchestra == .orderedAscending
        }

        let singer = (lhs.rawTagValue(for: singerSource) ?? "")
            .localizedStandardCompare(rhs.rawTagValue(for: singerSource) ?? "")

        if singer != .orderedSame {
            return singer == .orderedAscending
        }

        return lhs.normalizedPath < rhs.normalizedPath
    }
}
