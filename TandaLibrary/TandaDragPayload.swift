//
//  TandaDragPayload.swift
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


// MARK: - Tanda Drag Payload
//
// A whole Tanda's songs + the drag's insertion mode (Add/Insert),
// encoded as ONE plain string delivered via the reliable `.string`
// pasteboard type only — deliberately NOT a second registered custom
// UTI/pasteboard type. A previous attempt at registering a distinct
// type identifier here (`registerDataRepresentation(forTypeIdentifier:)`)
// made macOS request an unresolvable dynamic UTI
// ("dyn.agu80g55...") for local same-app drags; `.string` via
// `NSItemProvider(object:)` is what's proven reliable, so the mode
// marker is embedded INSIDE that same string instead of adding a
// second pasteboard entry.
//
// Format: "<add|insert>:<id>,<id>,<id>,..."

enum TandaDragPayload {

    struct Decoded {

        let mode: SetInsertionMode
        let songIDs: [Int64]
    }


    // MARK: - Encode

    /// Encodes the ids to actually use for this drag — NOT
    /// necessarily `tanda.songs`' own stored ids verbatim: if this
    /// Tanda was last saved against a DIFFERENT TrackLibrary (see
    /// `Tanda.savedAgainstLibraryName`), those ids are independently
    /// auto-incremented numbers from another database and would be
    /// coincidence, not identity, if trusted here — the drop side
    /// (PlaylistView) only receives bare ids over the pasteboard, no
    /// paths, so there's no chance to correct a wrong id after the
    /// fact. Resolving against the current Library HERE, before
    /// anything is encoded, means the drop side's simple id lookup
    /// stays correct without needing to change at all.
    static func encode(
        _ tanda:
            Tanda,
        mode:
            SetInsertionMode,
        byID:
            [Int64: Song],
        byPath:
            [String: Song],
        missingSongIDs:
            Set<Int64>
    ) -> String {

        let trustID =
            tanda.savedAgainstLibraryName == AppPaths.currentLibraryName

        let ids =
            tanda.songs
                .compactMap { song -> String? in

                    guard
                        let liveID =
                            LibraryReferenceResolver.resolve(
                                song,
                                byID: byID,
                                byPath: byPath,
                                missingSongIDs: missingSongIDs,
                                trustID: trustID
                            ).live?.id
                    else {
                        return nil
                    }

                    return String(
                        liveID
                    )
                }
                .joined(
                    separator:
                        ","
                )

        let modeToken =
            mode == .insert
            ? "insert"
            : "add"

        return "\(modeToken):\(ids)"
    }


    // MARK: - Decode

    static func decode(
        _ value:
            String
    ) -> Decoded? {

        guard
            let colonIndex =
                value.firstIndex(
                    of:
                        ":"
                )
        else {

            return nil
        }


        let modeToken =
            value[
                value.startIndex
                ..<
                colonIndex
            ]

        let idsToken =
            value[
                value.index(
                    after:
                        colonIndex
                )...
            ]


        let mode:
            SetInsertionMode =
                modeToken == "insert"
                ? .insert
                : .add

        let ids =
            idsToken
                .split(
                    separator:
                        ","
                )
                .compactMap {
                    Int64($0)
                }


        guard
            !ids.isEmpty
        else {

            return nil
        }


        return Decoded(
            mode:
                mode,
            songIDs:
                ids
        )
    }
}
