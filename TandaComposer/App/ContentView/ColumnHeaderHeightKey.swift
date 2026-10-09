//  Extracted from ContentView.swift

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Column Header Height Sync
//
// Set / Library / Smartlists column headers have different content
// (segmented Picker vs plain Text vs Text + optional lock icon), so
// their natural heights differ — and the Smartlists header's own
// height even varies between its three modes (lock icon shown only
// in Tracks mode). Each header reports its intrinsic height via this
// preference key; ContentView keeps the max in `columnHeaderHeight`
// and applies it back to all three headers, so they always line up
// regardless of mode or font.

struct ColumnHeaderHeightKey: PreferenceKey {

    static var defaultValue: CGFloat = 0

    static func reduce(
        value: inout CGFloat,
        nextValue: () -> CGFloat
    ) {

        value =
            max(
                value,
                nextValue()
            )
    }
}


