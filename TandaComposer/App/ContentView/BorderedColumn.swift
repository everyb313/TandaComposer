//  Extracted from ContentView.swift

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Bordered Column

struct BorderedColumn:
    ViewModifier {

    func body(
        content:
            Content
    ) -> some View {

        content
            .overlay(
                RoundedRectangle(
                    cornerRadius:
                        6
                )
                .stroke(
                    Color.secondary.opacity(
                        0.55
                    ),
                    lineWidth:
                        1
                )
            )
            .padding(
                1
            )
    }
}

