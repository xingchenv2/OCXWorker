# macOS OCX — macOS 自包含桌面端

**零外部依赖** — 下载、解压、双击即用。

## 版本区分

| 品牌 | 版本号 | 用途 |
|------|--------|------|
| **OCX Worker** | v2.0.x | 服务端部署（JAR + MySQL） |
| **macOS OCX** | v2.0.x | macOS 桌面端（.app + SQLite + 内置 JRE） |

两条产品线独立版本号，分别迭代。

## 架构

```
macOS OCX.app/
  Contents/
    MacOS/
      launch.sh              ← 自定义启动脚本
    Info.plist               ← macOS 应用信息
    Resources/
      app/
        ocx-worker.jar        ← Spring Boot 应用（来自 OCX Worker）
        sqlite-jdbc-3.45.1.0.jar  ← SQLite JDBC 驱动
        schema-sqlite.sql     ← SQLite 建表脚本
      data/                   ← 所有用户数据（app 内部）
        ocx-worker.db         ← SQLite 数据库（首次启动自动创建）
        keys/                 ← SSH 密钥
        logs/                 ← 应用日志
        backups/              ← 自动备份
      runtime-arm64/          ← 内置 JRE 21 (Apple Silicon)
      runtime-x64/           ← 内置 JRE 21 (Intel)
      compat-bin/             ← macOS 兼容脚本
        chpasswd              → dscl . -passwd
        userdel               → dscl . -delete
        systemctl             → launchctl load/unload
        getenforce            → echo "Disabled"
        restorecon            → 空操作
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
- `AFTER column` → SQLite 不支持，删除

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

# 完整构建（含 JRE 21，用户无需装任何东西）
./build-mac-dmg.sh --with-jre /path/to/ocx-worker.jar

# 仅构建 .app，不打包 .dmg
./build-mac-dmg.sh --skip-dmg /path/to/ocx-worker.jar
```

## 安装后使用

1. 下载对应架构的 zip（ARM64 或 x64）
2. 解压 → 拖到 `/Applications`
3. 首次启动：右键 → 打开（绕过 Gatekeeper）
4. 自动在 app 内创建 SQLite 数据库
5. 浏览器打开 `http://localhost:8818`

## 数据安全

- **数据库文件权限**: `chmod 600 ocx-worker.db`
- **密钥目录权限**: `chmod 700 data/keys/`
- **数据目录权限**: `chmod 700 data/`
- **无网络端口暴露**: SQLite 不监听任何端口
- **一键清除**: 删除 app 即可清除所有数据
- **一键备份**: 复制 `Contents/Resources/data/` 即可

## 可选：后台服务模式

```bash
# 注册为开机自启服务
sudo cp /Applications/macOS\ OCX.app/Contents/Resources/com.ocx.worker.plist /Library/LaunchDaemons/
sudo launchctl load -w /Library/LaunchDaemons/com.ocx.worker.plist

# 停止服务
sudo launchctl unload /Library/LaunchDaemons/com.ocx.worker.plist
```

## 重置数据

```bash
rm "/Applications/macOS OCX.app/Contents/Resources/data/ocx-worker.db"
```

## ⚠️ 注意事项

- **串口控制台**: macOS 不支持 Oracle Cloud 串口连接（仅适用于 OCI Linux 实例）
- **WebSSH**: 完全支持
- **JAR 内部 DDL**: `DatabaseGuardService.class` 已改为 SQLite 兼容语法
- **BackupService**: MySQL 特有 `SET` 命令已移除
