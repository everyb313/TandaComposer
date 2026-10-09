//  Extracted from ContentView.swift

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Import Progress

struct ImportProgressBar:
    View {

    @ObservedObject var scanner:
        LibraryScanner


    var body:
        some View {

        VStack(
            spacing:
                4
        ) {

            ProgressView(
                value:
                    Double(
                        scanner.processedCount
                    ),
                total:
                    Double(
                        max(
                            scanner.totalCount,
                            1
                        )
                    )
            )

            Text(
                "Importing \(scanner.processedCount) " +
                "of \(scanner.totalCount)…"
            )
            .font(
                .caption
            )
            .foregroundStyle(
                .secondary
            )
        }
        .padding(
            8
        )
        .background(
            .regularMaterial
        )
    }
}


