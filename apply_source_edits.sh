#!/bin/bash
# Entfernt in TracklibImportReference.swift dreimal "private" (nur Zugriffsebene),
# damit NameRecognizerTests darauf zugreifen kann. Im Projektordner ausfuehren.
set -e
F="TandaCore/Import/TracklibImportReference.swift"
sed -i '' \
  -e 's/nonisolated private struct NameRecognizer/nonisolated struct NameRecognizer/' \
  -e 's/nonisolated private static func patternFragment/nonisolated static func patternFragment/' \
  -e 's/nonisolated private func foldReferenceName/nonisolated func foldReferenceName/' \
  "$F"
grep -n "struct NameRecognizer\|func patternFragment\|func foldReferenceName" "$F"
