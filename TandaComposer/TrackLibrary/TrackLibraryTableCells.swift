//
//  TrackLibraryTableCells.swift
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
import AppKit

// MARK: - Focusable Library NSTableView

final class LibraryNSTableView:
    NSTableView {

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(
        with event: NSEvent
    ) {

        window?.makeFirstResponder(self)

        let coordinator =
            delegate as? LibraryTableCoordinator

        coordinator?.handleMouseClick(
            self,
            event: event
        )

        super.mouseDown(
            with: event
        )
    }
}


// MARK: - Cell factory

enum LibraryTableCells {

    static func cell(
        forColumn columnName:
            String,
        song:
            Song,
        isMissing:
            Bool,
        settings:
            AppSettings
    ) -> NSView {

        if columnName ==
            "Status" {

            let imageView =
                NSImageView()

            if isMissing {

                let configuration =
                    NSImage.SymbolConfiguration(
                        pointSize:
                            8,
                        weight:
                            .regular
                    )

                imageView.image =
                    NSImage(
                        systemSymbolName:
                            "octagon.fill",
                        accessibilityDescription:
                            "File not found"
                    )?
                    .withSymbolConfiguration(
                        configuration
                    )

                imageView.contentTintColor =
                    .systemRed

                imageView.toolTip =
                    "File not found on disk"

            } else {

                imageView.image =
                    nil
            }

            imageView.imageScaling =
                .scaleProportionallyDown

            return imageView
        }


        let value =
            LibraryColumnDefaults.displayValue(
                for:
                    columnName,
                song:
                    song,
                settings:
                    settings
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
}


// MARK: - Cross-Setlist Duplicate Row

final class LibraryTableRowView: NSTableRowView {

    var isCrossSetlistDuplicate = false {
        didSet {
            needsDisplay = true
        }
    }

    override func drawBackground(
        in dirtyRect: NSRect
    ) {

        super.drawBackground(in: dirtyRect)

        guard isCrossSetlistDuplicate else {
            return
        }

        NSColor.systemOrange
            .withAlphaComponent(0.25)
            .setFill()

        dirtyRect.fill()
    }
}
