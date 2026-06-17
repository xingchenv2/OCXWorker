#!/bin/bash
# ──────────────────────────────────────────────────────────────
# macOS OCX — Build Script (AppleScriptObjC Native Window)
#
# Creates a self-contained .app:
#   entry.applescript → native NSWindow + WKWebView
#   launch-backend.sh → Spring Boot backend
#   Bundled JRE 21 + SQLite JDBC
#
# No compilation needed! AppleScript runs natively on every Mac.
#
# Usage (on macOS):
#   ./build-mac-dmg.sh /path/to/ocx-worker.jar
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="macOS OCX"
APP_VERSION="2.0.6"
BUNDLE_ID="com.ocx.worker"
SERVER_PORT=8818

JAR_PATH=""
BUILD_BOTH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --both) BUILD_BOTH=true; shift ;;
        --*) echo "Unknown option: $1"; exit 1 ;;
        *) JAR_PATH="$1"; shift ;;
    esac
done

if [ -z "$JAR_PATH" ] || [ ! -f "$JAR_PATH" ]; then
    echo "Usage: $0 /path/to/ocx-worker.jar"
    exit 1
fi

JAR_PATH="$(cd "$(dirname "$JAR_PATH")" && pwd)/$(basename "$JAR_PATH")"
OUTPUT_DIR="$(pwd)/build-macos-ocx"
APP_DIR="${OUTPUT_DIR}/${APP_NAME}.app"

echo "═══════════════════════════════════════════"
echo "  $APP_NAME v$APP_VERSION — Build"
echo "═══════════════════════════════════════════"
echo "  JAR:    $JAR_PATH"
echo "  Mode:   osacompile native window (auto-compile on first run)"
echo ""

# ── Clean ──────────────────────────────────────────────────────
rm -rf "$OUTPUT_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources/app"
mkdir -p "${APP_DIR}/Contents/Resources/data/keys"
mkdir -p "${APP_DIR}/Contents/Resources/data/logs"
mkdir -p "${APP_DIR}/Contents/Resources/data/backups"
mkdir -p "${APP_DIR}/Contents/Resources/compat-bin"
mkdir -p "${APP_DIR}/Contents/Resources/runtime-arm64"
mkdir -p "${APP_DIR}/Contents/Resources/runtime-x64"

# ── 1. Copy main entry point (MacOSOCX shell wrapper) ────────
echo "📝 Setting up native window entry point..."
cp "${SCRIPT_DIR}/MacOSOCX" "${APP_DIR}/Contents/MacOS/MacOSOCX"
chmod +x "${APP_DIR}/Contents/MacOS/MacOSOCX"

# ── 2. Copy AppleScript native window ──────────────────────────
cp "${SCRIPT_DIR}/entry.applescript" "${APP_DIR}/Contents/MacOS/entry.applescript"
chmod +x "${APP_DIR}/Contents/MacOS/entry.applescript"

# ── 3. Copy JAR ────────────────────────────────────────────────
echo "📦 Copying application JAR..."
cp "$JAR_PATH" "${APP_DIR}/Contents/Resources/app/ocx-worker.jar"

# ── 4. Copy SQLite JDBC driver ─────────────────────────────────
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

# ── 5. Copy schema + compat ────────────────────────────────────
cp "${SCRIPT_DIR}/schema-sqlite.sql" "${APP_DIR}/Contents/Resources/app/"
cp "${SCRIPT_DIR}/compat-bin/"* "${APP_DIR}/Contents/Resources/compat-bin/"
chmod +x "${APP_DIR}/Contents/Resources/compat-bin/"*
cp "${SCRIPT_DIR}/com.ocx.worker.plist" "${APP_DIR}/Contents/Resources/"

# ── 6. Info.plist — CFBundleExecutable = MacOSOCX ─────────────
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

# ── 7. Bundle JRE ──────────────────────────────────────────────
build_arch() {
    local ARCH="$1"  # arm64 or x64
    local RUNTIME_DIR="${APP_DIR}/Contents/Resources/runtime-${ARCH}"
    local CACHE_FILE=""

    # Try macOS java_home first (only works on macOS)
    local JAVA_HOME_JRE="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"

    if [ -n "$JAVA_HOME_JRE" ]; then
        mkdir -p "$RUNTIME_DIR"
        cp -R "$JAVA_HOME_JRE" "${RUNTIME_DIR}/Home"
        echo "✅ JRE ($ARCH) from $JAVA_HOME_JRE"
    else
        # Check multiple cache locations
        for dir in "${SCRIPT_DIR}/cache" "${SCRIPT_DIR}/../cache" "/tmp/mac-prebundle"; do
            if [ -f "${dir}/zulu-jre21-mac-${ARCH}.tar.gz" ]; then
                CACHE_FILE="${dir}/zulu-jre21-mac-${ARCH}.tar.gz"
                break
            fi
        done

        if [ -n "$CACHE_FILE" ]; then
            mkdir -p "$RUNTIME_DIR"
            tar xzf "$CACHE_FILE" -C "$RUNTIME_DIR"
            echo "✅ JRE ($ARCH) from cache"
        else
            echo "⚠️  No JRE for $ARCH. App needs system Java."
        fi
    fi
}

if [ "$BUILD_BOTH" = true ]; then
    echo "📦 Bundling both architectures..."
    build_arch arm64
    build_arch x64
else
    # Map Linux arch names to Apple
    HOST_ARCH="$(uname -m)"
    case "$HOST_ARCH" in
        aarch64) APPLE_ARCH="arm64" ;;
        x86_64)  APPLE_ARCH="x64" ;;
        *)       APPLE_ARCH="$HOST_ARCH" ;;
    esac
    echo "📦 Bundling JRE 21 ($APPLE_ARCH)..."
    build_arch "$APPLE_ARCH"
fi

# ── 8. Secure permissions ──────────────────────────────────────
chmod 700 "${APP_DIR}/Contents/Resources/data" 2>/dev/null || true
chmod 700 "${APP_DIR}/Contents/Resources/data/keys" 2>/dev/null || true

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "✅ ${APP_NAME} v${APP_VERSION} built!"
echo "   Location: ${APP_DIR}"
echo "   Size:    $(du -sh "$APP_DIR" | cut -f1)"
echo ""
echo "   双击 ${APP_NAME}.app 即可使用"
echo "   ✅ 原生窗口（首次运行自动编译，之后直接使用）"
echo "   ✅ 无需浏览器、无需安装 Java"

# ── 9. Zip for distribution ────────────────────────────────────
if [ "$BUILD_BOTH" = true ]; then
    echo ""
    echo "📦 Splitting into architecture-specific zips..."
    for TARGET_ARCH in arm64 x64; do
        SPLIT_DIR="${OUTPUT_DIR}-${TARGET_ARCH}"
        mkdir -p "$SPLIT_DIR"
        cp -R "${APP_DIR}" "${SPLIT_DIR}/${APP_NAME}.app"
        # Remove opposite-arch JRE to save space
        OTHER_ARCH="x64"
        [ "$TARGET_ARCH" = "x64" ] && OTHER_ARCH="arm64"
        rm -rf "${SPLIT_DIR}/${APP_NAME}.app/Contents/Resources/runtime-${OTHER_ARCH}"

        ZIP_NAME="mac-${TARGET_ARCH}-v${APP_VERSION}.zip"
        cd "$SPLIT_DIR"
        zip -r -q "${SCRIPT_DIR}/${ZIP_NAME}" "${APP_NAME}.app"
        echo "✅ $TARGET_ARCH: ${SCRIPT_DIR}/${ZIP_NAME} $(du -h "${SCRIPT_DIR}/${ZIP_NAME}" | cut -f1)"
    done
else
    HOST_ARCH="$(uname -m)"
    case "$HOST_ARCH" in
        aarch64) ARCH_NAME="arm64" ;;
        x86_64)  ARCH_NAME="x64" ;;
        *)       ARCH_NAME="$HOST_ARCH" ;;
    esac
    ZIP_NAME="macOS-OCX-${APP_VERSION}-mac-${ARCH_NAME}.zip"
    echo ""
    echo "📦 Creating distribution zip..."
    cd "$OUTPUT_DIR"
    zip -r -q "${SCRIPT_DIR}/${ZIP_NAME}" "${APP_NAME}.app"
    echo "✅ Zip: ${SCRIPT_DIR}/${ZIP_NAME} $(du -h "${SCRIPT_DIR}/${ZIP_NAME}" | cut -f1)"
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  Build complete! 🎉"
echo "═══════════════════════════════════════════"
