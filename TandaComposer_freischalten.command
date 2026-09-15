#!/bin/bash
# ------------------------------------------------------------------
# TandaComposer — Erststart-Freischalter / First-Run Unlocker
# ------------------------------------------------------------------
# DE: Doppelklick auf dieses Skript, BEVOR du TandaComposer zum
#     ersten Mal startest. Entfernt macOS' Quarantäne-Markierung,
#     sodass die App danach ganz normal per Doppelklick öffnet —
#     ohne den Umweg über die Systemeinstellungen.
#
# EN: Double-click this script BEFORE launching TandaComposer for
#     the first time. Removes macOS' quarantine flag so the app
#     opens normally afterward with a regular double-click — no
#     detour through System Settings needed.
#
# Beim ersten Doppelklick auf DIESES Skript kann macOS einmalig
# fragen, ob du sicher bist ("Bist du sicher, dass du es öffnen
# möchtest?") — das ist eine einzelne, einfache Bestätigung, nicht
# die volle Gatekeeper-Blockade wie bei der App selbst. Einfach
# "Öffnen" bestätigen.
# ------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${SCRIPT_DIR}/TandaComposer.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "!! TandaComposer.app wurde nicht neben diesem Skript gefunden."
    echo "!! TandaComposer.app was not found next to this script."
    echo ""
    echo "   Bitte sicherstellen, dass beide im selben Ordner liegen."
    echo "   Please make sure both are in the same folder."
    echo ""
    read -p "Enter zum Schließen / Enter to close… "
    exit 1
fi

echo "Entsperre TandaComposer.app …"
echo "Unlocking TandaComposer.app …"

xattr -cr "${APP_PATH}"

echo ""
echo "✓ Fertig — TandaComposer.app lässt sich jetzt normal per Doppelklick öffnen."
echo "✓ Done — TandaComposer.app can now be opened normally with a double-click."
echo ""
read -p "Enter zum Schließen / Enter to close… "
