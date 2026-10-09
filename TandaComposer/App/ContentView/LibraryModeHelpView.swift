//  Extracted from ContentView.swift

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Library Mode Help

// Same three explanations that used to live in a single plain-text
// .help() tooltip on the TrackLibrary/TandaLibrary/Setlist Picker —
// moved into a popover (triggered by the "?" button next to the
// Picker) so the three titles can be set in a larger, bold font
// instead of flattened into tooltip text.
struct LibraryModeHelpView: View {

    private struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    private let sections: [Section] = [

        Section(
            title: "Track Library",
            body: "For experienced DJs: Build your setlist from " +
                "scratch, refining your selection by building " +
                "your own Smartlist — add tracks and narrow them " +
                "down using orchestra and singer combinations. " +
                "This gives you full control over your track " +
                "selection and lets you build every part of your " +
                "set individually."
        ),

        Section(
            title: "Tanda Library",
            body: "For beginners: Build your own Tanda Library by " +
                "grouping tracks into musically compatible sets " +
                "and saving them as Tandas. The system " +
                "automatically recognizes the orchestra and " +
                "singer combinations and adds the corresponding " +
                "Tandas to the Smartlist. This allows you to " +
                "quickly find the right Tandas by orchestra and " +
                "singer when building your setlist."
        ),

        Section(
            title: "Setlists",
            body: "For smart — or simply lazy — DJs: Reuse " +
                "setlists you have already created and save " +
                "yourself the effort of starting from scratch. " +
                "Copy an entire setlist or just the parts you " +
                "like, then adapt, extend, and reuse them for " +
                "your next event."
        )
    ]


    var body: some View {

        ScrollView {

            VStack(
                alignment: .leading,
                spacing: 18
            ) {

                ForEach(sections) { section in

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {

                        Text(section.title)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                }
            }
            .padding(20)
        }
        .frame(
            width: 420,
            height: 420
        )
    }
}


