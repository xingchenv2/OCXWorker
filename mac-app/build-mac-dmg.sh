#!/bin/bash
# ──────────────────────────────────────────────────────────────
# build-mac-dmg.sh — Build OCX Worker macOS .app + .dmg
#
# Prerequisites (on a Mac):
#   - Xcode Command Line Tools: xcode-select --install
#   - JRE 21:  brew install openjdk@21
#   - jpackage (bundled with JDK 21+)
#
# Usage:
#   ./build-mac-dmg.sh [path/to/ocx-worker.jar]
#
# Output:
#   ./dist/OCX Worker.app
#   ./dist/ocx-worker-2.0.1.dmg
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
DIST_DIR="${SCRIPT_DIR}/dist"
RESOURCES_DIR="${BUILD_DIR}/resources"

# ── Configuration ──────────────────────────────────────────────
APP_NAME="OCX Worker"
APP_VERSION="2.0.1"
VENDOR="OCX"
MAIN_JAR="ocx-worker.jar"
BUNDLE_ID="com.ocx.worker"

# ── Input JAR ─────────────────────────────────────────────────
INPUT_JAR="${1:-${SCRIPT_DIR}/../ocx-worker-${APP_VERSION}.jar}"
if [ ! -f "$INPUT_JAR" ]; then
    echo "❌ JAR not found: $INPUT_JAR"
    echo "   Usage: $0 [path/to/ocx-worker.jar]"
    exit 1
fi

echo "📦 Building ${APP_NAME} v${APP_VERSION} for macOS"
echo "   Input JAR: $(basename "$INPUT_JAR") ($(du -h "$INPUT_JAR" | cut -f1))"

# ── Clean previous build ──────────────────────────────────────
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR" "$RESOURCES_DIR"

# ── Prepare app resources ─────────────────────────────────────
echo "📁 Preparing resources..."

# Copy JAR into the input directory (jpackage wants a flat dir)
cp "$INPUT_JAR" "${BUILD_DIR}/${MAIN_JAR}"

# Copy compat-bin scripts
mkdir -p "${RESOURCES_DIR}/compat-bin"
cp "${SCRIPT_DIR}/compat-bin/"* "${RESOURCES_DIR}/compat-bin/"
chmod +x "${RESOURCES_DIR}/compat-bin/"*

# Copy launch script
cp "${SCRIPT_DIR}/launch.sh" "${RESOURCES_DIR}/launch.sh"
chmod +x "${RESOURCES_DIR}/launch.sh"

# Copy LaunchAgent plist
cp "${SCRIPT_DIR}/com.ocx.worker.plist" "${RESOURCES_DIR}/com.ocx.worker.plist"

# ── Create icon (placeholder if no .icns) ─────────────────────
ICON_PATH="${SCRIPT_DIR}/ocx-worker.icns"
if [ ! -f "$ICON_PATH" ]; then
    echo "⚠️  No ocx-worker.icns found, generating placeholder icon..."
    # Generate a simple .icns from a 1024x1024 PNG using sips + iconutil
    ICONSET_DIR="${BUILD_DIR}/ocx-worker.iconset"
    mkdir -p "$ICONSET_DIR"

    # Create a simple placeholder PNG (1024x1024 green square with "OX" text)
    if command -v python3 &>/dev/null; then
        python3 -c "
import struct, zlib

# Create a minimal 1024x1024 RGBA PNG with 'OX' text-like appearance
# This is a placeholder — replace with a real icon
width, height = 1024, 1024
# Green background
raw = b''
for y in range(height):
    raw += b'\\x00'  # filter byte
    for x in range(width):
        # Background: gradient green
        dist = ((x-512)**2 + (y-512)**2)**0.5
        if dist < 400:
            raw += b'\\x00\\x128\\x60\\xff'  # green circle
        else:
            raw += b'\\x1a\\x1a\\x2e\\xff'  # dark bg

def make_png(raw_data, w, h):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    sig = b'\\x89PNG\\r\\n\\x1a\\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(raw_data))
    iend = chunk(b'IEND', b'')
    return sig + ihdr + idat + iend

with open('${ICONSET_DIR}/icon_512x512@2x.png', 'wb') as f:
    f.write(make_png(raw, width, height))
" 2>/dev/null || echo "  (python3 icon generation failed, using fallback)"
    fi

    # Create other sizes from the 1024x1024
    for size in 16 32 64 128 256 512; do
        if [ -f "${ICONSET_DIR}/icon_512x512@2x.png" ]; then
            sips -z "$size" "$size" "${ICONSET_DIR}/icon_512x512@2x.png" \
                --out "${ICONSET_DIR}/icon_${size}x${size}.png" &>/dev/null || true
        fi
    done
    # Create @2x variants
    for size in 16 32 64 128 256; do
        double=$((size * 2))
        if [ -f "${ICONSET_DIR}/icon_${double}x${double}.png" ]; then
            cp "${ICONSET_DIR}/icon_${double}x${double}.png" \
               "${ICONSET_DIR}/icon_${size}x${size}@2x.png" 2>/dev/null || true
        fi
    done

    # Convert .iconset to .icns
    if command -v iconutil &>/dev/null && [ -d "$ICONSET_DIR" ]; then
        iconutil -c icns "$ICONSET_DIR" -o "${BUILD_DIR}/ocx-worker.icns" 2>/dev/null || true
    fi

    ICON_PATH="${BUILD_DIR}/ocx-worker.icns"
    [ -f "$ICON_PATH" ] || ICON_PATH=""
fi

# ── Build with jpackage ───────────────────────────────────────
echo "🔧 Running jpackage..."

JPACKAGE_ARGS=(
    --name "OCX Worker"
    --input "$BUILD_DIR"
    --main-jar "$MAIN_JAR"
    --main-class com.ociworker.OciWorkerApplication
    --type app-image
    --app-version "$APP_VERSION"
    --vendor "$VENDOR"
    --identifier "$BUNDLE_ID"
    --dest "$DIST_DIR"

    # JVM options
    --java-options "--add-opens=java.base/java.lang=ALL-UNNAMED"
    --java-options "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED"
    --java-options "-Xms256m"
    --java-options "-Xmx512m"

    # macOS specific
    --mac-package-identifier "$BUNDLE_ID"
    --mac-package-name "OCX Worker"

    # Resource directory (for launch.sh, compat-bin, plist)
    --resource-dir "$RESOURCES_DIR"
)

if [ -n "$ICON_PATH" ] && [ -f "$ICON_PATH" ]; then
    JPACKAGE_ARGS+=(--icon "$ICON_PATH")
fi

jpackage "${JPACKAGE_ARGS[@]}"

# ── Inject custom launch.sh into the .app bundle ──────────────
echo "🚀 Injecting macOS launch script..."
APP_BUNDLE="${DIST_DIR}/OCX Worker.app"

# Replace the default launcher with our custom one
cp "${SCRIPT_DIR}/launch.sh" "${APP_BUNDLE}/Contents/MacOS/launch.sh"
chmod +x "${APP_BUNDLE}/Contents/MacOS/launch.sh"

# Inject compat-bin into the app bundle
mkdir -p "${APP_BUNDLE}/Contents/Resources/compat-bin"
cp "${SCRIPT_DIR}/compat-bin/"* "${APP_BUNDLE}/Contents/Resources/compat-bin/"
chmod +x "${APP_BUNDLE}/Contents/Resources/compat-bin/"*

# Inject LaunchAgent plist
cp "${SCRIPT_DIR}/com.ocx.worker.plist" "${APP_BUNDLE}/Contents/Resources/com.ocx.worker.plist"

# ── Create .dmg ────────────────────────────────────────────────
echo "💿 Creating DMG..."
DMG_NAME="ocx-worker-${APP_VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

# Use hdiutil to create a DMG
DMG_STAGING="${BUILD_DIR}/dmg-staging"
mkdir -p "$DMG_STAGING"

# Copy .app into staging
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"

# Create a symlink to /Applications for drag-and-drop install
ln -s /Applications "${DMG_STAGING}/Applications"

# Create the DMG
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" 2>/dev/null || {
    echo "⚠️  hdiutil failed (running on non-Mac?). .app bundle is still available."
    echo "   Distribution: zip the .app bundle instead."
    # Create a zip as fallback
    cd "$DIST_DIR"
    zip -r -q "ocx-worker-${APP_VERSION}-macos.zip" "OCX Worker.app"
    echo "✅ Created: ocx-worker-${APP_VERSION}-macos.zip"
    echo "   Size: $(du -h "ocx-worker-${APP_VERSION}-macos.zip" | cut -f1)"
    exit 0
}

echo ""
echo "✅ Build complete!"
echo "   App:  ${APP_BUNDLE}"
echo "   DMG:  ${DMG_PATH}"
echo "   Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "📋 Installation on macOS:"
echo "   1. Double-click ${DMG_NAME}"
echo "   2. Drag 'OCX Worker' to /Applications"
echo "   3. First launch: Right-click → Open (bypass Gatekeeper)"
echo "   4. App will check for Java 21+ and MySQL"
echo ""
echo "📋 To run as background service (optional):"
echo "   sudo cp /Applications/OCX\\ Worker.app/Contents/Resources/com.ocx.worker.plist /Library/LaunchDaemons/"
echo "   sudo launchctl load -w /Library/LaunchDaemons/com.ocx.worker.plist"
