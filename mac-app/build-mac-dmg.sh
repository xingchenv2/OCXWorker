#!/bin/bash
# ──────────────────────────────────────────────────────────────
# macOS OCX — Build Script
#
# Creates a self-contained .app bundle with bundled JRE 21.
# Run on macOS. PKG file for JRE must be pre-installed or use --with-jre.
#
# Usage:
#   ./build-mac-dmg.sh [--with-jre] [--skip-dmg] /path/to/ocx-worker.jar
#
# Brand: macOS OCX v2.0.x (desktop)
# Based on: OCX Worker (server JAR)
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="macOS OCX"
APP_VERSION="2.0.1"
BUNDLE_ID="com.ocx.worker"
SERVER_PORT=8818

# Defaults
WITH_JRE=false
SKIP_DMG=false
JAR_PATH=""

# ── Parse args ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-jre) WITH_JRE=true; shift ;;
        --skip-dmg) SKIP_DMG=true; shift ;;
        --*) echo "Unknown option: $1"; exit 1 ;;
        *) JAR_PATH="$1"; shift ;;
    esac
done

if [ -z "$JAR_PATH" ] || [ ! -f "$JAR_PATH" ]; then
    echo "Usage: $0 [--with-jre] [--skip-dmg] /path/to/ocx-worker.jar"
    exit 1
fi

JAR_PATH="$(cd "$(dirname "$JAR_PATH")" && pwd)/$(basename "$JAR_PATH")"
OUTPUT_DIR="$(pwd)/build-macos-ocx"
APP_DIR="${OUTPUT_DIR}/${APP_NAME}.app"

echo "═══════════════════════════════════════════"
echo "  $APP_NAME v$APP_VERSION — Build"
echo "═══════════════════════════════════════════"
echo "  JAR:   $JAR_PATH"
echo "  JRE:   $WITH_JRE"
echo "  DMG:   $(! $SKIP_DMG && echo yes || echo skip)"
echo ""

# ── Clean previous build ──────────────────────────────────────
rm -rf "$OUTPUT_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources/app"
mkdir -p "${APP_DIR}/Contents/Resources/data/keys"
mkdir -p "${APP_DIR}/Contents/Resources/data/logs"
mkdir -p "${APP_DIR}/Contents/Resources/data/backups"
mkdir -p "${APP_DIR}/Contents/Resources/compat-bin"

# ── 1. Copy main JAR ─────────────────────────────────────────
echo "📦 Copying application JAR..."
cp "$JAR_PATH" "${APP_DIR}/Contents/Resources/app/ocx-worker.jar"

# ── 2. Copy SQLite JDBC driver ────────────────────────────────
SQLITE_JDBC_VER="3.45.1.0"
SQLITE_JDBC_URL="https://github.com/xerial/sqlite-jdbc/releases/download/${SQLITE_JDBC_VER}/sqlite-jdbc-${SQLITE_JDBC_VER}.jar"
SQLITE_JDBC_DST="${APP_DIR}/Contents/Resources/app/sqlite-jdbc-${SQLITE_JDBC_VER}.jar"

if [ -f "${SCRIPT_DIR}/cache/sqlite-jdbc-${SQLITE_JDBC_VER}.jar" ]; then
    echo "📦 Using cached SQLite JDBC..."
    cp "${SCRIPT_DIR}/cache/sqlite-jdbc-${SQLITE_JDBC_VER}.jar" "$SQLITE_JDBC_DST"
else
    echo "⬇️  Downloading SQLite JDBC ${SQLITE_JDBC_VER}..."
    mkdir -p "${SCRIPT_DIR}/cache"
    curl -fSL -o "${SCRIPT_DIR}/cache/sqlite-jdbc-${SQLITE_JDBC_VER}.jar" "$SQLITE_JDBC_URL"
    cp "${SCRIPT_DIR}/cache/sqlite-jdbc-${SQLITE_JDBC_VER}.jar" "$SQLITE_JDBC_DST"
fi

# ── 3. Copy SQLite schema ─────────────────────────────────────
echo "📦 Copying schema..."
cp "${SCRIPT_DIR}/schema-sqlite.sql" "${APP_DIR}/Contents/Resources/app/"

# ── 4. Copy launcher ─────────────────────────────────────────
echo "📦 Copying launcher script..."
cp "${SCRIPT_DIR}/launch.sh" "${APP_DIR}/Contents/MacOS/launch.sh"
chmod +x "${APP_DIR}/Contents/MacOS/launch.sh"

# ── 5. Copy compat-bin ────────────────────────────────────────
echo "📦 Copying compat scripts..."
cp "${SCRIPT_DIR}/compat-bin/"* "${APP_DIR}/Contents/Resources/compat-bin/"
chmod +x "${APP_DIR}/Contents/Resources/compat-bin/"*

# ── 6. Copy LaunchDaemon plist ─────────────────────────────────
cp "${SCRIPT_DIR}/com.ocx.worker.plist" "${APP_DIR}/Contents/Resources/"

# ── 7. Info.plist ─────────────────────────────────────────────
echo "📝 Writing Info.plist..."
cat > "${APP_DIR}/Contents/Info.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>launch.sh</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 OCX. All rights reserved.</string>
</dict>
</plist>
PLISTEOF

# ── 8. Bundle JRE (optional) ──────────────────────────────────
if $WITH_JRE; then
    ARCH="$(uname -m)"
    echo "📦 Bundling JRE 21 for $ARCH..."
    RUNTIME_DIR="${APP_DIR}/Contents/Resources/runtime-${ARCH}"

    # Check for system JRE
    JAVA_HOME_JRE="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
    if [ -n "$JAVA_HOME_JRE" ]; then
        echo "   Using system JRE: $JAVA_HOME_JRE"
        cp -R "$JAVA_HOME_JRE" "${RUNTIME_DIR}/Home"
    else
        echo "❌ No JRE 21 found. Install with: brew install openjdk@21"
        echo "   Or download Azul Zulu JRE: https://www.azul.com/downloads/"
        exit 1
    fi
fi

# ── 9. Secure permissions ─────────────────────────────────────
chmod 700 "${APP_DIR}/Contents/Resources/data" 2>/dev/null || true
chmod 700 "${APP_DIR}/Contents/Resources/data/keys" 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "✅ ${APP_NAME} v${APP_VERSION} built successfully!"
echo "   Location: ${APP_DIR}"
echo "   Size:    $(du -sh "$APP_DIR" | cut -f1)"
echo ""
echo "   Usage: Open ${APP_NAME}.app"
echo "   URL:   http://localhost:${SERVER_PORT}"

# ── 10. Create DMG (optional) ─────────────────────────────────
if ! $SKIP_DMG; then
    DMG_NAME="macOS-OCX-${APP_VERSION}.dmg"
    DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

    echo ""
    echo "📀 Creating DMG: ${DMG_NAME}..."
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${OUTPUT_DIR}" \
        -ov -format UDZO \
        "$DMG_PATH"

    echo "✅ DMG created: ${DMG_PATH}"
    echo "   Size: $(du -sh "$DMG_PATH" | cut -f1)"
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  Build complete!"
echo "═══════════════════════════════════════════"
