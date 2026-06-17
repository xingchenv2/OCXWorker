#!/bin/bash
# ──────────────────────────────────────────────────────────────
# macOS OCX — App Launcher (Native Window Mode)
#
# This is the main entry point for macOS OCX.
# It starts the backend, waits for it to be ready,
# then opens the UI using the BEST available method:
#
#   1. Swift WebView wrapper (if compiled) — BEST, native window
#   2. Python3 + pyobjc (if available) — native window
#   3. System browser — fallback, opens in Safari/Chrome
#
# Zero external dependencies required for mode 3.
# Modes 1 & 2 give in-app experience.
# ──────────────────────────────────────────────────────────────
set -euo pipefail

APP_NAME="macOS OCX"
APP_VERSION="2.0.1"
SERVER_PORT=8818

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="${BUNDLE}/Resources"
MACOS="${BUNDLE}/MacOS"

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

LOG_FILE="${LOG_DIR}/launch.log"
mkdir -p "$LOG_DIR"

# Log function
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; echo "[$(date '+%H:%M:%S')] $*"; }

# ── Detect CPU architecture → pick bundled JRE ────────────────
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
        log "⚠️  Using system Java (bundled JRE not found)"
    else
        log "❌ No Java found!"
        if command -v osascript &>/dev/null; then
            osascript -e "display dialog \"macOS OCX 无法启动\\n\\n未找到 Java 运行时，请重新下载完整安装包\" with title \"macOS OCX — 启动失败\" buttons {\"OK\"} default button \"OK\" with icon stop"
        fi
        exit 1
    fi
fi

log "Java: $JAVA ($ARCH)"

# ── Create data directories ────────────────────────────────────
mkdir -p "$DATA_DIR" "$KEYS_DIR" "$LOG_DIR" "$BACKUP_DIR"
chmod 700 "$DATA_DIR" 2>/dev/null || true
chmod 700 "$KEYS_DIR" 2>/dev/null || true
[ -f "$DB_FILE" ] && chmod 600 "$DB_FILE" 2>/dev/null || true

# ── Inject compat-bin into PATH ────────────────────────────────
export PATH="${COMPAT_DIR}:${PATH}"

# ── Initialize SQLite (first run) ─────────────────────────────
if [ ! -f "$DB_FILE" ]; then
    SQLITE3="$(command -v sqlite3 2>/dev/null || true)"
    if [ -n "$SQLITE3" ] && [ -f "$SCHEMA_FILE" ]; then
        log "🗄️  初始化 SQLite 数据库..."
        "$SQLITE3" "$DB_FILE" < "$SCHEMA_FILE"
        chmod 600 "$DB_FILE"
        log "✅ 数据库已创建"
    else
        log "ℹ️  DB will be auto-created by Spring Boot"
    fi
fi

# ── Start Spring Boot backend (background) ─────────────────────
log "🚀 Starting backend..."

"$JAVA" \
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
    "$@" >> "${LOG_DIR}/backend.log" 2>&1 &

BACKEND_PID=$!
log "Backend PID: $BACKEND_PID"

# ── Wait for backend, then open UI ────────────────────────────
log "⏳ Waiting for backend..."
ATTEMPTS=0
MAX_ATTEMPTS=60

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    ATTEMPTS=$((ATTEMPTS + 1))
    
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$SERVER_PORT" 2>/dev/null || echo "000")
    
    if echo "$HTTP_CODE" | grep -qE '^[23]'; then
        log "✅ Backend ready! (HTTP $HTTP_CODE after ${ATTEMPTS}s)"
        
        # ── Choose UI mode ──────────────────────────────────────
        # Mode 1: Compiled Swift native window (BEST)
        if [ -x "${MACOS}/MacOSOCX" ]; then
            log "🪟 Opening native Swift window..."
            "${MACOS}/MacOSOCX"
            # When Swift window closes, we get here → kill backend
            kill $BACKEND_PID 2>/dev/null
            exit 0
        fi
        
        # Mode 2: Open in default browser
        log "🌐 Opening in browser (compile Swift for native window)..."
        open "http://localhost:$SERVER_PORT"
        
        # Keep script running while backend is up
        # When user closes the terminal / kills process, backend dies too
        log "ℹ️  Backend running at http://localhost:$SERVER_PORT"
        log "ℹ️  To get native window: run build-mac-dmg.sh on this Mac"
        wait $BACKEND_PID
        exit 0
    fi
    
    sleep 1
done

log "❌ Backend failed to start within 60s"
if command -v osascript &>/dev/null; then
    osascript -e "display dialog \"macOS OCX 启动失败\\n\\n服务启动超时，请查看日志：\\n${LOG_DIR}/backend.log\" with title \"macOS OCX — 启动失败\" buttons {\"OK\"} default button \"OK\" with icon stop"
fi
kill $BACKEND_PID 2>/dev/null
exit 1
