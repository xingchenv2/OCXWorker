#!/bin/bash
# ──────────────────────────────────────────────────────────────
# macOS OCX — Backend Launcher
#
# Called by entry.applescript (native window mode).
# Purely starts the Spring Boot backend — no UI logic here.
# ──────────────────────────────────────────────────────────────
set -euo pipefail

APP_NAME="macOS OCX"
SERVER_PORT=8818

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="${BUNDLE}/Resources"

APP_DIR="${RESOURCES}/app"
DATA_DIR="${RESOURCES}/data"
KEYS_DIR="${DATA_DIR}/keys"
LOG_DIR="${DATA_DIR}/logs"
BACKUP_DIR="${DATA_DIR}/backups"
DB_FILE="${DATA_DIR}/ocx-worker.db"
COMPAT_DIR="${RESOURCES}/compat-bin"

JAR_FILE="${APP_DIR}/ocx-worker.jar"
SQLITE_JDBC="${APP_DIR}/sqlite-jdbc-3.45.1.0.jar"
SCHEMA_FILE="${APP_DIR}/schema-sqlite.sql"

# ── Detect architecture → pick JRE ────────────────────────────
ARCH="$(uname -m)"
case "$ARCH" in
    arm64|aarch64)  RUNTIME_DIR="${RESOURCES}/runtime-arm64" ;;
    x86_64|x64)     RUNTIME_DIR="${RESOURCES}/runtime-x64" ;;
    *)              RUNTIME_DIR="${RESOURCES}/runtime-arm64" ;;
esac

JAVA=""
for candidate in \
    "$RUNTIME_DIR"/*/zulu-*.jre/Contents/Home/bin/java \
    "$RUNTIME_DIR"/*/Contents/Home/bin/java \
    "$RUNTIME_DIR"/*/Home/bin/java; do
    if [ -x "$candidate" ]; then
        JAVA="$candidate"
        break
    fi
done

if [ -z "$JAVA" ] || [ ! -x "$JAVA" ]; then
    if command -v java &>/dev/null; then
        JAVA="$(command -v java)"
    else
        echo "❌ No Java runtime found!" >&2
        if command -v osascript &>/dev/null; then
            osascript -e "display dialog \"macOS OCX 无法启动\\n\\n未找到 Java 运行时\\n请重新下载完整安装包\" with title \"macOS OCX — 启动失败\" buttons {\"OK\"} default button \"OK\" with icon stop" &
        fi
        exit 1
    fi
fi

# ── Create data directories (inside app bundle) ───────────────
mkdir -p "$DATA_DIR" "$KEYS_DIR" "$LOG_DIR" "$BACKUP_DIR"
chmod 700 "$DATA_DIR" 2>/dev/null || true
chmod 700 "$KEYS_DIR" 2>/dev/null || true
[ -f "$DB_FILE" ] && chmod 600 "$DB_FILE" 2>/dev/null || true

# ── Inject compat-bin → PATH ──────────────────────────────────
export PATH="${COMPAT_DIR}:${PATH}"

# ── Initialize SQLite (first run) ─────────────────────────────
if [ ! -f "$DB_FILE" ]; then
    SQLITE3="$(command -v sqlite3 2>/dev/null || true)"
    if [ -n "$SQLITE3" ] && [ -f "$SCHEMA_FILE" ]; then
        "$SQLITE3" "$DB_FILE" < "$SCHEMA_FILE"
        chmod 600 "$DB_FILE"
    fi
fi

# ── Launch Spring Boot (foreground) ───────────────────────────
# AppleScript wrapper manages this process and can kill it
exec "$JAVA" \
    -Dloader.main=com.ociworker.OciWorkerApplication \
    -Dloader.path="${APP_DIR}/" \
    -cp "$JAR_FILE" \
    org.springframework.boot.loader.launch.PropertiesLauncher \
    --spring.datasource.driver-class-name=org.sqlite.JDBC \
    --spring.datasource.url="jdbc:sqlite:${DB_FILE}?journal_mode=WAL&busy_timeout=5000&foreign_keys=on" \
    --spring.datasource.username=sa \
    --spring.datasource.password= \
    --spring.sql.init.mode=always \
    --spring.sql.init.schema-locations=classpath:schema-sqlite.sql \
    --spring.sql.init.continue-on-error=true \
    --server.port="$SERVER_PORT" \
    --oci-cfg.key-dir-path="$KEYS_DIR" \
    ${OCX_EXTRA_JAVA_OPTS:-} \
    "$@"
