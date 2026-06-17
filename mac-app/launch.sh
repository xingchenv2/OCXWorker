#!/bin/bash
# ──────────────────────────────────────────────────────────────
# macOS OCX — Self-Contained Desktop App Launcher
#
# Brand: macOS OCX (desktop) | Based on: OCX Worker (server)
# Zero external dependencies — double-click to run.
# ──────────────────────────────────────────────────────────────
set -euo pipefail

APP_NAME="macOS OCX"
APP_VERSION="2.0.1"
SERVER_PORT=8818

# ── Resolve bundle paths ──────────────────────────────────────
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

# ── Detect CPU architecture → pick correct bundled JRE ───────
ARCH="$(uname -m)"
case "$ARCH" in
    arm64|aarch64)  RUNTIME_DIR="${RESOURCES}/runtime-arm64" ;;
    x86_64|x64)     RUNTIME_DIR="${RESOURCES}/runtime-x64" ;;
    *)              RUNTIME_DIR="${RESOURCES}/runtime-arm64" ;;
esac

# Find JRE java binary
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
        echo "⚠️  Bundled JRE not found, using system Java: $JAVA"
    else
        echo "❌ No Java found! Please re-download macOS OCX." >&2
        if command -v osascript &>/dev/null; then
            osascript -e "display dialog \"macOS OCX 无法启动\n\n未找到 Java 运行时，请重新下载完整安装包\" with title \"macOS OCX — 启动失败\" buttons {\"OK\"} default button \"OK\" with icon stop"
        fi
        exit 1
    fi
fi

# ── Create data directories (all inside app bundle) ───────────
mkdir -p "$DATA_DIR" "$KEYS_DIR" "$LOG_DIR" "$BACKUP_DIR"
chmod 700 "$DATA_DIR" 2>/dev/null || true
chmod 700 "$KEYS_DIR" 2>/dev/null || true
[ -f "$DB_FILE" ] && chmod 600 "$DB_FILE" 2>/dev/null || true

# ── Inject compat-bin into PATH ──────────────────────────────
export PATH="${COMPAT_DIR}:${PATH}"

# ── Initialize SQLite (first run) ─────────────────────────────
if [ ! -f "$DB_FILE" ]; then
    SQLITE3="$(command -v sqlite3 2>/dev/null || true)"
    if [ -n "$SQLITE3" ] && [ -f "$SCHEMA_FILE" ]; then
        echo "🗄️  初始化 SQLite 数据库..."
        "$SQLITE3" "$DB_FILE" < "$SCHEMA_FILE"
        chmod 600 "$DB_FILE"
        echo "✅ 数据库已创建: $DB_FILE"
    else
        echo "ℹ️  数据库将在应用启动时自动创建"
    fi
fi

# ── Launch ─────────────────────────────────────────────────────
echo "🚀 $APP_NAME v$APP_VERSION"
echo "   Java:   $JAVA ($ARCH)"
echo "   DB:     $DB_FILE"
echo "   URL:    http://localhost:$SERVER_PORT"
echo ""

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
