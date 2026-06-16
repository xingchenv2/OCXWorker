#!/bin/bash
# ──────────────────────────────────────────────────────────────
# launch.sh — OCX Worker macOS App Launcher
#
# This script:
# 1. Resolves the app bundle directory
# 2. Injects compat-bin/ into PATH (overrides Linux commands)
# 3. Sets up macOS-specific directories and config
# 4. Starts a local MySQL instance (via Homebrew or bundled)
# 5. Launches the JAR with the bundled JRE
# ──────────────────────────────────────────────────────────────
set -euo pipefail

# ── Resolve app bundle paths ──────────────────────────────────
# When running from .app bundle:  Contents/MacOS/launch.sh
# When running from dev:          mac-app/launch.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "${SCRIPT_DIR}/../Resources/app/ocx-worker.jar" ]; then
    # Running from .app bundle
    APP_RESOURCES="${SCRIPT_DIR}/../Resources"
    APP_DIR="${SCRIPT_DIR}/.."
    JAR_DIR="${APP_RESOURCES}/app"
    RUNTIME_DIR="${APP_RESOURCES}/runtime/Contents/Home"
    COMPAT_DIR="${APP_RESOURCES}/compat-bin"
else
    # Running from development directory
    APP_RESOURCES="${SCRIPT_DIR}"
    APP_DIR="${SCRIPT_DIR}"
    JAR_DIR="${SCRIPT_DIR}"
    RUNTIME_DIR=""  # Use system java
    COMPAT_DIR="${SCRIPT_DIR}/compat-bin"
fi

JAR_FILE="${JAR_DIR}/ocx-worker.jar"

# ── macOS Data Directory ──────────────────────────────────────
DATA_DIR="${HOME}/Library/Application Support/OCX Worker"
KEYS_DIR="${DATA_DIR}/keys"
LOG_DIR="${HOME}/Library/Logs/OCX Worker"

mkdir -p "$DATA_DIR" "$KEYS_DIR" "$LOG_DIR"

# ── Inject compat-bin into PATH (priority) ────────────────────
export PATH="${COMPAT_DIR}:${PATH}"

# ── macOS-specific environment variables ──────────────────────
# Tell the Java app where to store keys on Mac
export OCX_KEY_DIR_PATH="$KEYS_DIR"
export OCX_LOG_DIR="$LOG_DIR"
# Override JAR path for SystemService (auto-update)
export OCX_JAR_PATH="$JAR_FILE"

# ── Determine Java command ───────────────────────────────────
if [ -n "$RUNTIME_DIR" ] && [ -x "${RUNTIME_DIR}/bin/java" ]; then
    JAVA="${RUNTIME_DIR}/bin/java"
else
    # Fall back to system Java
    JAVA="$(command -v java 2>/dev/null || echo "")"
    if [ -z "$JAVA" ]; then
        echo "❌ Java 21+ not found." >&2
        echo "   Install with: brew install openjdk@21" >&2
        echo "   Or re-run the installer to bundle a JRE." >&2
        #
        # Show a macOS alert dialog
        if command -v osascript &>/dev/null; then
            osascript -e 'display dialog "OCX Worker requires Java 21+\n\nInstall with:\nbrew install openjdk@21\n\nOr download from:\nhttps://adoptium.net" with title "OCX Worker — Java Not Found" buttons {"OK"} default button "OK" with icon stop'
        fi
        exit 1
    fi
fi

# ── Check / Start MySQL ───────────────────────────────────────
check_mysql() {
    # Try connecting on localhost:3306
    if command -v mysql &>/dev/null; then
        mysql -h 127.0.0.1 -P 3306 -u root -e "SELECT 1" &>/dev/null
        return $?
    fi
    # Fallback: try netcat
    if command -v nc &>/dev/null; then
        nc -z 127.0.0.1 3306 2>/dev/null
        return $?
    fi
    # Can't check, assume it's running
    return 0
}

if ! check_mysql; then
    echo "⚠️  MySQL not detected on localhost:3306" >&2
    # Try starting Homebrew MySQL
    if [ -f /opt/homebrew/opt/mysql/support-files/mysql.server ]; then
        /opt/homebrew/opt/mysql/support-files/mysql.server start 2>/dev/null || true
    elif [ -f /usr/local/opt/mysql/support-files/mysql.server ]; then
        /usr/local/opt/mysql/support-files/mysql.server start 2>/dev/null || true
    fi
    sleep 2
    if ! check_mysql; then
        echo "❌ MySQL is not running." >&2
        echo "   Install with: brew install mysql" >&2
        echo "   Then start:   brew services start mysql" >&2
        if command -v osascript &>/dev/null; then
            osascript -e 'display dialog "OCX Worker requires MySQL\n\nInstall with:\nbrew install mysql\nbrew services start mysql" with title "OCX Worker — MySQL Not Found" buttons {"OK"} default button "OK" with icon caution'
        fi
        exit 1
    fi
fi

# ── Create database & user if not exists ──────────────────────
if command -v mysql &>/dev/null; then
    mysql -h 127.0.0.1 -u root -e \
        "CREATE DATABASE IF NOT EXISTS oci_worker CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
         CREATE USER IF NOT EXISTS 'ocxworker'@'localhost' IDENTIFIED BY 'ocxworker123';
         GRANT ALL PRIVILEGES ON oci_worker.* TO 'ocxworker'@'localhost';
         FLUSH PRIVILEGES;" 2>/dev/null || true
fi

# ── SSH config fix for macOS ──────────────────────────────────
# macOS sshd config is at /etc/ssh/sshd_config (no sshd_config.d/)
# Create the compat symlink so Linux-style paths work
if [ ! -d /etc/ssh/sshd_config.d ]; then
    # We can't mkdir /etc/ssh/ without sudo; the compat script will handle it
    export MAC_SSH_CONFIG_MODE="append"
fi

# ── Launch the JAR ────────────────────────────────────────────
echo "🚀 Starting OCX Worker..."
echo "   JAR:    $JAR_FILE"
echo "   Java:   $JAVA"
echo "   Data:   $DATA_DIR"
echo "   Keys:   $KEYS_DIR"
echo "   Compat: $COMPAT_DIR"
echo ""

exec "$JAVA" \
    -jar "$JAR_FILE" \
    --spring.datasource.url="jdbc:mysql://localhost:3306/oci_worker?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=Asia/Shanghai&allowPublicKeyRetrieval=true" \
    --spring.datasource.username=ocxworker \
    --spring.datasource.password=ocxworker123 \
    --oci-cfg.key-dir-path="$KEYS_DIR" \
    ${OCX_EXTRA_JAVA_OPTS:-} \
    "$@"
