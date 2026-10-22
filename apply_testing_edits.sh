#!/bin/bash
# Einmal im Projektordner ausfuehren:  ./apply_testing_edits.sh
# Aendert nur Zugriffsebenen und fuegt einen Test-Eingang ein.
# Verhalten der App bleibt gleich (der Test-Eingang ist ohne Test immer nil).
set -e

F1="TandaCore/Import/TracklibImportReference.swift"
F2="TandaCore/TrackLibrary/SongMetadataReader.swift"

if ! grep -q overrideEntriesForTesting "$F1"; then
  perl -0pi -e 's|(    public static var orchestras: \[TracklibImportReferenceEntry\] \{)|    /// TEST SEAM: when set, name recognition uses these entries instead of\n    /// the bundled list. Only tests set it, and they reset it to nil.\n    nonisolated(unsafe) static var overrideEntriesForTesting: (\n        orchestras: [TracklibImportReferenceEntry],\n        singers: [TracklibImportReferenceEntry]\n    )?\n\n$1|' "$F1"

  perl -0pi -e 's|        switch kind \{\n        case \.orchestra:\n            return orchestraRecognizer\.matches\(in: text\)|        if let injected = overrideEntriesForTesting {\n            let entries = kind == .orchestra ? injected.orchestras : injected.singers\n\n            return NameRecognizer(entries: entries).matches(in: text)\n        }\n\n$&|' "$F1"
fi

sed -i '' \
  -e 's/private static func extractBPM/static func extractBPM/' \
  -e 's/private static func extractSampleRate/static func extractSampleRate/' \
  -e 's/private static func extractReplayGain/static func extractReplayGain/' \
  "$F2"

echo "--- $F1"
grep -n "overrideEntriesForTesting\|injected" "$F1"
echo "--- $F2"
grep -n "static func extract" "$F2"
