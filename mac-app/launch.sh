#!/bin/bash
# ──────────────────────────────────────────────────────────────
# launch.sh — OCX Worker macOS App Launcher (Self-Contained)
#
# Design: ALL data stays inside the app bundle.
#         No external files/dirs created without user consent.
#         SQLite replaces MySQL — zero external dependencies.
# ──────────────────────────────────────────────────────────────
set -euo pipefail

# ── Resolve app bundle paths ──────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "${SCRIPT_DIR}/../Resources/app/ocx-worker.jar" ]; then
    # Running from .app bundle
    RESOURCES="${SCRIPT_DIR}/../Resources"
    JAR_DIR="${RESOURCES}/app"
    RUNTIME_DIR="${RESOURCES}/runtime/Contents/Home"
    COMPAT_DIR="${RESOURCES}/compat-bin"
    # Self-contained data directory INSIDE the app bundle
    DATA_DIR="${RESOURCES}/data"
else
    # Running from development directory
    RESOURCES="${SCRIPT_DIR}"
    JAR_DIR="${SCRIPT_DIR}"
    RUNTIME_DIR=""
    COMPAT_DIR="${SCRIPT_DIR}/compat-bin"
    DATA_DIR="${SCRIPT_DIR}/data"
fi

JAR_FILE="${JAR_DIR}/ocx-worker.jar"
DB_FILE="${DATA_DIR}/ocx-worker.db"
KEYS_DIR="${DATA_DIR}/keys"
LOG_DIR="${DATA_DIR}/logs"
BACKUP_DIR="${DATA_DIR}/backups"

# ── Create data directories (all inside app bundle) ──────────
mkdir -p "$DATA_DIR" "$KEYS_DIR" "$LOG_DIR" "$BACKUP_DIR"

# ── Secure file permissions ──────────────────────────────────
chmod 700 "$DATA_DIR"
chmod 600 "$DB_FILE" 2>/dev/null || true
chmod 700 "$KEYS_DIR"

# ── Inject compat-bin into PATH (priority) ────────────────────
export PATH="${COMPAT_DIR}:${PATH}"

# ── macOS-specific environment variables ──────────────────────
export OCX_KEY_DIR_PATH="$KEYS_DIR"
export OCX_LOG_DIR="$LOG_DIR"
export OCX_JAR_PATH="$JAR_FILE"
export OCX_DATA_DIR="$DATA_DIR"

# ── Determine Java command ───────────────────────────────────
if [ -n "$RUNTIME_DIR" ] && [ -x "${RUNTIME_DIR}/bin/java" ]; then
    JAVA="${RUNTIME_DIR}/bin/java"
else
    JAVA="$(command -v java 2>/dev/null || echo "")"
    if [ -z "$JAVA" ]; then
        if command -v osascript &>/dev/null; then
            osascript -e 'display dialog "OCX Worker requires Java 21+\n\nInstall with:\nbrew install openjdk@21\n\nOr download from:\nhttps://adoptium.net" with title "OCX Worker — Java Not Found" buttons {"OK"} default button "OK" with icon stop'
        else
            echo "❌ Java 21+ not found. Install: brew install openjdk@21" >&2
        fi
        exit 1
    fi
fi

# ── Initialize SQLite database (if first run) ────────────────
if [ ! -f "$DB_FILE" ]; then
    echo "🗄️  Initializing SQLite database (first run)..."

    # Find SQLite3 binary
    SQLITE3=""
    if command -v sqlite3 &>/dev/null; then
        SQLITE3="$(command -v sqlite3)"
    elif [ -x "${RESOURCES}/sqlite3" ]; then
        SQLITE3="${RESOURCES}/sqlite3"
    elif [ -x "/usr/bin/sqlite3" ]; then
        SQLITE3="/usr/bin/sqlite3"
    fi

    # Check for bundled schema file
    SCHEMA_FILE=""
    if [ -f "${RESOURCES}/app/schema-sqlite.sql" ]; then
        SCHEMA_FILE="${RESOURCES}/app/schema-sqlite.sql"
    elif [ -f "${SCRIPT_DIR}/schema-sqlite.sql" ]; then
        SCHEMA_FILE="${SCRIPT_DIR}/schema-sqlite.sql"
    fi

    if [ -n "$SQLITE3" ] && [ -n "$SCHEMA_FILE" ] && [ -f "$SCHEMA_FILE" ]; then
        "$SQLITE3" "$DB_FILE" < "$SCHEMA_FILE"
        chmod 600 "$DB_FILE"
        echo "✅ Database initialized: $DB_FILE"
    else
        echo "ℹ️  SQLite3 not found on system. Database will be auto-created by JDBC on first launch."
        echo "   (Spring Boot will use schema-sqlite.sql via spring.sql.init)"
    fi
fi

# ── Launch the JAR with SQLite config ─────────────────────────
echo "🚀 Starting OCX Worker (Self-Contained Mode)..."
echo "   JAR:     $JAR_FILE"
echo "   Java:    $JAVA"
echo "   Data:    $DATA_DIR"
echo "   DB:      $DB_FILE"
echo "   Keys:    $KEYS_DIR"
echo "   Logs:    $LOG_DIR"
echo "   Compat:  $COMPAT_DIR"
echo ""

exec "$JAVA" \
    -jar "$JAR_FILE" \
    --spring.datasource.driver-class-name=org.sqlite.JDBC \
    --spring.datasource.url="jdbc:sqlite:${DB_FILE}?journal_mode=WAL&busy_timeout=5000&foreign_keys=on" \
    --spring.datasource.username=sa \
    --spring.datasource.password= \
    --spring.sql.init.mode=always \
    --spring.sql.init.schema-locations=classpath:schema-sqlite.sql \
    --spring.sql.init.continue-on-error=true \
    --oci-cfg.key-dir-path="$KEYS_DIR" \
    ${OCX_EXTRA_JAVA_OPTS:-} \
    "$@"
