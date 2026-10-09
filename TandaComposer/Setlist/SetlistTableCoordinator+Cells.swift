//
//  SetlistTableCoordinator+Cells.swift
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


import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Coordinator: cells & row styling

extension PlaylistTableCoordinator {

    // MARK: - Cell

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {

        guard
            let column = tableColumn,
            row >= 0,
            row < entries.count
        else {
            return nil
        }

        let entry = entries[row]
        let song = entry.song

        if column.identifier.rawValue == "#" {

            let field =
                NSTextField(
                    labelWithString:
                        "\(row + 1)"
                )

            field.font =
                LibraryColumnDefaults.rowFont

            field.textColor =
                .secondaryLabelColor

            field.alignment = .right

            return field
        }

        if column.identifier.rawValue == "Status" {

            let imageView = NSImageView()

            imageView.imageScaling =
                .scaleProportionallyDown

            let symbolConfiguration =
                NSImage.SymbolConfiguration(
                    pointSize: 8,
                    weight: .regular
                )

            if entry.status == .fileMissing {

                imageView.image =
                    NSImage(
                        systemSymbolName:
                            "octagon.fill",
                        accessibilityDescription:
                            "File not found"
                    )?
                    .withSymbolConfiguration(
                        symbolConfiguration
                    )

                imageView.contentTintColor =
                    .systemRed

                imageView.toolTip =
                    "File not found on disk"

            } else if entry.status == .notInLibrary {

                imageView.image =
                    NSImage(
                        systemSymbolName:
                            "questionmark.circle.fill",
                        accessibilityDescription:
                            "Not in current Library"
                    )?
                    .withSymbolConfiguration(
                        symbolConfiguration
                    )

                imageView.contentTintColor =
                    .systemBlue

                imageView.toolTip =
                    "Not found in the current Library — showing saved info"

            } else if entry.status == .staleReference {

                // Not currently produced by resolveAgainstLibrary
                // below (it always re-links to the live Library
                // song on a path match, so a Setlist entry can't
                // end up "known but stale" the way a Tanda's saved
                // snapshot can — see TandaBlock.status(for:) in
                // TandaLibraryView.swift). Handled here anyway so
                // this stays correct if that ever changes.
                imageView.image =
                    NSImage(
                        systemSymbolName:
                            "exclamationmark.triangle.fill",
                        accessibilityDescription:
                            "Outdated reference"
                    )?
                    .withSymbolConfiguration(
                        symbolConfiguration
                    )

                imageView.contentTintColor =
                    .systemOrange

                imageView.toolTip =
                    "The TrackLibrary already found this file at a new location, but this reference hasn't been re-linked to it yet."

            } else {

                imageView.image = nil
            }

            return imageView
        }

        if column.identifier.rawValue == "Sum" {

            let totalSeconds =
                entries[0...row].reduce(0) {
                    $0 + ($1.song.duration ?? 0)
                }

            let totalMinutes =
                (totalSeconds + 30) / 60

            let hours =
                totalMinutes / 60

            let minutes =
                totalMinutes % 60

            let field =
                NSTextField(
                    labelWithString:
                        "\(hours):\(String(format: "%02d", minutes))"
                )

            field.font =
                LibraryColumnDefaults.rowFont

            field.textColor =
                .secondaryLabelColor

            field.alignment = .center

            return field
        }

        let value =
            LibraryColumnDefaults.displayValue(
                for:
                    column.identifier.rawValue,
                song:
                    song,
                settings:
                    self.settings
            )

        let field =
            NSTextField(
                labelWithString:
                    value
            )

        field.lineBreakMode =
            .byTruncatingTail

        field.font =
            LibraryColumnDefaults.rowFont

        return field
    }

    // MARK: - Row View

    func tableView(
        _ tableView: NSTableView,
        rowViewForRow row: Int
    ) -> NSTableRowView? {

        let rowView =
            PlaylistRowView()

        guard
            row >= 0,
            row < entries.count
        else {
            return rowView
        }

        rowView.isDuplicateHighlighted =
            duplicateSongIDs.contains(
                entries[row].song.id
            )

        rowView.tandaType =
            tandaType(
                forRow: row
            )
        return rowView
    }

    // MARK: - Tanda Type

    func tandaType(
        forRow row: Int
    ) -> PlaylistRowView.TandaType {

        guard isTandaColoringEnabled else {
            return .none
        }

        guard entries.indices.contains(row) else {
            return .none
        }

        if isCortinaRow(row) {
            return .none
        }

        let genre =
            entries[row].song.genre ?? ""

        let normalized =
            genre
                .folding(
                    options: [
                        .diacriticInsensitive,
                        .caseInsensitive
                    ],
                    locale: .current
                )
                .lowercased()
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        if normalized.contains("milonga") ||
           normalized.contains("candombe") ||
           normalized.contains("otra") ||
           normalized.contains("foxtrot") {

            return .milonga
        }

        if normalized.contains("vals") {
            return .vals
        }

        if normalized.contains("tango") {
            return .tango
        }

        return .none
    }

    // MARK: - Cortina Detection

    func isCortinaRow(
        _ row: Int
    ) -> Bool {

        guard
            entries.indices.contains(row)
        else {
            return false
        }

        let genre =
            entries[row].song.genre ?? ""

        return genre.localizedCaseInsensitiveContains(
            "cortina"
        )
    }
}
