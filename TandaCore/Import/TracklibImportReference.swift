//
//  TracklibImportReference.swift
//
//  Reference data used by the TXT setlist importer.
//

import Foundation

/// Canonical Tracklib name plus alternative spellings that may occur in
/// filenames or TXT setlists.
public struct TracklibImportReferenceEntry: Codable, Equatable {
    public let name: String
    public let aliases: [String]
}

public struct TracklibImportReference: Codable, Equatable {
    public let version: Int
    public let description: String?
    public let orchestras: [TracklibImportReferenceEntry]
    public let singers: [TracklibImportReferenceEntry]

    public init(
        version: Int,
        description: String? = nil,
        orchestras: [TracklibImportReferenceEntry],
        singers: [TracklibImportReferenceEntry]
    ) {
        self.version = version
        self.description = description
        self.orchestras = orchestras
        self.singers = singers
    }
}

/// Loads the bundled reference list once and provides deterministic name
/// recognition for the text-list importer and the library matcher.
///
/// All recognizers are compiled once. Earlier versions compiled one
/// regular expression per alias on every call, which added up to
/// hundreds of thousands of compilations for a long list.
public enum TracklibImportReferenceStore {

    public enum Kind {
        case orchestra
        case singer
    }

    public typealias NameMatch = (
        entry: TracklibImportReferenceEntry,
        range: Range<String.Index>
    )

    private static let loaded: (
        reference: TracklibImportReference,
        problem: String?
    ) = load()

    public static var orchestras: [TracklibImportReferenceEntry] {
        loaded.reference.orchestras
    }

    public static var singers: [TracklibImportReferenceEntry] {
        loaded.reference.singers
    }

    /// Non-nil when the bundled list is missing or cannot be decoded.
    /// Name recognition is then switched off entirely, so callers
    /// should tell the user instead of degrading silently.
    public static var loadProblem: String? {
        loaded.problem
    }

    private static let orchestraRecognizer =
        NameRecognizer(entries: loaded.reference.orchestras)

    private static let singerRecognizer =
        NameRecognizer(entries: loaded.reference.singers)

    /// Canonical orchestra/singer names found in `text`, left to right,
    /// not overlapping. At one position the longest spelling wins.
    ///
    /// Matching ignores case, accents, apostrophe variants and runs of
    /// white space in the alias. Pass precomposed (NFC) text: the
    /// returned ranges refer to the string as given.
    static func matches(
        in text: String,
        kind: Kind
    ) -> [NameMatch] {

        switch kind {
        case .orchestra:
            return orchestraRecognizer.matches(in: text)
        case .singer:
            return singerRecognizer.matches(in: text)
        }
    }

    private static func load() -> (
        reference: TracklibImportReference,
        problem: String?
    ) {

        func fallback(_ why: String) -> (
            reference: TracklibImportReference,
            problem: String?
        ) {
            print("TracklibImportReference: \(why)")

            return (
                TracklibImportReference(
                    version: 1,
                    description: "Built-in fallback: \(why)",
                    orchestras: [],
                    singers: []
                ),
                why
            )
        }

        guard let url = Bundle.main.url(
            forResource: "tracklib_import_reference",
            withExtension: "json"
        ) else {
            return fallback(
                "tracklib_import_reference.json is not in the app bundle."
            )
        }

        do {
            let data = try Data(contentsOf: url)

            return (
                try JSONDecoder().decode(
                    TracklibImportReference.self,
                    from: data
                ),
                nil
            )
        } catch {
            return fallback(
                "tracklib_import_reference.json cannot be read: \(error.localizedDescription)"
            )
        }
    }
}


// MARK: - Recognizer

/// One compiled alternation of every spelling of one kind of name.
private struct NameRecognizer {

    private let regex: NSRegularExpression?
    private let entryByFoldedName: [String: TracklibImportReferenceEntry]

    init(entries: [TracklibImportReferenceEntry]) {

        var table: [String: TracklibImportReferenceEntry] = [:]
        var spellings = Set<String>()

        for entry in entries {

            let foldedCanonical = foldReferenceName(entry.name)

            for alias in [entry.name] + entry.aliases {

                let precomposed =
                    alias.precomposedStringWithCanonicalMapping

                let folded = foldReferenceName(precomposed)

                guard !folded.isEmpty else {
                    continue
                }

                // The original spelling and the accent-free one, so
                // text with and without accents is found either way.
                spellings.insert(precomposed)
                spellings.insert(folded)

                if let existing = table[folded] {

                    // A spelling listed under two entries (a full name
                    // that appears in both): prefer the entry whose own
                    // name is part of it.
                    let existingName = foldReferenceName(existing.name)

                    if folded.contains(foldedCanonical),
                       !folded.contains(existingName) {
                        table[folded] = entry
                    }

                } else {
                    table[folded] = entry
                }
            }
        }

        entryByFoldedName = table

        guard !spellings.isEmpty else {
            regex = nil
            return
        }

        // Longest spelling first: at one position the regex engine
        // takes the first alternative that fits.
        let alternatives = spellings
            .sorted {
                $0.count != $1.count
                    ? $0.count > $1.count
                    : $0 < $1
            }
            .map(Self.patternFragment)
            .joined(separator: "|")

        // Not inside a longer word, e.g. "Biagi" in "Biagini".
        regex = try? NSRegularExpression(
            pattern:
                #"(?<![\p{L}\p{N}])(?:"# + alternatives + #")(?![\p{L}\p{N}])"#,
            options: [.caseInsensitive]
        )
    }

    func matches(
        in text: String
    ) -> [TracklibImportReferenceStore.NameMatch] {

        guard let regex, !text.isEmpty else {
            return []
        }

        var result: [TracklibImportReferenceStore.NameMatch] = []

        let whole = NSRange(text.startIndex..., in: text)

        for match in regex.matches(in: text, options: [], range: whole) {

            guard let range = Range(match.range, in: text),
                  let entry =
                    entryByFoldedName[
                        foldReferenceName(String(text[range]))
                    ]
            else {
                continue
            }

            result.append((entry, range))
        }

        return result
    }

    /// Regex for one literal spelling: metacharacters escaped by hand,
    /// every apostrophe variant interchangeable, white space flexible.
    private static func patternFragment(_ spelling: String) -> String {

        let apostrophes = "'\u{2019}\u{2018}\u{00B4}`"
        let metacharacters = "\\.[]{}()*+?^$|-/"

        var result = ""
        var previousWasSpace = false

        for character in spelling {

            if character.isWhitespace {

                if !previousWasSpace {
                    result += #"\s+"#
                }

                previousWasSpace = true
                continue
            }

            previousWasSpace = false

            if apostrophes.contains(character) {
                result += "['\u{2019}\u{2018}\u{00B4}`]"

            } else if metacharacters.contains(character) {
                result += "\\" + String(character)

            } else {
                result += String(character)
            }
        }

        return result
    }
}

/// Case, accent, apostrophe and dash folding for comparing names.
/// Not locale dependent.
private func foldReferenceName(_ value: String) -> String {

    value
        .precomposedStringWithCanonicalMapping
        .folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        .replacingOccurrences(of: "\u{2019}", with: "'")
        .replacingOccurrences(of: "\u{2018}", with: "'")
        .replacingOccurrences(of: "\u{00B4}", with: "'")
        .replacingOccurrences(of: "`", with: "'")
        .replacingOccurrences(of: "\u{2013}", with: "-")
        .replacingOccurrences(of: "\u{2014}", with: "-")
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}
