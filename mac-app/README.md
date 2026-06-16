# OCX Worker — macOS Desktop App

将 OCX Worker 打包为 macOS 桌面应用（.app + .dmg）。

## 设计思路

**零 Java 代码改动** — 通过 `compat-bin/` 目录注入 macOS 兼容脚本，覆盖 Linux 专有命令：

```
OCX Worker.app/
  Contents/
    MacOS/
      launch.sh              ← 自定义启动脚本
    Resources/
      app/
        ocx-worker.jar        ← 原样 Spring Boot JAR
      compat-bin/
        chpasswd              ← dscl 替代 chpasswd
        userdel                ← dscl 替代 userdel
        systemctl              ← launchctl 替代 systemctl
        getenforce             ← 返回 "Disabled"（Mac 无 SELinux）
        restorecon             ← 空操作
      runtime/                ← 捆绑 JRE 21（可选）
      com.ocx.worker.plist    ← LaunchDaemon 配置（可选后台服务）
```

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

# 构建
cd mac-app/
chmod +x build-mac-dmg.sh
./build-mac-dmg.sh /path/to/ocx-worker-2.0.1.jar

# 产物
#   dist/OCX Worker.app      ← 拖到 /Applications 即可
#   dist/ocx-worker-2.0.1.dmg ← 分发用磁盘映像
```

## 安装后使用

1. 双击 `.dmg` → 拖到 `/Applications`
2. 首次启动：右键 → 打开（绕过 Gatekeeper）
3. 首次启动会自动检测：
   - **Java 21+** — 未安装会弹窗提示 `brew install openjdk@21`
   - **MySQL** — 未运行会尝试启动 Homebrew MySQL，未安装会弹窗提示
4. 自动创建 `oci_worker` 数据库和 `ocxworker` 用户
5. 浏览器打开 `http://localhost:8818`

## 可选：后台服务模式

```bash
# 注册为开机自启服务
sudo cp /Applications/OCX\ Worker.app/Contents/Resources/com.ocx.worker.plist /Library/LaunchDaemons/
sudo launchctl load -w /Library/LaunchDaemons/com.ocx.worker.plist

# 停止服务
sudo launchctl unload /Library/LaunchDaemons/com.ocx.worker.plist
```

## 数据目录

| 数据 | Linux 路径 | macOS 路径 |
|------|-----------|-----------|
| SSH 密钥 | `./keys` | `~/Library/Application Support/OCX Worker/keys` |
| 日志 | `/var/log/ociworker-bootstrap.log` | `~/Library/Logs/OCX Worker/` |
| 数据库 | MySQL `oci_worker` | MySQL `oci_worker`（同） |

## 注意事项

- **串口控制台功能**：macOS 不支持 Oracle Cloud 串口连接（仅适用于 OCI Linux 实例），Web 控制台可正常使用
- **WebSSH**：文件管理和终端完全支持（JSch 是纯 Java SSH 客户端）
- **Pty4j 终端**：macOS 支持 `/bin/bash` PTY，可正常工作
- **数据库**：`oci_worker` 库名未改（兼容现有数据）
