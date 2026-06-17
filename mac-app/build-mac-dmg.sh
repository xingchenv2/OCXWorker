#!/bin/bash
# ──────────────────────────────────────────────────────────────
# build-mac-dmg.sh — Build OCX Worker Self-Contained macOS App
#
# Everything inside the app bundle:
#   - JAR + SQLite JDBC driver
#   - SQLite schema
#   - Data directory (DB, keys, logs, backups)
#   - compat-bin (Linux command shims)
#   - JRE 21 (optional, if --with-jre specified)
#
# Prerequisites (on a Mac):
#   - Xcode CLI Tools: xcode-select --install
#   - JDK 21+: brew install openjdk@21
#   - jpackage (bundled with JDK 21+)
#
# Usage:
#   ./build-mac-dmg.sh [options] [path/to/ocx-worker.jar]
#
# Options:
#   --with-jre       Bundle a JRE 21 into the app (no system Java needed)
#   --skip-dmg       Skip .dmg creation, only produce .app
#
# Output:
#   dist/OCX Worker.app
#   dist/ocx-worker-2.0.1.dmg  (unless --skip-dmg)
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
DIST_DIR="${SCRIPT_DIR}/dist"

APP_NAME="OCX Worker"
APP_VERSION="2.0.1"
VENDOR="OCX"
MAIN_JAR="ocx-worker.jar"
BUNDLE_ID="com.ocx.worker"

WITH_JRE=false
SKIP_DMG=false
INPUT_JAR=""

# ── Parse arguments ───────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --with-jre) WITH_JRE=true; shift ;;
        --skip-dmg) SKIP_DMG=true; shift ;;
        *) INPUT_JAR="$1"; shift ;;
    esac
done

if [ -z "$INPUT_JAR" ]; then
    INPUT_JAR="${SCRIPT_DIR}/../ocx-worker-${APP_VERSION}.jar"
fi
if [ ! -f "$INPUT_JAR" ]; then
    echo "❌ JAR not found: $INPUT_JAR"
    echo "   Usage: $0 [--with-jre] [--skip-dmg] /path/to/ocx-worker.jar"
    exit 1
fi

echo "📦 Building ${APP_NAME} v${APP_VERSION} (Self-Contained macOS)"
echo "   Input JAR: $(basename "$INPUT_JAR") ($(du -h "$INPUT_JAR" | cut -f1))"
echo "   Bundle JRE: $WITH_JRE"

# ── Clean previous build ──────────────────────────────────────
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# ── Download SQLite JDBC driver ───────────────────────────────
SQLITE_JDBC_VERSION="3.45.1.0"
SQLITE_JDBC_JAR="sqlite-jdbc-${SQLITE_JDBC_VERSION}.jar"
SQLITE_JDBC_URL="https://github.com/xerial/sqlite-jdbc/releases/download/${SQLITE_JDBC_VERSION}/${SQLITE_JDBC_JAR}"

if [ ! -f "${SCRIPT_DIR}/cache/${SQLITE_JDBC_JAR}" ]; then
    echo "⬇️  Downloading SQLite JDBC ${SQLITE_JDBC_VERSION}..."
    mkdir -p "${SCRIPT_DIR}/cache"
    curl -fSL -o "${SCRIPT_DIR}/cache/${SQLITE_JDBC_JAR}" "$SQLITE_JDBC_URL"
fi

# ── Prepare jpackage input directory ──────────────────────────
INPUT_DIR="${BUILD_DIR}/input"
mkdir -p "$INPUT_DIR"

# Copy main JAR
cp "$INPUT_JAR" "${INPUT_DIR}/${MAIN_JAR}"

# Copy SQLite JDBC into the same input dir
cp "${SCRIPT_DIR}/cache/${SQLITE_JDBC_JAR}" "${INPUT_DIR}/"

# Copy SQLite schema into input dir (will be packaged alongside JAR)
cp "${SCRIPT_DIR}/schema-sqlite.sql" "${INPUT_DIR}/"

# ── Prepare resources directory ────────────────────────────────
RES_DIR="${BUILD_DIR}/resources"
mkdir -p "${RES_DIR}/compat-bin" "${RES_DIR}/data/keys" "${RES_DIR}/data/logs" "${RES_DIR}/data/backups"

# Copy compat-bin scripts
cp "${SCRIPT_DIR}/compat-bin/"* "${RES_DIR}/compat-bin/"
chmod +x "${RES_DIR}/compat-bin/"*

# Copy launch script
cp "${SCRIPT_DIR}/launch.sh" "${RES_DIR}/launch.sh"
chmod +x "${RES_DIR}/launch.sh"

# Copy LaunchAgent plist
cp "${SCRIPT_DIR}/com.ocx.worker.plist" "${RES_DIR}/com.ocx.worker.plist"

# Copy SQLite schema to resources too (for standalone sqlite3 init)
cp "${SCRIPT_DIR}/schema-sqlite.sql" "${RES_DIR}/app/"

# ── Create icon ────────────────────────────────────────────────
ICON_PATH="${SCRIPT_DIR}/ocx-worker.icns"
if [ ! -f "$ICON_PATH" ]; then
    ICON_PATH=""
fi

# ── Build with jpackage ───────────────────────────────────────
echo "🔧 Running jpackage..."

JPACKAGE_ARGS=(
    --name "OCX Worker"
    --input "$INPUT_DIR"
    --main-jar "$MAIN_JAR"
    --main-class com.ociworker.OciWorkerApplication
    --type app-image
    --app-version "$APP_VERSION"
    --vendor "$VENDOR"
    --identifier "$BUNDLE_ID"
    --dest "$DIST_DIR"

    # Add SQLite JDBC to module path / classpath
    --module-path "${INPUT_DIR}/${SQLITE_JDBC_JAR}"
    --add-modules org.sqlite.jdbc

    # JVM options
    --java-options "--add-opens=java.base/java.lang=ALL-UNNAMED"
    --java-options "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED"
    --java-options "-Xms256m"
    --java-options "-Xmx512m"

    # macOS specific
    --mac-package-identifier "$BUNDLE_ID"
    --mac-package-name "OCX Worker"

    # Resource directory
    --resource-dir "$RES_DIR"
)

if [ -n "$ICON_PATH" ]; then
    JPACKAGE_ARGS+=(--icon "$ICON_PATH")
fi

# ── JRE bundling (optional) ───────────────────────────────────
if [ "$WITH_JRE" = true ]; then
    # jpackage auto-bundles the running JRE if --runtime-image is specified
    JRE_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
    if [ -d "$JRE_HOME" ]; then
        JPACKAGE_ARGS+=(--runtime-image "$JRE_HOME")
        echo "   JRE: $JRE_HOME"
    else
        echo "⚠️  JAVA_HOME not found, skipping JRE bundle"
    fi
fi

jpackage "${JPACKAGE_ARGS[@]}"

# ── Post-process the .app bundle ──────────────────────────────
APP_BUNDLE="${DIST_DIR}/OCX Worker.app"
echo "🚀 Post-processing app bundle..."

# Replace default launcher with our custom one
cp "${SCRIPT_DIR}/launch.sh" "${APP_BUNDLE}/Contents/MacOS/launch.sh"
chmod +x "${APP_BUNDLE}/Contents/MacOS/launch.sh"

# Inject compat-bin into Resources
mkdir -p "${APP_BUNDLE}/Contents/Resources/compat-bin"
cp "${SCRIPT_DIR}/compat-bin/"* "${APP_BUNDLE}/Contents/Resources/compat-bin/"
chmod +x "${APP_BUNDLE}/Contents/Resources/compat-bin/"*

# Create self-contained data directories inside app
mkdir -p "${APP_BUNDLE}/Contents/Resources/data/keys"
mkdir -p "${APP_BUNDLE}/Contents/Resources/data/logs"
mkdir -p "${APP_BUNDLE}/Contents/Resources/data/backups"

# Copy schema for external sqlite3 init fallback
cp "${SCRIPT_DIR}/schema-sqlite.sql" "${APP_BUNDLE}/Contents/Resources/app/"

# Copy LaunchAgent plist
cp "${SCRIPT_DIR}/com.ocx.worker.plist" "${APP_BUNDLE}/Contents/Resources/"

# Set secure permissions on data dirs
chmod 700 "${APP_BUNDLE}/Contents/Resources/data"
chmod 700 "${APP_BUNDLE}/Contents/Resources/data/keys"

# ── Create .dmg ────────────────────────────────────────────────
if [ "$SKIP_DMG" = false ]; then
    echo "💿 Creating DMG..."
    DMG_NAME="ocx-worker-${APP_VERSION}.dmg"
    DMG_PATH="${DIST_DIR}/${DMG_NAME}"

    DMG_STAGING="${BUILD_DIR}/dmg-staging"
    mkdir -p "$DMG_STAGING"
    cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
    ln -s /Applications "${DMG_STAGING}/Applications"

    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        "$DMG_PATH" 2>/dev/null || {
        echo "⚠️  hdiutil failed (non-Mac?). Creating zip instead."
        cd "$DIST_DIR"
        zip -r -q "ocx-worker-${APP_VERSION}-macos.zip" "OCX Worker.app"
        echo "✅ Created: ocx-worker-${APP_VERSION}-macos.zip"
        exit 0
    }
fi

echo ""
echo "✅ Build complete!"
echo "   App:  ${APP_BUNDLE}"
echo ""
echo "📋 Self-contained structure:"
echo "   OCX Worker.app/Contents/Resources/"
echo "     app/ocx-worker.jar        ← Application"
echo "     app/schema-sqlite.sql      ← DB schema"
echo "     data/ocx-worker.db         ← SQLite database (created on first run)"
echo "     data/keys/                 ← SSH keys"
echo "     data/logs/                 ← Application logs"
echo "     data/backups/              ← Auto-backups"
echo "     compat-bin/               ← macOS Linux shim scripts"
echo ""
echo "📋 To install:"
echo "   1. Copy OCX Worker.app to /Applications"
echo "   2. First launch: Right-click → Open (bypass Gatekeeper)"
echo "   3. Browser opens http://localhost:8818"
echo ""
echo "📋 All data stays inside the app. No external files created."
echo "   To reset: delete OCX Worker.app/Contents/Resources/data/"
