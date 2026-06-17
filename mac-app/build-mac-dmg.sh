#!/bin/bash
# ──────────────────────────────────────────────────────────────
# macOS OCX — Build Script
#
# Creates a self-contained .app with:
#   - Native macOS window (Swift WKWebView wrapper)
#   - Bundled JRE 21 (user never installs Java)
#   - SQLite (no MySQL needed)
#   - All data inside app bundle
#
# Run on macOS:
#   ./build-mac-dmg.sh [--with-jre] /path/to/ocx-worker.jar
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="macOS OCX"
APP_VERSION="2.0.1"
BUNDLE_ID="com.ocx.worker"
SERVER_PORT=8818

WITH_JRE=false
JAR_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-jre) WITH_JRE=true; shift ;;
        --*) echo "Unknown option: $1"; exit 1 ;;
        *) JAR_PATH="$1"; shift ;;
    esac
done

if [ -z "$JAR_PATH" ] || [ ! -f "$JAR_PATH" ]; then
    echo "Usage: $0 [--with-jre] /path/to/ocx-worker.jar"
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
echo ""

# ── Clean previous build ──────────────────────────────────────
rm -rf "$OUTPUT_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources/app"
mkdir -p "${APP_DIR}/Contents/Resources/data/keys"
mkdir -p "${APP_DIR}/Contents/Resources/data/logs"
mkdir -p "${APP_DIR}/Contents/Resources/data/backups"
mkdir -p "${APP_DIR}/Contents/Resources/compat-bin"

# ── 1. Compile Swift WebView wrapper → native binary ──────────
echo "🔨 Compiling Swift WebView wrapper..."
SWIFT_SRC="${SCRIPT_DIR}/MacOSOCXWebView.swift"
SWIFT_BIN="${APP_DIR}/Contents/MacOS/MacOSOCX"

swiftc -o "$SWIFT_BIN" \
    "$SWIFT_SRC" \
    -framework Cocoa -framework WebKit \
    -parse-as-library \
    -Osize \
    2>&1

if [ $? -ne 0 ]; then
    echo "❌ Swift compilation failed!"
    exit 1
fi
chmod +x "$SWIFT_BIN"
echo "✅ Swift binary: $(du -h "$SWIFT_BIN" | cut -f1)"

# ── 2. Copy backend launcher script ───────────────────────────
echo "📦 Copying backend launcher..."
cp "${SCRIPT_DIR}/launch-backend.sh" "${APP_DIR}/Contents/MacOS/"
chmod +x "${APP_DIR}/Contents/MacOS/launch-backend.sh"

# ── 3. Copy main JAR ──────────────────────────────────────────
echo "📦 Copying application JAR..."
cp "$JAR_PATH" "${APP_DIR}/Contents/Resources/app/ocx-worker.jar"

# ── 4. Copy SQLite JDBC driver ────────────────────────────────
SQLITE_JDBC_VER="3.45.1.0"
SQLITE_JDBC_URL="https://github.com/xerial/sqlite-jdbc/releases/download/${SQLITE_JDBC_VER}/sqlite-jdbc-${SQLITE_JDBC_VER}.jar"
SQLITE_JDBC_DST="${APP_DIR}/Contents/Resources/app/sqlite-jdbc-${SQLITE_JDBC_VER}.jar"

if [ -f "${SCRIPT_DIR}/cache/sqlite-jdbc-${SQLITE_JDBC_VER}.jar" ]; then
    cp "${SCRIPT_DIR}/cache/sqlite-jdbc-${SQLITE_JDBC_VER}.jar" "$SQLITE_JDBC_DST"
else
    echo "⬇️  Downloading SQLite JDBC..."
    mkdir -p "${SCRIPT_DIR}/cache"
    curl -fSL -o "${SCRIPT_DIR}/cache/sqlite-jdbc-${SQLITE_JDBC_VER}.jar" "$SQLITE_JDBC_URL"
    cp "${SCRIPT_DIR}/cache/sqlite-jdbc-${SQLITE_JDBC_VER}.jar" "$SQLITE_JDBC_DST"
fi

# ── 5. Copy schema & compat ───────────────────────────────────
cp "${SCRIPT_DIR}/schema-sqlite.sql" "${APP_DIR}/Contents/Resources/app/"
cp "${SCRIPT_DIR}/compat-bin/"* "${APP_DIR}/Contents/Resources/compat-bin/"
chmod +x "${APP_DIR}/Contents/Resources/compat-bin/"*
cp "${SCRIPT_DIR}/com.ocx.worker.plist" "${APP_DIR}/Contents/Resources/"

# ── 6. Info.plist ─────────────────────────────────────────────
echo "📝 Writing Info.plist..."
# CFBundleExecutable = MacOSOCX (the Swift binary, not launch.sh)
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
    <string>MacOSOCX</string>
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

# ── 7. Bundle JRE (if --with-jre) ────────────────────────────
if $WITH_JRE; then
    ARCH="$(uname -m)"
    echo "📦 Bundling JRE 21 for $ARCH..."
    RUNTIME_DIR="${APP_DIR}/Contents/Resources/runtime-${ARCH}"

    JAVA_HOME_JRE="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
    if [ -n "$JAVA_HOME_JRE" ]; then
        mkdir -p "$RUNTIME_DIR"
        cp -R "$JAVA_HOME_JRE" "${RUNTIME_DIR}/Home"
    else
        echo "❌ No JRE 21 found! Install: brew install openjdk@21"
        exit 1
    fi
fi

# ── 8. Secure permissions ─────────────────────────────────────
chmod 700 "${APP_DIR}/Contents/Resources/data" 2>/dev/null || true
chmod 700 "${APP_DIR}/Contents/Resources/data/keys" 2>/dev/null || true

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "✅ ${APP_NAME} v${APP_VERSION} built!"
echo "   Location: ${APP_DIR}"
echo "   Size:    $(du -sh "$APP_DIR" | cut -f1)"
echo ""
echo "   双击 ${APP_NAME}.app 即可直接使用"
echo "   无需浏览器，无需安装 Java，无需安装 MySQL"

# ── 9. Create zip (for distribution) ───────────────────────────
ZIP_NAME="macOS-OCX-${APP_VERSION}-mac-$(uname -m).zip"
echo ""
echo "📦 Creating distribution zip..."
cd "$OUTPUT_DIR"
zip -r -q "${SCRIPT_DIR}/${ZIP_NAME}" "${APP_NAME}.app"
echo "✅ Zip: ${SCRIPT_DIR}/${ZIP_NAME} $(du -h "${SCRIPT_DIR}/${ZIP_NAME}" | cut -f1)"

echo ""
echo "═══════════════════════════════════════════"
echo "  Build complete! 🎉"
echo "═══════════════════════════════════════════"
