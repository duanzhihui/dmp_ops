# dmp_ops — 数据中台组件运维工具集

一套基于 [oneinstack](https://github.com/oneinstack/oneinstack) 架构规范提炼、面向**数据中台常用开源组件**的 Shell 运维自动化脚本集合。每个组件独立成模块，统一遵循 `install / uninstall / upgrade / backup / monitor` 五段式运维生命周期，支持交互式与静默双模式、单机与集群部署、systemd 托管、多目标备份与告警。

> 仓库在 Windows 端开发提交、Linux 端运行，跨平台协作约定见 [AGENTS.md](./AGENTS.md)。

## 模块总览

| 模块 | 组件 | 支持版本 | 部署模式 | 说明 |
|------|------|---------|---------|------|
| [openjdk](./openjdk) | OpenJDK | 8 / 11 / 17 / 18 / 21 | 多版本共存 | 运行时基础环境，多版本共存、默认版本切换、JVM 监控诊断 |
| [sshtrust](./sshtrust) | SSH 互信 | — | one-way / mesh | 集群部署前置工具，批量建立免密互信（单向 / 全互信网状） |
| [chrony](./chrony) | Chrony 时间同步 | 发行版仓库版本（源码可选 4.6.1） | standalone / cluster | 集群部署前置工具，单机校时或内网 NTP Server + 多客户端时间同步 |
| [mysql](./mysql) | MySQL | 5.7 / 8.0 / 8.4 | 单机 / MGR | 元数据库，含 MGR 单主集群、密码重置、多目标备份 |
| [zookeeper](./zookeeper) | Apache ZooKeeper | 3.7.2 / 3.8.6 / 3.9.5 | standalone / cluster | 分布式协调服务，DolphinScheduler / SeaTunnel 集群依赖 |
| [doris](./doris) | Apache Doris | 2.1.11 / 3.0.8 / 4.1.3 | standalone / integrated / separated | 实时分析型 MPP 数据库，支持存算一体与存算分离 |
| [dolphinscheduler](./dolphinscheduler) | Apache DolphinScheduler | 3.2.2 / 3.3.2 / 3.4.1 | standalone / pseudo-cluster / cluster | 可视化分布式任务调度系统，按角色分布式部署 |
| [seatunnel](./seatunnel) | Apache SeaTunnel | 2.3.x（默认 2.3.13） | local / hybrid / separated | 数据集成引擎（Zeta），支持多节点集群与扩缩容 |
| [oneinstack](./oneinstack) | OneinStack | — | LEMP/LAMP/LNMP/LNMPA/LTMP | Web 一体化环境（Nginx/MySQL/PHP/Tomcat/JDK），作为本仓库架构规范的源头 |
| [template](./template) | 运维代码模板 | — | — | 通用 Shell 运维代码架构规范与 AI 编程提示词模板 |

## 组件依赖关系

```
                 ┌────────────┐
                 │  sshtrust  │  ← 集群部署前置：建立免密互信
                 └─────┬──────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   ┌─────────┐   ┌──────────┐   ┌──────────────┐
   │ openjdk │   │  mysql   │   │  zookeeper   │
   └────┬────┘   └────┬─────┘   └──────┬───────┘
        │             │                │
        │      ┌──────┴───────┐        │
        │      ▼              ▼        │
        │  dolphinscheduler  doris     │
        │  (元数据库)        (元数据库) │
        │      │                       │
        │      └───────────┬───────────┘
        │                  │
        ▼                  ▼
   ┌────────────┐   ┌──────────────────┐
   │ seatunnel  │   │  dolphinscheduler│
   └────────────┘   └──────────────────┘
```

典型数据中台部署顺序：`sshtrust` → `openjdk` → `mysql` / `zookeeper` → `doris` → `dolphinscheduler` / `seatunnel`。

## 统一架构规范

所有模块遵循 [template/ops-code-template.md](./template/ops-code-template.md) 提炼的架构规范，目录结构一致：

```
{module}/
├── install.sh              # 安装主入口（交互/静默双模式）
├── uninstall.sh            # 卸载主入口
├── upgrade.sh              # 升级主入口
├── backup.sh               # 备份执行脚本（由 cron 调用）
├── backup_setup.sh         # 备份策略配置向导（部分模块）
├── monitor.sh              # 健康检查与状态监控
├── options.conf.template   # 中央配置模板（git 跟踪，含 conf_version 版本号）
├── options.conf            # 运行时配置（.gitignore 忽略，由模板生成/升级）
├── versions.txt            # 版本号清单
├── include/                # 功能模块库（color / check_os / download / 业务模块等）
├── init.d/                 # systemd service 单元
├── config/                 # 组件配置文件模板
├── tools/                  # 辅助工具脚本
└── src/                    # 源码包存放目录（运行时填充）
```

### 关键设计

- **options.conf 模板化**：仓库跟踪 `options.conf.template`，运行时由 `include/ensure_options_conf.sh` 引导生成 `options.conf`（含版本号 `conf_version`），升级时自动备份旧配置并按模板重建，避免 git pull 覆盖用户配置。
- **交互 / 静默双模式**：无参数时进入交互菜单；带 `-q/--quiet` 与功能参数时静默执行，便于无人值守部署与 CI 集成。
- **systemd 托管**：组件以 `init.d/*.service` 注册为系统服务，支持 `systemctl start|stop|restart|status` 与开机自启。
- **多目标备份**：支持 local / remote(scp/rsync) / 阿里云 OSS / 腾讯云 COS / AWS S3，可配置 cron 定时与保留策略。
- **健康监控告警**：检测进程、端口、资源使用、集群一致性，可选自动恢复与告警通知（邮件 / Webhook，兼容钉钉/飞书/Slack）。
- **多 OS 兼容**：自动识别 RHEL 系（CentOS/Rocky/Alma/Alibaba Cloud Linux/TencentOS/openEuler/Kylin/UOS 等）、Debian 系、Ubuntu 系，支持 x86_64 与 aarch64。
- **集群部署**：基于 SSH/SCP 多节点部署，要求节点间预配置免密互信（可用 `sshtrust` 模块批量建立）。

## 快速开始

以部署一套 DolphinScheduler + Doris 数据中台为例：

```bash
# 1. 在控制节点与所有目标节点间建立免密互信
cd sshtrust
./sshtrust.sh --add 192.168.1.10 192.168.1.11 192.168.1.12 --quiet --password mypass

# 2. 在所有节点安装 OpenJDK（DolphinScheduler 3.2+ 推荐 17）
cd ../openjdk
./install.sh -q --jdk_option 3 --install_method package

# 3. 部署 MySQL 元数据库
cd ../mysql
./install.sh --mysql_option 0 -q

# 4. 部署 ZooKeeper 集群（3 节点）
cd ../zookeeper
./install.sh --cluster --zk_ver 3.9.5 --myid 1 \
  --nodes "1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"

# 5. 部署 Doris 集群（存算一体）
cd ../doris
bash install.sh --doris_ver 4 --deploy_mode integrated

# 6. 部署 DolphinScheduler 集群
cd ../dolphinscheduler
./install.sh --deploy_mode cluster --ds_ver 3
```

各模块详细用法见对应目录下的 `README.md`。

## 跨平台协作约定

本仓库在 Windows 端开发提交、Linux 端运行，主要约定：

- **可执行位**：Windows 端 `git add` 新建脚本后，用 `bash git-chmod+x.sh` 批量设置可执行位（`100644` → `100755`），Linux 端 pull 后即可直接执行。
- **换行符**：仓库统一 LF，Windows 端 `core.autocrlf=true` 自动转换，不要提交 CRLF 文件。
- **提交信息**：使用中文，简明描述"为什么"做这个改动。

详见 [AGENTS.md](./AGENTS.md) 与 [git-chmod+x.sh](./git-chmod+x.sh)。

## License

Apache License 2.0（部分模块 MIT，见各模块 README）。
