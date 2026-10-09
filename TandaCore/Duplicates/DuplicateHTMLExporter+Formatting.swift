//
//  DuplicateHTMLExporter+Formatting.swift
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

//
//  DuplicateHTMLExporter.swift
//  TandaComposer
//

import Foundation

// MARK: - Source highlighting, TT detection, formatting

extension DuplicateHTMLExporter {

    // MARK: - Source Highlighting
    // =============================================================

    static func sourceClassForPath(
        _ path: String
    ) -> String {

        let lowercased =
            path.lowercased()

        if lowercased.contains(
            "tango time travel"
        )
        || lowercased.contains(
            "tangotime travel"
        )
        || lowercased.contains(
            "tango_time_travel"
        ) {

            return "source-ttt"
        }

        if lowercased.contains(
            "tango tunes"
        )
        || lowercased.contains(
            "tangotunes"
        )
        || containsStandaloneTT(
            lowercased
        ) {

            return "source-tt"
        }

        return ""
    }

    // =============================================================
    // MARK: - Standalone TT Detection
    // =============================================================

    private static func containsStandaloneTT(
        _ text: String
    ) -> Bool {

        let characters =
            Array(text)

        guard characters.count >= 2 else {
            return false
        }

        for index in
            0..<(characters.count - 1) {

            guard
                characters[index] == "t",
                characters[index + 1] == "t"
            else {
                continue
            }

            let beforeIsBoundary:
                Bool

            if index == 0 {

                beforeIsBoundary =
                    true

            } else {

                beforeIsBoundary =
                    !characters[index - 1].isLetter
                    &&
                    !characters[index - 1].isNumber
            }

            let afterIndex =
                index + 2

            let afterIsBoundary:
                Bool

            if afterIndex >=
                characters.count {

                afterIsBoundary =
                    true

            } else {

                afterIsBoundary =
                    !characters[afterIndex].isLetter
                    &&
                    !characters[afterIndex].isNumber
            }

            if
                beforeIsBoundary
                &&
                afterIsBoundary {

                return true
            }
        }

        return false
    }

    // =============================================================
    // MARK: - Sample Rate
    // =============================================================

    static func sampleRateText(
        _ sampleRate: Int?
    ) -> String {

        guard
            let sampleRate
        else {
            return ""
        }

        if sampleRate % 1000 == 0 {

            return
                "\(sampleRate / 1000)k"
        }

        let value =
            Double(sampleRate)
            /
            1000.0

        return
            String(
                format:
                    "%.1fk",
                value
            )
    }

    // =============================================================
    // MARK: - HTML Escape
    // =============================================================

    static func escapeHTML(
        _ string: String
    ) -> String {

        string
            .replacingOccurrences(
                of: "&",
                with: "&amp;"
            )
            .replacingOccurrences(
                of: "<",
                with: "&lt;"
            )
            .replacingOccurrences(
                of: ">",
                with: "&gt;"
            )
            .replacingOccurrences(
                of: "\"",
                with: "&quot;"
            )
            .replacingOccurrences(
                of: "'",
                with: "&#39;"
            )
    }
}
