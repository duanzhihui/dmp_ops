# SeaTunnel Ops Code

> 基于 [oneinstack](https://github.com/oneinstack/oneinstack) 运维代码模板，为 **Apache SeaTunnel** 定制的一站式运维自动化脚本集合。
>
> - 适用版本：SeaTunnel 2.3.x（默认 2.3.13）
> - 引擎：SeaTunnel Engine (Zeta)
> - 官网：<https://seatunnel.apache.org/>

---

## 目录

- [功能特性](#功能特性)
- [目录结构](#目录结构)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [部署模式](#部署模式)
- [脚本说明](#脚本说明)
  - [install.sh — 安装](#installsh--安装)
  - [uninstall.sh — 卸载](#uninstallsh--卸载)
  - [upgrade.sh — 升级 / 回滚](#upgradesh--升级--回滚)
  - [cluster.sh — 集群管理](#clustersh--集群管理)
  - [monitor.sh — 监控](#monitorsh--监控)
  - [backup.sh — 备份](#backupsh--备份)
  - [backup_setup.sh — 备份配置向导](#backup_setupsh--备份配置向导)
- [配置文件](#配置文件)
- [Systemd 服务](#systemd-服务)
- [常用示例](#常用示例)
- [注意事项](#注意事项)

---

## 功能特性

- **三种部署模式**：`local`（单机）、`hybrid`（混合集群）、`separated`（分离集群，生产推荐）
- **交互式 + 命令行**：既支持菜单式交互安装，也支持参数化无人值守安装
- **多节点集群部署**：基于 SSH/SCP 一键部署、扩容、缩容
- **配置自动生成**：根据 `options.conf` 自动渲染 `seatunnel.yaml`、`hazelcast.yaml`、`hazelcast-client.yaml`、JVM 参数、`plugin_config`
- **Systemd 托管**：自动注册并启用 `seatunnel` / `seatunnel-master` / `seatunnel-worker` 服务
- **版本升级与回滚**：升级前自动备份配置/连接器，支持一键回滚
- **健康监控**：进程、端口、REST API、运行作业、磁盘、集群成员一致性检查，可选自动恢复与告警（邮件 / Webhook）
- **多目标备份**：本地 / 远程 SCP / 阿里云 OSS / AWS S3，可配置 cron 定时与保留策略
- **多 OS 兼容**：自动识别 RHEL 系（CentOS/Rocky/Alma/Alinux/TencentOS/openEuler/Kylin/UOS 等）、Debian 系（Debian/Deepin/Kali）、Ubuntu 系（Ubuntu/Mint/Elementary），支持 x86_64 与 aarch64
- **Java 环境自检**：自动探测 `JAVA_HOME`，缺失时可选自动安装 OpenJDK 11

---

## 目录结构

```
seatunnel/
├── install.sh              # 安装脚本（交互式 / 命令行）
├── uninstall.sh            # 卸载脚本
├── upgrade.sh              # 升级 / 回滚脚本
├── cluster.sh              # 集群部署与管理
├── monitor.sh              # 监控与健康检查
├── backup.sh               # 备份执行脚本
├── backup_setup.sh         # 备份配置向导（含 cron）
├── options.conf            # 全局配置（路径、模式、集群、JVM、连接器、备份等）
├── versions.txt            # 版本配置（SeaTunnel / Java）
├── ops-code-seatunnel.md   # AI 编程提示词（生成本模块的依据）
├── prompt.md               # 提示词源文件
├── src/                    # 下载的安装包缓存目录（运行时生成）
├── config/                 # 配置文件模板
│   ├── seatunnel.yaml.template
│   ├── hazelcast.yaml.template
│   └── hazelcast-client.yaml.template
├── include/                # 内部功能模块
│   ├── color.sh            # 终端颜色定义
│   ├── check_os.sh         # 操作系统识别
│   ├── check_java.sh       # Java 环境检测与安装
│   ├── download.sh         # 多镜像下载（oneinstack/Apache archive/dlcdn）
│   ├── get_char.sh         # 交互输入辅助
│   ├── seatunnel.sh        # 安装 / 卸载主流程
│   ├── seatunnel_config.sh # 配置文件生成
│   ├── monitor_seatunnel.sh# 监控与告警
│   └── upgrade_seatunnel.sh# 升级与回滚
└── init.d/                 # systemd 服务单元
    ├── seatunnel.service        # hybrid 模式
    ├── seatunnel-master.service # separated 模式 Master
    └── seatunnel-worker.service # separated 模式 Worker
```

---

## 环境要求

| 项目 | 要求 |
|------|------|
| 操作系统 | CentOS/RHEL 7+、Rocky、AlmaLinux、Fedora、Amazon Linux、Alibaba Cloud Linux、TencentOS、openEuler、Anolis、Kylin、UOS、KylinSecOS、Debian 9+、Deepin、Kali、Ubuntu 16+、LinuxMint、Elementary |
| 架构 | x86_64 / aarch64（不支持 32 位） |
| Java | OpenJDK 8 或 11（推荐 11，缺失时脚本可自动安装） |
| 权限 | root（所有脚本均需 root 执行） |
| 网络 | 集群部署需节点间 SSH 免密互通；备份到 OSS/S3 需对应 CLI 工具 |

---

## 快速开始

```bash
# 1. 单机交互式安装（推荐首次使用）
./install.sh

# 2. 命令行无人值守安装 hybrid 集群
./install.sh --deploy_mode hybrid \
             --cluster_name seatunnel \
             --cluster_members 192.168.1.1,192.168.1.2,192.168.1.3 \
             --jvm_heap 4g \
             --connectors connector-fake,connector-console,connector-jdbc \
             -q

# 3. 启动服务
systemctl start seatunnel            # hybrid 模式
# 或 separated 模式：
systemctl start seatunnel-master     # Master 节点
systemctl start seatunnel-worker     # Worker 节点

# 4. 查看状态
./monitor.sh --status
```

---

## 部署模式

| 模式 | 说明 | 服务单元 | 适用场景 |
|------|------|---------|---------|
| `local` | 单机本地模式，每个任务启动独立进程，任务完成后退出 | 无（手动 `seatunnel.sh --config xxx -e local`） | 开发测试、快速验证 |
| `hybrid` | 混合集群模式，Master 与 Worker 在同一进程，所有节点均可运行作业并参与选举 | `seatunnel.service` | 小规模集群 |
| `separated` | 分离集群模式，Master 负责调度与 REST API，Worker 负责执行 | `seatunnel-master.service` / `seatunnel-worker.service` | **生产推荐** |

默认模式由 `options.conf` 中的 `deploy_mode` 决定（默认 `hybrid`），可通过 `--deploy_mode` 参数覆盖。

---

## 脚本说明

### install.sh — 安装

安装 SeaTunnel 引擎、连接器插件、配置文件、systemd 服务。

```text
Usage: install.sh [OPTIONS]

Options:
  -h, --help                  显示帮助
  -v, --version               显示脚本版本
  -q, --quiet                 静默模式，跳过确认
  --deploy_mode MODE          部署模式: local, hybrid, separated (默认: hybrid)
  --cluster_name NAME         集群名称 (默认: seatunnel)
  --cluster_members IPs       集群成员，逗号分隔 (默认: 127.0.0.1)
  --node_role ROLE            separated 模式节点角色: master, worker
  --connectors LIST           待安装连接器，逗号分隔
  --jvm_heap SIZE             JVM 堆大小 (默认: 2g)
```

安装流程（见 `include/seatunnel.sh`）：

1. 幂等检查（已安装则跳过）
2. Java 环境检测 / 自动安装
3. 多镜像下载 SeaTunnel 二进制包
4. 解压到 `${seatunnel_install_dir}`（默认 `/opt/seatunnel`）
5. 生成 `plugin_config` 并执行 `bin/install-plugin.sh` 安装连接器
6. 创建 `seatunnel` 系统用户
7. 生成全部配置文件（`seatunnel.yaml` / `hazelcast.yaml` / `hazelcast-client.yaml` / JVM 参数 / `plugin_config`）
8. 创建 data / log / checkpoint / dump / run 目录并设置属主
9. 写入 `/etc/profile.d/seatunnel.sh` 环境变量
10. 按部署模式注册 systemd 服务并 enable
11. 校验安装并输出摘要

### uninstall.sh — 卸载

```text
Usage: uninstall.sh [OPTIONS]
  -h, --help       显示帮助
  -q, --quiet      静默模式，跳过确认
  --keep_data      保留数据目录（重命名备份而非删除）
```

执行步骤：停止服务 → 移除 systemd 单元 → 备份/删除数据目录 → 删除安装目录 → 清理环境变量。

### upgrade.sh — 升级 / 回滚

```text
Usage: upgrade.sh [OPTIONS]
  -h, --help              显示帮助
  -v, --version VERSION   升级到指定版本
  --rollback DIR          从备份目录回滚
```

升级流程（见 `include/upgrade_seatunnel.sh`）：

1. 检测当前版本（从 `lib/seatunnel-*.jar` 解析）
2. 获取最新版本（优先从官网抓取，回退到 `versions.txt`）
3. 版本校验（跨大版本升级会提示兼容性风险）
4. 升级前备份 `config` / `connectors` / `plugins` 到 `/tmp/seatunnel_upgrade_backup_<时间戳>`
5. 停止服务
6. 下载新版本并替换安装目录
7. 恢复用户配置（保留新版本默认配置，仅覆盖用户修改过的文件）
8. 重置权限并启动服务
9. 失败时自动回滚并重启

回滚示例：

```bash
./upgrade.sh --rollback /tmp/seatunnel_upgrade_backup_20260806103000
```

### cluster.sh — 集群管理

基于 SSH/SCP 进行多节点部署与维护，要求节点间已配置 SSH 免密。

```text
Usage: cluster.sh [COMMAND] [OPTIONS]

Commands:
  deploy-hybrid      部署 hybrid 模式集群
  deploy-separated   部署 separated 模式集群
  add-node           向集群添加节点
  remove-node        从集群移除节点
  scale-workers      Worker 扩缩容（提示使用 add-node/remove-node）
  status             查看集群状态

Options:
  -h, --help         显示帮助
  --nodes IPs        节点 IP 列表（逗号分隔）
  --role ROLE        节点角色: master, worker
  --masters IPs      separated 模式 Master 节点列表
  --workers IPs      separated 模式 Worker 节点列表
```

工作方式：将整个 `seatunnel` 目录通过 SCP 推送到目标节点 `/tmp/seatunnel_deploy/`，再远程以 `-q` 静默模式调用 `install.sh`，并同步更新所有节点 `options.conf` 中的 `cluster_members`。

### monitor.sh — 监控

```text
Usage: monitor.sh [OPTIONS]
  -h, --help        显示帮助
  --status          完整状态报告（默认）
  --check           健康检查
  --jobs            列出运行中的作业
  --cluster         集群健康状态
  --auto-recover    检测到故障时自动重启服务
```

监控项（见 `include/monitor_seatunnel.sh`）：

- **进程检查**：`pgrep` 检测 SeaTunnel 进程，可选自动 `systemctl restart`
- **端口检查**：Hazelcast 端口（默认 5801）监听状态
- **REST API**：调用 `/hazelcast/rest/cluster` 获取集群成员数
- **运行作业**：调用 `/hazelcast/rest/maps/running-jobs` 列出作业
- **Java 进程资源**：内存（RSS/%）、CPU、启动时间、线程数
- **磁盘使用**：安装目录 / 日志目录 / checkpoint 目录，超阈值告警（默认 85%）
- **集群一致性**：期望成员数与实际成员数比对
- **告警通知**：写日志 + 邮件（`alert_email`）+ Webhook（`webhook_url`，兼容钉钉/飞书/Slack）

### backup.sh — 备份

按 `options.conf` 中的 `backup_content` 与 `backup_destination` 执行备份，可被 `backup_setup.sh` 注册为 cron 任务。

| 备份内容 | 说明 |
|---------|------|
| `config` | 配置文件目录 |
| `connectors` | 连接器插件目录 |
| `jobs` | 作业文件目录 |
| `full` | 全量备份（config + connectors + plugins + jobs） |

| 备份目标 | 依赖工具 |
|---------|---------|
| `local` | 无 |
| `remote` | `scp`（需 SSH 免密） |
| `oss` | `ossutil`（阿里云 OSS） |
| `s3` | `aws` CLI |

备份完成后按 `expired_days`（默认 7 天）清理过期文件。

### backup_setup.sh — 备份配置向导

交互式引导配置备份目标、内容、目录、保留天数、cron 周期，并自动写入 `options.conf` 与 crontab。会主动测试 SSH / OSS / S3 连通性。

---

## 配置文件

### options.conf

全局配置入口，所有脚本通过 `. ./options.conf` 加载。主要配置项：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `mirror_link` | `https://mirrors.oneinstack.com/oneinstack/src` | 下载镜像源 |
| `maven_mirror` | `https://maven.aliyun.com/repository/public` | Maven 镜像源，加速连接器插件下载（留空则用 Maven 中央仓库） |
| `seatunnel_install_dir` | `/opt/seatunnel` | 安装目录 |
| `seatunnel_data_dir` | `/opt/seatunnel/data` | 数据目录 |
| `seatunnel_log_dir` | `/opt/seatunnel/logs` | 日志目录 |
| `seatunnel_checkpoint_dir` | `/opt/seatunnel/checkpoint` | Checkpoint 目录 |
| `run_user` / `run_group` | `seatunnel` | 运行用户/组 |
| `deploy_mode` | `hybrid` | 部署模式 |
| `cluster_name` | `seatunnel` | 集群名称 |
| `cluster_members` | `127.0.0.1` | 集群成员 IP（逗号分隔） |
| `node_role` | `master` | separated 模式节点角色 |
| `hazelcast_port` | `5801` | Hazelcast 通信端口 |
| `jvm_heap_size` | `2g` | JVM 堆大小 |
| `jvm_metaspace_size` | `256m` | Metaspace 大小 |
| `connectors` | `connector-fake,connector-console` | 待安装连接器列表 |
| `checkpoint_interval` | `10000` | Checkpoint 间隔（ms） |
| `checkpoint_timeout` | `60000` | Checkpoint 超时（ms） |
| `checkpoint_max_retained` | `3` | Checkpoint 保留份数 |
| `checkpoint_storage_type` | `localfile` | Checkpoint 存储：`localfile` / `hdfs` |
| `imap_backup_count` | `1` | IMAP 备份数 |
| `history_job_expire_minutes` | `1440` | 历史作业过期时间（分钟） |
| `job_schedule_strategy` | `REJECT` | 调度策略：`WAIT` / `REJECT` |
| `backup_dir` | `/data/backup/seatunnel` | 备份目录 |
| `expired_days` | `7` | 备份保留天数 |
| `backup_destination` | `local` | 备份目标（逗号分隔） |
| `backup_content` | `config,connectors` | 备份内容（逗号分隔） |
| `alert_email` | （空） | 告警邮件收件人 |
| `webhook_url` | （空） | 告警 Webhook |
| `seatunnel_installed` | （空） | 安装时自动填充 |
| `java_home` | （空） | 安装时自动填充 |

### versions.txt

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `seatunnel_ver` | `2.3.13` | SeaTunnel 版本 |
| `java_required_ver` | `11` | 推荐 Java 版本 |
| `java_min_ver` | `8` | 最低 Java 版本 |
| `java_max_ver` | `11` | 最高支持 Java 版本 |

### config/*.template

提供 `seatunnel.yaml` / `hazelcast.yaml` / `hazelcast-client.yaml` 的占位符模板，供参考。实际安装时由 `include/seatunnel_config.sh` 根据当前配置动态生成最终文件到 `${seatunnel_install_dir}/config/`。

---

## Systemd 服务

| 服务单元 | 部署模式 | 启动命令 |
|---------|---------|---------|
| `seatunnel.service` | hybrid | `seatunnel-cluster.sh -d` |
| `seatunnel-master.service` | separated (master) | `seatunnel-cluster.sh -d -r master` |
| `seatunnel-worker.service` | separated (worker) | `seatunnel-cluster.sh -d -r worker` |

服务特性：

- `Type=forking`，以 `seatunnel` 用户运行
- `Restart=on-failure`，`RestartSec=10`
- `LimitNOFILE=1000000`、`LimitNPROC=1000000`、`LimitCORE=infinity`
- 安装时自动替换 `SEATUNNEL_HOME` 与 `JAVA_HOME` 占位符

常用管理命令：

```bash
systemctl start|stop|restart|status seatunnel
systemctl enable|disable seatunnel
journalctl -u seatunnel -f
```

---

## 常用示例

### 单机 local 模式

```bash
./install.sh --deploy_mode local -q
# 运行作业
/opt/seatunnel/bin/seatunnel.sh --config /path/to/job.conf -e local
```

### hybrid 三节点集群

```bash
# 在任一节点执行
./cluster.sh deploy-hybrid --nodes 192.168.1.1,192.168.1.2,192.168.1.3

# 各节点启动
ssh 192.168.1.1 'systemctl start seatunnel'
ssh 192.168.1.2 'systemctl start seatunnel'
ssh 192.168.1.3 'systemctl start seatunnel'

# 提交作业
/opt/seatunnel/bin/seatunnel.sh --config /path/to/job.conf
```

### separated 生产集群

```bash
./cluster.sh deploy-separated \
  --masters 192.168.1.1,192.168.1.2 \
  --workers 192.168.1.3,192.168.1.4,192.168.1.5

# Master 节点
ssh 192.168.1.1 'systemctl start seatunnel-master'
# Worker 节点
ssh 192.168.1.3 'systemctl start seatunnel-worker'
```

### 扩容 / 缩容

```bash
# 增加 worker
./cluster.sh add-node --nodes 192.168.1.6 --role worker

# 移除节点
./cluster.sh remove-node --nodes 192.168.1.6
```

### 升级到指定版本

```bash
./upgrade.sh -v 2.3.14
# 升级失败后回滚
./upgrade.sh --rollback /tmp/seatunnel_upgrade_backup_xxx
```

### 配置定时备份到 OSS

```bash
./backup_setup.sh
# 按向导选择: Local + OSS -> 填写 bucket/endpoint -> 选择备份内容 -> 选择 cron 周期
# 手动触发一次
./backup.sh
```

### 监控与自动恢复

```bash
./monitor.sh --status              # 完整状态
./monitor.sh --check               # 健康检查
./monitor.sh --jobs                # 运行作业
./monitor.sh --cluster             # 集群一致性
./monitor.sh --check --auto-recover # 健康检查 + 故障自动重启
```

---

## 注意事项

1. **必须 root 执行**：所有脚本开头均校验 `id -u == 0`。
2. **集群部署需 SSH 免密**：`cluster.sh` 通过 `ssh -o StrictHostKeyChecking=no` 远程执行，请提前配置好密钥（`ssh-copy-id`）。
3. **下载源**：优先 `mirrors.oneinstack.com`，失败回退到 Apache archive 与 dlcdn；网络受限环境可手动将 `apache-seatunnel-<version>-bin.tar.gz` 放入 `src/` 目录。
4. **连接器插件下载加速**：`bin/install-plugin.sh` 默认通过 `mvnw` 从 `https://repo.maven.apache.org` 下载连接器 jar，国内访问极慢。本脚本在执行 `install-plugin.sh` 前会根据 `options.conf` 中的 `maven_mirror` 自动生成 `~/.m2/settings.xml`（已存在则备份），让 `mvnw` 走国内镜像（默认阿里云）。如需更换镜像，修改 `maven_mirror` 即可（华为云/腾讯云/网易等，见 `options.conf` 注释）；留空则恢复使用 Maven 中央仓库。后续手动执行 `install-plugin.sh` 增装连接器时同样会走该镜像。
5. **跨大版本升级**：脚本会告警兼容性风险，请先阅读官方 Release Notes 并对运行中作业做好 savepoint。
5. **数据安全**：卸载默认会重命名备份数据目录（`<data_dir>_YYYYMMDDHHMM`），如需彻底删除请显式确认；`--keep_data` 则完全保留。
6. **配置回写**：安装/备份向导会通过 `sed -i` 修改 `options.conf`，请勿在脚本运行期间手工编辑该文件。
7. **端口规划**：Hazelcast 端口默认 5801，集群节点间需互通；REST API 复用该端口。
8. **Java 版本**：推荐 OpenJDK 11；若检测到 Java 8 也可运行，但低于 8 会被拒绝。
9. **告警配置**：`alert_email` 依赖系统 `mail` 命令，`webhook_url` 兼容钉钉/飞书/Slack 的 JSON `{text: ...}` 格式。
10. **Maven settings.xml 备份**：安装时若 `~/.m2/settings.xml` 已存在，会先备份为 `settings.xml.bak.<时间戳>` 再覆盖为本脚本生成的镜像配置；如需保留原有自定义配置，请在安装后合并备份文件。

---

## 相关文档

- SeaTunnel 官网：<https://seatunnel.apache.org/>
- 本地部署：<https://seatunnel.apache.org/zh-CN/docs/2.3.13/getting-started/locally/deployment>
- Hybrid 集群：<https://seatunnel.apache.org/zh-CN/docs/2.3.13/engines/zeta/hybrid-cluster-deployment/>
- Separated 集群：<https://seatunnel.apache.org/zh-CN/docs/2.3.13/engines/zeta/separated-cluster-deployment/>
- 版本升级：<https://seatunnel.apache.org/zh-CN/docs/2.3.13/engines/zeta/version-upgrade>
- oneinstack 模板：<https://github.com/oneinstack/oneinstack>
