# OCX Worker v1.1.7 — 完整代码解析

> 本目录存放从 `xingchenv2/OCX-worker` 仓库 v1.1.7 Release 的全部资产解析出的代码和资源。

## 目录结构

```
v1.1.7/
├── src-decompiled/com/ociworker/   # CFR 反编译的 Java 源码（144个 .java 文件）
│   ├── OciWorkerApplication.java          # Spring Boot 主入口
│   ├── config/                            # 配置类（拦截器、过滤器、WebSocket等）
│   ├── controller/                        # REST API 控制器（17个）
│   ├── enums/                             # 枚举类
│   ├── exception/                         # 异常处理
│   ├── mapper/                            # MyBatis Mapper 接口
│   ├── model/                             # DTO / Entity / Params / VO
│   ├── service/                           # 业务逻辑层（28个 Service）
│   ├── util/                              # 工具类（含加密、区域目录、SOCKS5等）
│   ├── websocket/                         # WebSocket 日志推送
│   └── webssh/                            # WebSSH 终端管理层
│
├── resources/                      # JAR 内置资源文件
│   ├── application.yml                     # Spring Boot 配置模板
│   ├── build-commit.txt                    # 构建标识（commit hash）
│   ├── logback-spring.xml                  # 日志配置
│   ├── schema.sql                          # 数据库表结构（建库脚本）
│   └── upgrade-oci-*.sql                   # 数据库升级脚本
│
├── maven/                          # Maven 构建元数据
│   ├── pom.xml                             # 完整 Maven POM（含所有依赖及版本）
│   ├── pom.properties                      # GAV 坐标
│   ├── MANIFEST.MF                         # JAR 清单
│   ├── classpath.idx                       # Spring Boot 类路径索引（173个依赖JAR）
│   ├── layers.idx                          # Spring Boot 分层索引
│   └── services/                           # Java SPI 声明
│
├── frontend-dist/                  # Vue 3 编译后的前端（Vite build 产物）
│   ├── index.html                          # SPA 入口
│   ├── favicon.svg                         # 站点图标
│   ├── icons.svg                           # 图标集
│   └── assets/                             # JS/CSS 分块资源
│
├── webssh/                          # WebSSH 子应用
│   ├── index.html                          # WebSSH 终端页面
│   └── static/                             # CSS + JS
│
├── scripts/                        # Release 分发脚本
│   ├── install.sh                          # v2 智能安装器（交互式向导）
│   ├── ocx                                 # 管理 CLI（菜单式）
│   ├── INSTALL_COMMANDS.txt                # 一键安装命令
│   └── SHA256SUMS                          # Release 资产校验
│
└── repo-source/                    # OCX-worker 仓库 v1.1.7 提交快照
    ├── README.md                           # 项目说明
    ├── INSTALLER.md                        # 安装器详细文档
    ├── install.sh                          # 安装脚本
    ├── ocx                                 # 管理 CLI
    └── .gitignore                          # Git 忽略规则
```

## 技术栈

| 层级 | 技术 | 版本 |
|------|------|------|
| 后端框架 | Spring Boot | 3.5.0 |
| JDK | Adoptium Temurin | 21 |
| 数据库 | MySQL | 8.0+ |
| ORM | MyBatis-Plus | 3.5.10.1 |
| OCI SDK | oci-java-sdk | 3.83.0 |
| Telegram Bot | telegrambots | 9.2.0 |
| AI | Spring AI (OpenAI) | 1.0.0-M6 |
| 前端 | Vue 3 + Vite + Ant Design Vue 4 | — |
| SSH | JSch (mwiede fork) | 2.27.7 |
| 工具库 | Hutool | 5.8.38 |

## 关键文件说明

### `resources/application.yml`
默认配置模板。包含服务端口(8818)、WebSSH 超时(120min)、Telegram Bot、OpenAI API、数据库连接等。

### `resources/schema.sql`
数据库完整建表脚本，包含六张核心表：
- `oci_user` — 租户/用户配置
- `oci_create_task` — 抢机任务
- `oci_kv` — 键值存储（系统配置、Tg绑定等）
- `cf_cfg` — Cloudflare DNS 配置
- `oci_login_audit` — 登录审计
- `oci_openai_port_binding` — OpenAI 端口绑定

### `maven/pom.xml`
完整的 Maven 依赖声明，包含 173 个运行时依赖 JAR。主类 `com.ociworker.OciWorkerApplication`。

### `scripts/install.sh`
v2 智能安装器，支持：
- Debian / Ubuntu / CentOS（ARM64 + AMD64）
- 1Panel / 宝塔兼容（使用已有 MySQL）
- Docker 自动装 MySQL 8.0
- 数据库自检（连通性/版本/字符集/DDL权限）
- 配置改坏自动回滚

### `scripts/ocx`
`ocx` 管理 CLI，提供 12 项功能：状态、启停、日志、配置、升级、备份、恢复、Tg 清除、版本、卸载等。

## 注意事项

- **反编译代码仅用于学习参考**，并非原始源码。CFR 反编译可能产生语法差异（如 lambda 表达式、switch 策略等）。
- **Java 包路径 `com.ociworker` 不可更改**，这是编译后的包结构，改名会导致 `ClassNotFoundException`。
- **`oci_worker` 是 MySQL 数据库名**，不可改名（JDBC URL 中硬编码）。
- **`OciOpenaiKeyCipher` 的加密盐值 `ociworker-openai-key-v1:`** 不可更改，否则无法解密已有密钥数据。
