# OCX Worker — macOS Desktop App (Self-Contained)

将 OCX Worker 打包为 **完全自包含** 的 macOS 桌面应用。

**零外部依赖** — 数据库、密钥、日志全部在 app 内部，不在 app 外创建任何文件。

## 架构

```
OCX Worker.app/
  Contents/
    MacOS/
      launch.sh              ← 自定义启动脚本
    Resources/
      app/
        ocx-worker.jar        ← Spring Boot 应用
        schema-sqlite.sql     ← SQLite 建表脚本
        sqlite-jdbc-3.45.1.0.jar  ← SQLite JDBC 驱动
      data/                   ← 所有用户数据（app 内部）
        ocx-worker.db         ← SQLite 数据库（首次启动自动创建）
        keys/                 ← SSH 密钥
        logs/                 ← 应用日志
        backups/              ← 自动备份
      compat-bin/             ← macOS 兼容脚本
        chpasswd              → dscl . -passwd
        userdel               → dscl . -delete
        systemctl             → launchctl load/unload
        getenforce            → echo "Disabled"
        restorecon            → 空操作
      runtime/                ← 捆绑 JRE 21（--with-jre 时）
      com.ocx.worker.plist    ← LaunchDaemon 配置（可选后台服务）
```

## SQLite vs MySQL

| | MySQL (服务端) | SQLite (桌面端) |
|---|---|---|
| 安装 | 需要系统安装 | **JDBC 驱动内嵌，零安装** |
| 端口 | 监听 3306 | **无端口，无网络暴露** |
| 认证 | 需用户名密码 | **无认证，文件权限保护** |
| 数据位置 | 系统目录 | **app 内部 data/** |
| 并发 | 多用户写入 | 单用户（桌面端足够） |
| 备份 | mysqldump | **复制 .db 文件** |

### Schema 适配

MySQL → SQLite 转换规则：
- `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=...` → 删除
- `TINYINT(1)` → `INTEGER`
- `MEDIUMTEXT` → `TEXT`
- `UNIQUE KEY uk_xxx (col)` → `CREATE UNIQUE INDEX IF NOT EXISTS uk_xxx ON table (col)`
- `INDEX idx_xxx (col)` → `CREATE INDEX IF NOT EXISTS idx_xxx ON table (col)`
- `AUTO_INCREMENT` → SQLite 自动处理
- `AFTER column` → SQLite 不支持，删除（列顺序无关紧要）

## 兼容脚本说明

| Linux 命令 | macOS 替代 | 说明 |
|-----------|-----------|------|
| `chpasswd` | `dscl . -passwd` | Linux 从 stdin 读 `user:pass`，Mac 用 dscl |
| `userdel -rf` | `dscl . -delete` + `rm -rf` | Linux 删用户，Mac 用 Directory Service |
| `systemctl start/stop/restart` | `launchctl load/unload` | Linux systemd，Mac launchd |
| `getenforce` | `echo "Disabled"` | SELinux 不存在于 macOS |
| `restorecon` | `true` | SELinux 上下文恢复，Mac 不需要 |

## 构建（需要在 macOS 上执行）

```bash
# 前置条件
xcode-select --install
brew install openjdk@21

# 基础构建（不含 JRE，用户需自己装 Java）
./build-mac-dmg.sh /path/to/ocx-worker.jar

# 完整构建（含 JRE 21，用户无需装任何东西）
./build-mac-dmg.sh --with-jre /path/to/ocx-worker.jar

# 仅构建 .app，不打包 .dmg
./build-mac-dmg.sh --skip-dmg /path/to/ocx-worker.jar
```

## 安装后使用

1. 双击 `.dmg` → 拖到 `/Applications`
2. 首次启动：右键 → 打开（绕过 Gatekeeper）
3. 首次启动自动检测 Java 21+（未捆绑 JRE 时）
4. 自动在 app 内创建 SQLite 数据库
5. 浏览器打开 `http://localhost:8818`

## 数据安全

- **数据库文件权限**: `chmod 600 ocx-worker.db`（仅当前用户可读写）
- **密钥目录权限**: `chmod 700 data/keys/`
- **数据目录权限**: `chmod 700 data/`
- **无网络端口暴露**: SQLite 不监听任何端口
- **一键清除**: 删除 app 即可清除所有数据（`rm -rf "OCX Worker.app"`）
- **一键备份**: 复制 `Contents/Resources/data/` 即可

## 可选：后台服务模式

```bash
# 注册为开机自启服务
sudo cp /Applications/OCX\ Worker.app/Contents/Resources/com.ocx.worker.plist /Library/LaunchDaemons/
sudo launchctl load -w /Library/LaunchDaemons/com.ocx.worker.plist

# 停止服务
sudo launchctl unload /Library/LaunchDaemons/com.ocx.worker.plist

# 日志在 app 内部
tail -f /Applications/OCX\ Worker.app/Contents/Resources/data/logs/launchd-stdout.log
```

## 重置数据

```bash
# 删除数据库重新初始化
rm "/Applications/OCX Worker.app/Contents/Resources/data/ocx-worker.db"

# 清空所有用户数据
rm -rf "/Applications/OCX Worker.app/Contents/Resources/data/"
mkdir -p "/Applications/OCX Worker.app/Contents/Resources/data/keys"
mkdir -p "/Applications/OCX Worker.app/Contents/Resources/data/logs"
mkdir -p "/Applications/OCX Worker.app/Contents/Resources/data/backups"
```

## 注意事项

- **串口控制台**：macOS 不支持 Oracle Cloud 串口连接（仅适用于 OCI Linux 实例）
- **WebSSH**：完全支持（JSch 是纯 Java SSH 客户端，Pty4j 支持 macOS PTY）
- **`DatabaseGuardService`**：JAR 内部的 DDL 是 MySQL 语法，需要重新编译替换为 SQLite 版本（见下方）
- **`BackupService`**：`SET FOREIGN_KEY_CHECKS` / `SET NAMES utf8mb4` 对 SQLite 无害（会被忽略）

### ⚠️ JAR 内部 DDL 适配

JAR 中的 `DatabaseGuardService.class` 包含 MySQL 语法的建表语句。
启动时 `spring.sql.init.mode=always` + `schema-sqlite.sql` 会在 SQLite 上执行正确建表。
`DatabaseGuardService` 发现表已存在会跳过创建，但 `migrateColumns()` 中的 `AFTER column` 语法
SQLite 不支持 — 需要重新编译 `DatabaseGuardService.class` 去除 `AFTER` 子句。

## Java 代码改动清单（SQLite 适配）

仅 2 个 Java 文件需要修改：

| 文件 | 改动 | 重要性 |
|------|------|--------|
| `DatabaseGuardService.java` | TABLE_DDL 中的 MySQL 语法→SQLite；`migrateColumns` 去除 `AFTER column` | **必须** |
| `BackupService.java` | `SET NAMES`/`SET FOREIGN_KEY_CHECKS` 删除（SQLite 无此语法，忽略也不报错） | 可选 |
