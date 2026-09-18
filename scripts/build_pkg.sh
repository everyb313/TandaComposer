#!/bin/bash
set -e

# --------------------------------------------------------------------
# TandaComposer — Release build + macOS PKG installer
# --------------------------------------------------------------------
#
# Builds:
#   - Release / arm64
#   - ad-hoc signed application
#   - embeds install_de.html and install_en.html
#   - creates a versioned macOS .pkg installer
#
# Output:
#
#   build/TandaComposer-<VERSION>.pkg
#
# Example:
#
#   build/TandaComposer-1.4.pkg
#
# Installation:
#
#   /Applications/TandaComposer.app
#
# After installation:
#
#   German macOS  -> install_de.html
#   Other macOS   -> install_en.html
#
# Requirements:
#
#   - Xcode command line tools
#   - macOS
#   - Apple Silicon Mac
#
# --------------------------------------------------------------------

APP_NAME="TandaComposer"
SCHEME="TandaComposer"
PROJECT="TandaComposer.xcodeproj"
CONFIGURATION="Release"

BUILD_DIR="build"

INSTALL_LOCATION="/Applications"

INSTALL_GUIDES=(
    "install_de.html"
    "install_en.html"
)

# Always run from the project root, regardless of where this script was
# invoked from (e.g. "./scripts/build_pkg.sh" or "cd scripts &&
# ./build_pkg.sh" both work — everything below assumes the project root
# as CWD).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."


# --------------------------------------------------------------------
# Helper
# --------------------------------------------------------------------

fail()
{
    echo ""
    echo "!! ERROR: $1"
    echo ""
    exit 1
}


# --------------------------------------------------------------------
# Check project
# --------------------------------------------------------------------

echo ""
echo "============================================================"
echo " TandaComposer PKG Build"
echo "============================================================"
echo ""

[ -d "${PROJECT}" ] || fail "${PROJECT} not found."
[ -f "install_de.html" ] || fail "install_de.html not found."
[ -f "install_en.html" ] || fail "install_en.html not found."


# --------------------------------------------------------------------
# Clean build
# --------------------------------------------------------------------

echo "==> Cleaning old build..."

rm -rf "${BUILD_DIR}"

mkdir -p "${BUILD_DIR}"


# --------------------------------------------------------------------
# Build
# --------------------------------------------------------------------

echo ""
echo "==> Building ${APP_NAME} (${CONFIGURATION}, arm64)..."
echo ""

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


[ -d "${APP_PATH}" ] || \
    fail "Build succeeded but ${APP_PATH} was not found."


echo ""
echo "==> Built:"
echo "    ${APP_PATH}"


# --------------------------------------------------------------------
# Read version from the built application
#
# CFBundleShortVersionString = Marketing Version
# CFBundleVersion            = Build Number
# --------------------------------------------------------------------

VERSION=$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleShortVersionString" \
        "${APP_PATH}/Contents/Info.plist"
)

BUILD_NUMBER=$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleVersion" \
        "${APP_PATH}/Contents/Info.plist"
)


[ -n "${VERSION}" ] || fail "Could not determine application version."
[ -n "${BUILD_NUMBER}" ] || fail "Could not determine build number."


echo ""
echo "==> Application version:"
echo "    ${VERSION}"
echo ""
echo "==> Build number:"
echo "    ${BUILD_NUMBER}"


# --------------------------------------------------------------------
# Ad-hoc sign
# --------------------------------------------------------------------

echo ""
echo "==> Ad-hoc signing application..."

codesign \
    --force \
    --deep \
    --sign - \
    "${APP_PATH}"


# --------------------------------------------------------------------
# Copy installation guides into app
# --------------------------------------------------------------------

RESOURCES_DIR="${APP_PATH}/Contents/Resources"

mkdir -p "${RESOURCES_DIR}"

echo ""
echo "==> Copying installation guides..."

for guide in "${INSTALL_GUIDES[@]}"; do

    echo "    + ${guide}"

    cp "${guide}" "${RESOURCES_DIR}/"

done


# --------------------------------------------------------------------
# Re-sign after modifying application bundle
# --------------------------------------------------------------------

echo ""
echo "==> Re-signing application..."

codesign \
    --force \
    --deep \
    --sign - \
    "${APP_PATH}"


# --------------------------------------------------------------------
# Verify application signature
# --------------------------------------------------------------------

echo ""
echo "==> Verifying application..."

codesign \
    --verify \
    --deep \
    --strict \
    "${APP_PATH}"

echo "    Signature OK."


# --------------------------------------------------------------------
# Prepare PKG root
# --------------------------------------------------------------------

PKG_ROOT="${BUILD_DIR}/pkgroot"

rm -rf "${PKG_ROOT}"

mkdir -p "${PKG_ROOT}${INSTALL_LOCATION}"

echo ""
echo "==> Preparing installer payload..."

cp -R \
    "${APP_PATH}" \
    "${PKG_ROOT}${INSTALL_LOCATION}/"


# --------------------------------------------------------------------
# Installer scripts
# --------------------------------------------------------------------

SCRIPTS_DIR="${BUILD_DIR}/scripts"

rm -rf "${SCRIPTS_DIR}"

mkdir -p "${SCRIPTS_DIR}"


# --------------------------------------------------------------------
# postinstall
#
# Opens the appropriate installation guide using the logged-in user.
# --------------------------------------------------------------------

cat > "${SCRIPTS_DIR}/postinstall" <<'EOF'
#!/bin/bash

# --------------------------------------------------------------------
# TandaComposer PKG postinstall
# --------------------------------------------------------------------

APP_PATH="/Applications/TandaComposer.app"

if [ ! -d "${APP_PATH}" ]; then
    exit 0
fi


# ------------------------------------------------------------
# Determine macOS language
# ------------------------------------------------------------

LANGUAGE="${LANG:-}"

case "${LANGUAGE}" in

    de_DE*|de_AT*|de_CH*|de*)

        HELP_FILE="${APP_PATH}/Contents/Resources/install_de.html"

        ;;

    *)

        HELP_FILE="${APP_PATH}/Contents/Resources/install_en.html"

        ;;

esac


# ------------------------------------------------------------
# Fallback if selected language file does not exist
# ------------------------------------------------------------

if [ ! -f "${HELP_FILE}" ]; then

    if [ -f "${APP_PATH}/Contents/Resources/install_de.html" ]; then

        HELP_FILE="${APP_PATH}/Contents/Resources/install_de.html"

    elif [ -f "${APP_PATH}/Contents/Resources/install_en.html" ]; then

        HELP_FILE="${APP_PATH}/Contents/Resources/install_en.html"

    else

        exit 0

    fi

fi


# ------------------------------------------------------------
# Find logged-in console user
# ------------------------------------------------------------

CONSOLE_USER=$(
    /usr/bin/stat -f "%Su" /dev/console
)

if [ -z "${CONSOLE_USER}" ] || [ "${CONSOLE_USER}" = "root" ]; then
    exit 0
fi


CONSOLE_UID=$(
    /usr/bin/id -u "${CONSOLE_USER}"
)


# ------------------------------------------------------------
# Open installation guide as logged-in user
# ------------------------------------------------------------

/bin/launchctl asuser "${CONSOLE_UID}" \
    /usr/bin/open "${HELP_FILE}" \
    >/dev/null 2>&1 || true


exit 0
EOF


chmod +x "${SCRIPTS_DIR}/postinstall"


# --------------------------------------------------------------------
# Create versioned PKG
# --------------------------------------------------------------------

PKG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.pkg"

rm -f "${PKG_PATH}"


echo ""
echo "==> Creating PKG..."
echo ""

pkgbuild \
    --root "${PKG_ROOT}" \
    --identifier "com.tandacomposer.app" \
    --version "${VERSION}" \
    --install-location "/" \
    --scripts "${SCRIPTS_DIR}" \
    "${PKG_PATH}"


[ -f "${PKG_PATH}" ] || \
    fail "PKG was not created."


# --------------------------------------------------------------------
# Verify PKG
# --------------------------------------------------------------------

echo ""
echo "==> Verifying PKG..."

pkgutil --check-signature "${PKG_PATH}" || true


# --------------------------------------------------------------------
# Information
# --------------------------------------------------------------------

PKG_SIZE=$(
    du -h "${PKG_PATH}" | awk '{print $1}'
)


echo ""
echo "============================================================"
echo " Build complete"
echo "============================================================"
echo ""
echo "Application:"
echo "  ${APP_PATH}"
echo ""
echo "Version:"
echo "  ${VERSION}"
echo ""
echo "Build:"
echo "  ${BUILD_NUMBER}"
echo ""
echo "Installer:"
echo "  ${PKG_PATH}"
echo ""
echo "Size:"
echo "  ${PKG_SIZE}"
echo ""
echo "Installation target:"
echo "  ${INSTALL_LOCATION}/${APP_NAME}.app"
echo ""
echo "After installation:"
echo "  install_de.html / install_en.html opens automatically"
echo ""
echo "============================================================"
echo ""
