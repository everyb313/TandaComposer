//
//  SetlistRowView.swift
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

// MARK: - Setlist Row View

final class PlaylistRowView: NSTableRowView {

    enum TandaType {

        case none
        case tango
        case milonga
        case vals
    }

    var isDuplicateHighlighted = false {

        didSet {
            needsDisplay = true
        }
    }

    var tandaType: TandaType = .none {

        didSet {
            needsDisplay = true
        }
    }

    override func drawBackground(
        in dirtyRect: NSRect
    ) {

        super.drawBackground(
            in: dirtyRect
        )

        let tandaColor: NSColor?

        switch tandaType {

        case .tango:

            tandaColor =
                NSColor.systemYellow
                    .withAlphaComponent(0.14)

        case .milonga:

            tandaColor =
                NSColor.systemRed
                    .withAlphaComponent(0.14)

        case .vals:

            tandaColor =
                NSColor.systemGreen
                    .withAlphaComponent(0.14)

        case .none:

            tandaColor = nil
        }

        if let tandaColor {

            tandaColor.setFill()

            dirtyRect.fill()
        }

        if isDuplicateHighlighted {

            NSColor.systemOrange
                .withAlphaComponent(0.25)
                .setFill()

            dirtyRect.fill()
        }
    }

    override func draw(
        _ dirtyRect: NSRect
    ) {

        super.draw(
            dirtyRect
        )
    }
}
