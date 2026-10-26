#!/bin/bash
#
# Testabdeckung kontrollieren: TandaCoreTests und AudioTagKitTests.
#
#   ./coverage.sh              beide Schemes
#   ./coverage.sh core         nur TandaCoreTests
#   ./coverage.sh kit          nur AudioTagKitTests
#   ./coverage.sh both 95      beide, Schwelle 95 % (Standard 100)
#
# Im Projektordner ausfuehren (dort, wo TandaComposer.xcodeproj liegt).
# Ergebnis im Terminal und in ./coverage_report/:
#   <name>.files.txt       alle Dateien, aufsteigend nach Abdeckung
#   <name>.functions.txt   Funktionen unter 100 % der Dateien unter der Schwelle
#   <name>.testlog.txt     Ausgabe von xcodebuild
#
# Mit EXCLUDE_CORE / EXCLUDE_KIT (Regex auf den Dateinamen, siehe unten) lassen
# sich Dateien aus der Summe nehmen, die man nicht testen will (Oberflaeche,
# Audio-Hardware). Sie werden weiter aufgelistet, aber markiert.

set -u

MODE="${1:-both}"
THRESHOLD="${2:-100}"

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
PROJECT="${PROJECT:-$(ls -d "$PROJECT_DIR"/*.xcodeproj 2>/dev/null | head -1)}"
DESTINATION="${DESTINATION:-platform=macOS}"
OUT="${OUT:-$PROJECT_DIR/coverage_report}"

CORE_SCHEME="TandaCoreTests"
CORE_PATH_RE='/TandaCore/'
KIT_SCHEME="AudioTagKitTests"
KIT_PATH_RE='/AudioTagKit/'

# Nicht sinnvoll testbar: Oberflaeche, Audio-Hardware, M4A-Schreiber.
EXCLUDE_CORE="${EXCLUDE_CORE:-PreviewPlayer|AudioOutputDevice|SettingsView|CleanUpMissingLinksView|SongTransferable}"
EXCLUDE_KIT="${EXCLUDE_KIT:-MP4TagWriter}"

if [ -z "$PROJECT" ] || [ ! -d "$PROJECT" ]; then
    echo "Kein .xcodeproj in $PROJECT_DIR gefunden. Im Projektordner ausfuehren oder PROJECT=... setzen."
    exit 2
fi

mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# Eine Zeile pro Quelldatei: "<prozent> <abgedeckt> <gesamt> <voller Pfad>"
# Liest die Ausgabe von `xccov view --report` auf stdin.
# ---------------------------------------------------------------------------
parse_report() {
    local path_re="$1"

    grep -E "$path_re" \
        | grep -v '/Tests/' \
        | grep -E '\.swift' \
        | awk '
            {
                path = $1
                pct = $2
                counts = $3
                sub("%", "", pct)
                gsub(/[()]/, "", counts)
                split(counts, n, "/")
                printf "%s %s %s %s\n", pct, n[1], n[2], path
            }' \
        | sort -n
}

# ---------------------------------------------------------------------------
# Tabelle und Summe aus der geparsten Liste.
#   $1 Name, $2 Datei mit geparsten Zeilen, $3 Ausschluss-Regex, $4 Schwelle
# ---------------------------------------------------------------------------
print_summary() {
    local name="$1" parsed="$2" exclude="$3" threshold="$4"

    echo
    echo "================ $name: Dateien unter ${threshold} % ================"

    awk -v threshold="$threshold" -v exclude="$exclude" '
        {
            pct = $1 + 0
            n = split($4, parts, "/")
            file = parts[n]
            excluded = (exclude != "" && file ~ exclude)

            if (pct < threshold) {
                printf "%7.2f%%  %5d/%-5d  %s%s\n", pct, $2, $3, file, (excluded ? "   (nicht gezaehlt)" : "")
            }
        }' "$parsed"

    awk -v exclude="$exclude" '
        {
            n = split($4, parts, "/")
            file = parts[n]
            all_cov += $2
            all_tot += $3

            if (exclude != "" && file ~ exclude) {
                skipped++
                next
            }

            cov += $2
            tot += $3
            files++
        }
        END {
            printf "\n%s: %d Dateien gezaehlt, %d ausgenommen\n", "'"$name"'", files, skipped
            if (tot > 0)   printf "  gezaehlt:   %d/%d Zeilen = %.2f %%\n", cov, tot, 100 * cov / tot
            if (all_tot > 0) printf "  mit allem:  %d/%d Zeilen = %.2f %%\n", all_cov, all_tot, 100 * all_cov / all_tot
        }' "$parsed"
}

# ---------------------------------------------------------------------------
# Funktionen unter 100 % fuer Dateien unter der Schwelle.
# ---------------------------------------------------------------------------
write_functions() {
    local name="$1" parsed="$2" bundle="$3" exclude="$4" threshold="$5"
    local target="$OUT/$name.functions.txt"

    : > "$target"

    while read -r pct covered total path; do

        local file
        file="$(basename "$path")"

        if [ -n "$exclude" ] && echo "$file" | grep -Eq "$exclude"; then
            continue
        fi

        if [ "$(echo "$pct < $threshold" | bc -l)" != "1" ]; then
            continue
        fi

        {
            echo "=== $file  (${pct} %)"
            xcrun xccov view --report --functions-for-file "$path" "$bundle" 2>/dev/null \
                | grep -v '100.00%' \
                | grep -vE '^(/|ID |-- )' \
                | grep -v '^\s*$'
            echo
        } >> "$target"

    done < "$parsed"

    echo "Funktionen unter 100 %: $target"
}

# ---------------------------------------------------------------------------
# Ein Scheme: testen, Ergebnis auswerten.
# ---------------------------------------------------------------------------
run_scheme() {
    local name="$1" scheme="$2" path_re="$3" exclude="$4"
    local bundle="$OUT/$name.xcresult"
    local log="$OUT/$name.testlog.txt"
    local parsed="$OUT/$name.files.txt"

    echo
    echo "################ $scheme ################"
    echo "Tests laufen (kann ein bis zwei Minuten dauern) ..."

    rm -rf "$bundle"

    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$scheme" \
        -destination "$DESTINATION" \
        -enableCodeCoverage YES \
        -resultBundlePath "$bundle" \
        > "$log" 2>&1
    local status=$?

    if grep -q '\*\* TEST SUCCEEDED \*\*' "$log"; then
        echo "Ergebnis: TEST SUCCEEDED"
    else
        echo "Ergebnis: TEST FAILED (xcodebuild Status $status)"
        echo "Fehlgeschlagene Tests:"
        grep -E "Test Case .* failed|error: " "$log" | sed -E "s/^.*Test Case '(.*)' failed.*/  \1/" | sort -u | head -40
    fi

    local executed
    executed="$(grep -E "Executed [0-9]+ tests" "$log" | tail -1 | sed 's/^ *//')"
    [ -n "$executed" ] && echo "$executed"

    if [ ! -d "$bundle" ]; then
        echo "Kein Ergebnis-Bundle, Abdeckung nicht verfuegbar. Log: $log"
        return 1
    fi

    xcrun xccov view --report "$bundle" | parse_report "$path_re" > "$parsed"

    if [ ! -s "$parsed" ]; then
        echo "Keine Abdeckungsdaten fuer $path_re gefunden. Log: $log"
        return 1
    fi

    print_summary "$name" "$parsed" "$exclude" "$THRESHOLD"
    write_functions "$name" "$parsed" "$bundle" "$exclude" "$THRESHOLD"

    return $status
}

# ---------------------------------------------------------------------------

overall=0

case "$MODE" in
    core) run_scheme "core" "$CORE_SCHEME" "$CORE_PATH_RE" "$EXCLUDE_CORE" || overall=1 ;;
    kit)  run_scheme "kit"  "$KIT_SCHEME"  "$KIT_PATH_RE"  "$EXCLUDE_KIT"  || overall=1 ;;
    both)
        run_scheme "core" "$CORE_SCHEME" "$CORE_PATH_RE" "$EXCLUDE_CORE" || overall=1
        run_scheme "kit"  "$KIT_SCHEME"  "$KIT_PATH_RE"  "$EXCLUDE_KIT"  || overall=1
        ;;
    *)
        echo "Aufruf: $0 [core|kit|both] [Schwelle in Prozent]"
        exit 2
        ;;
esac

echo
echo "Berichte: $OUT"
exit $overall
