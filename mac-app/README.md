# macOS OCX — macOS 自包含桌面端

**零外部依赖** — 下载、解压、双击即用。原生窗口内操作，无需浏览器。

## 版本区分

| 品牌 | 版本号 | 用途 |
|------|--------|------|
| **OCX Worker** | v2.0.x | 服务端部署（JAR + MySQL） |
| **macOS OCX** | v2.0.x | macOS 桌面端（.app + SQLite + 内置 JRE） |

两条产品线独立版本号，分别迭代。

## 架构

### 原生窗口方案（v2.0.7+）

首次启动时，`osacompile`（macOS 自带）将 `entry.applescript` 编译为 `Window.applet`（约1秒），之后直接使用编译后的 applet。无需 Xcode，无需 Swift 编译器。

```
双击 macOS OCX.app
  ↓
MacOSOCX (bash 入口, CFBundleExecutable)
  ↓
1. 修复 JRE 权限 (chmod -R u+X，zip 解压后权限可能丢失)
2. 检查/编译 Window.applet (osacompile, 首次运行)
3. 检测 JRE (内置 JRE 21 或系统 Java)
4. 初始化 SQLite 数据库
5. 启动 Spring Boot 后端 (port 8818)
6. 等待后端就绪 (HTTP 2xx/3xx, 最长 120s)
7. 打开 Window.applet (原生窗口)
   ↓
Window.applet (AppleScriptObjC 编译后 applet)
  ↓
创建 NSWindow + WKWebView → 加载 http://localhost:8818
  ↓
关闭窗口 → 退出 applet → 后端终止 → 退出
```

### .app 包结构

```
macOS OCX.app/
  Contents/
    MacOS/
      MacOSOCX             ← 主启动脚本 (CFBundleExecutable)
      entry.applescript     ← AppleScriptObjC 原生窗口源码
    Info.plist              ← macOS 应用信息
    Resources/
      AppIcon.icns          ← 应用图标
      app/
        ocx-worker.jar        ← Spring Boot 应用
        sqlite-jdbc-3.45.1.0.jar  ← SQLite JDBC 驱动
        schema-sqlite.sql     ← SQLite 建表脚本
      runtime-arm64/          ← 内置 JRE 21 (Apple Silicon)
      runtime-x64/           ← 内置 JRE 21 (Intel)
      compat-bin/             ← macOS 兼容脚本
        chpasswd, userdel, systemctl, getenforce, restorecon
```

### 数据目录（v2.0.7+ 重要变更！）

⚠️ **数据不在 .app 内部！** Gatekeeper 会让下载的 .app 变只读（App Translocation），所以所有可写数据存放在 macOS 标准位置：

```
~/Library/Application Support/macOS OCX/
  ├── ocx-worker.db       ← SQLite 数据库
  ├── keys/               ← SSH 密钥 (chmod 700)
  ├── logs/               ← 应用日志
  │   ├── launch.log      ← 启动日志
  │   ├── backend.log     ← Spring Boot 日志
  │   └── spring.log      ← Spring 框架日志
  ├── backups/            ← 自动备份
  └── Window.applet/      ← 编译后的原生窗口 (首次运行自动编译)
```

**为什么不在 .app 里？** macOS Gatekeeper 会把未签名 .app 搬到只读临时目录（App Translocation），导致写数据库/日志失败。`~/Library/Application Support/` 是 macOS 标准数据位置，始终可写。

## 使用方式

1. 下载对应架构的 zip（ARM64 = Apple Silicon, x64 = Intel）
2. 解压 → 拖入 `/Applications`
3. 首次启动：右键 → 打开（绕过 Gatekeeper）
4. ✅ 直接在 app 窗口内操作，无需浏览器！

## SQLite vs MySQL

| | MySQL (服务端) | SQLite (桌面端) |
|---|---|---|
| 安装 | 需要系统安装 | **JDBC 驱动内嵌，零安装** |
| 端口 | 监听 3306 | **无端口，无网络暴露** |
| 认证 | 需用户名密码 | **无认证，文件权限保护** |
| 数据位置 | 系统目录 | **~/Library/Application Support/** |
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

## 构建

```bash
# 使用缓存 JRE 构建（Linux 服务器）
./build-mac-dmg.sh --both /path/to/ocx-worker.jar

# 构建单个架构
./build-mac-dmg.sh /path/to/ocx-worker.jar

# JRE 缓存目录搜索顺序：
#   1. build script 同级 cache/
#   2. 上级 cache/
#   3. /tmp/mac-prebundle/
# 文件名：zulu-jre21-mac-arm64.tar.gz / zulu-jre21-mac-x64.tar.gz
#        或 zulu-jre21-mac-aarch64.tar.gz / zulu-jre21-mac-x86_64.tar.gz
```

## 数据安全

- **数据库文件权限**: `chmod 600 ocx-worker.db`
- **密钥目录权限**: `chmod 700 keys/`
- **数据目录权限**: `chmod 700 ~/Library/Application Support/macOS OCX/`
- **无网络端口暴露**: SQLite 不监听任何端口
- **一键清除**: 删除 `~/Library/Application Support/macOS OCX/` 即可
- **一键备份**: 复制 `~/Library/Application Support/macOS OCX/ocx-worker.db` 即可

## 重置数据

```bash
rm -rf ~/Library/Application\ Support/macOS\ OCX/ocx-worker.db
rm -rf ~/Library/Application\ Support/macOS\ OCX/Window.applet
# 下次启动会自动重建数据库
```

## 历史版本问题（v2.0.8 已全部修复）

| 版本 | 问题 | 原因 |
|------|------|------|
| v2.0.4 | 闪退 | `CFBundleExecutable=entry.applescript` — macOS 不执行 .applescript 文件 |
| v2.0.5 | 闪退 | `MacOSOCX→osascript` — osascript 无法维持 Cocoa 事件循环 |
| v2.0.6 | 未正常工作 | `entry.applescript` createMenuBar() 括号不匹配 → osacompile 失败 |
| v2.0.7 | 服务启动超时 | App Translocation → .app 只读 → 数据改到 ~/Library/ (部分修复) |
| v2.0.8 | ✅ 已修复 | JRE bin/java 丢失可执行权限 → 启动时 chmod -R u+X 自动修复 |

## ⚠️ 注意事项

- **首次启动慢**: osacompile 需要约1秒编译窗口 + Spring Boot 首次初始化，可能需30-60秒
- **Gatekeeper**: 未签名 app 需要右键 → 打开，首次运行后不再需要
- **串口控制台**: macOS 不支持 Oracle Cloud 串口连接（仅适用于 OCI Linux 实例）
- **WebSSH**: 完全支持
- **JAR 内部 DDL**: `DatabaseGuardService.class` 已改为 SQLite 兼容语法
- **BackupService**: MySQL 特有 `SET` 命令已移除
- **Safari 后备**: 如果 osacompile 编译失败（极少），会自动用 Safari 应用模式打开
