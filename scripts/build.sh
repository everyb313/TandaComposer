#!/bin/bash
set -e

# --------------------------------------------------------------------
# TandaComposer — ad-hoc release build + zip for distribution
# --------------------------------------------------------------------
# No paid Apple Developer ID needed. Builds Release for arm64 only
# (Apple Silicon, M1+ — no Intel support), signs ad-hoc (enough for
# Gatekeeper to run it, not enough to skip the warning), and zips it
# with ditto so the app bundle survives transfer intact.
#
# Requirements for recipients: macOS Sequoia (15) or later, Apple
# Silicon Mac (M1 or later).
#
# Usage:
#   ./build.sh
#
# Output:
#   build/Build/Products/Release/<APP_NAME>.app
#   build/<APP_NAME>.zip   <- this is the file to share
# --------------------------------------------------------------------

APP_NAME="TandaComposer"          # change here if you rename the target
SCHEME="TandaComposer"
PROJECT="TandaComposer.xcodeproj"
CONFIGURATION="Release"
BUILD_DIR="build"

# Always run from the project root, regardless of where this script was
# invoked from (e.g. "./scripts/build.sh" or "cd scripts && ./build.sh"
# both work — everything below assumes the project root as CWD).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

echo "==> Building ${APP_NAME} (${CONFIGURATION})…"

xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${BUILD_DIR}" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH="${BUILD_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "!! Build succeeded but ${APP_PATH} not found — check APP_NAME/SCHEME match your Xcode target."
    exit 1
fi

echo "==> Built: ${APP_PATH}"

# Ad-hoc sign explicitly (belt-and-braces — xcodebuild's CODE_SIGN_IDENTITY="-"
# above already does this during build, this re-signs the final bundle
# in case any embedded frameworks were left unsigned).
echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "${APP_PATH}"

# Stage the app together with the install guides and the unlock
# script, so recipients get everything in one download instead of
# hunting for separate files.
DIST_DIR="${BUILD_DIR}/dist"
INSTALL_GUIDES=("install_de.html" "install_en.html")   # expected next to this script
UNLOCK_SCRIPT="TandaComposer_freischalten.command"      # expected next to this script

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
cp -R "${APP_PATH}" "${DIST_DIR}/"

for guide in "${INSTALL_GUIDES[@]}"; do
    if [ -f "${guide}" ]; then
        cp "${guide}" "${DIST_DIR}/"
    else
        echo "!! ${guide} not found next to build.sh — zipping without it."
    fi
done

if [ -f "${UNLOCK_SCRIPT}" ]; then
    cp "${UNLOCK_SCRIPT}" "${DIST_DIR}/"
    chmod +x "${DIST_DIR}/${UNLOCK_SCRIPT}"
else
    echo "!! ${UNLOCK_SCRIPT} not found next to build.sh — zipping without it."
fi

# Zip with ditto (preserves the .app bundle structure/resource forks —
# a plain 'zip' or Finder "Compress" can silently corrupt the bundle).
ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"

echo "==> Zipping…"
ditto -c -k "${DIST_DIR}" "${ZIP_PATH}"

echo ""
echo "Done."
echo "  App:  ${APP_PATH}"
echo "  Zip:  ${ZIP_PATH}   <- share this one (app + install guide)"
echo ""
echo "Reminder for recipients: run TandaComposer_freischalten.command once"
echo "before first launch (see install_de.html / install_en.html) — macOS"
echo "Sequoia and later no longer support the old right-click bypass."
