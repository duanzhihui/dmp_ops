# OpenJDK 运维脚本

基于 oneinstack 架构规范实现的 OpenJDK 自动化运维工具集，支持**多版本共存**、**默认版本切换**、
**包管理器 / tar.gz 双安装模式**，以及 **JVM 侧监控与诊断**。

> 设计说明见 [ops-code-openjdk.md](./ops-code-openjdk.md)

## 与其他组件的差异

OpenJDK 是运行时而非服务，因此本目录**没有** `init.d/*.service`：JDK 无常驻进程、无监听端口、无业务数据目录。
运维重心是 `JAVA_HOME` / `PATH` / `alternatives` 的正确性，以及运行在该 JDK 上的 JVM 进程健康度。

## 支持矩阵

| JDK | 类型 | 状态 | 说明 |
|-----|------|------|------|
| 8 | LTS | 维护中 | ZooKeeper 3.7/3.8、Hadoop 2.x |
| 11 | LTS | 维护中 | ZooKeeper 3.9、Doris FE 2.0、Flink/Spark |
| 17 | LTS | 维护中 | Doris 2.1+、DolphinScheduler 3.2+（默认版本） |
| 18 | 非 LTS | EOL | 仅兼容保留，生产不推荐 |
| 21 | LTS | 维护中 | 新建集群推荐 |

**操作系统**：CentOS/RHEL 7+（含 Alma/Rocky/Anolis/OpenCloudOS/openEuler/Kylin/UOS 等衍生版）、Debian 9+、Ubuntu 16+
**架构**：x86_64、aarch64

## 目录结构

```
openjdk/
├── install.sh              # 安装（交互/静默双模式）
├── uninstall.sh            # 卸载（预览 + 确认 + 占用检测）
├── upgrade.sh              # 同 feature 版本补丁升级
├── switch.sh               # 默认 JDK 切换
├── backup.sh               # 备份 cacerts/安全配置/完整 JDK
├── backup_setup.sh         # 备份策略向导 + cron
├── monitor.sh              # JDK 自检 + JVM 监控
├── options.conf            # 中央配置
├── versions.txt            # 版本清单
├── include/                # 功能模块
│   ├── color.sh check_os.sh check_env.sh download.sh
│   ├── adoptium_repo.sh    # Adoptium 仓库（老系统兜底）
│   ├── openjdk_package.sh  # 包管理器安装
│   ├── openjdk_binary.sh   # tar.gz 安装（Adoptium API）
│   ├── jdk_env.sh          # 环境变量与 alternatives
│   ├── openjdk.sh          # 安装/卸载编排
│   ├── upgrade_jdk.sh      # 升级
│   └── monitor_jdk.sh      # 监控
├── config/
│   ├── openjdk.sh.tpl      # /etc/profile.d/openjdk.sh 模板
│   └── jvm_opts.conf       # 推荐 JVM 参数
├── tools/
│   ├── jdk_list.sh         # 已装 JDK 清单
│   ├── jvm_diag.sh         # JVM 诊断采集
│   └── cacerts_import.sh   # 企业 CA 导入
└── src/                    # 安装包缓存 + adoptium.key
```

## 快速开始

```bash
chmod +x install.sh uninstall.sh upgrade.sh switch.sh backup.sh backup_setup.sh monitor.sh tools/*.sh

# 交互式安装
./install.sh

# 静默安装 OpenJDK 17（包管理器，设为默认）
./install.sh -q --jdk_option 3 --install_method package

# 安装 OpenJDK 21（Adoptium tar.gz），不改变当前默认
./install.sh -q --jdk_option 5 --install_method binary --no_default

# 锁定补丁版本安装
./install.sh -q --jdk_option 5 --install_method binary --jdk_patch_ver 21.0.7+6
```

`jdk_option` 对照：`1`=JDK8 `2`=JDK11 `3`=JDK17 `4`=JDK18 `5`=JDK21

## 常用运维命令

```bash
# 已装版本与默认版本
./switch.sh --list
./tools/jdk_list.sh --all

# 切换默认 JDK
./switch.sh --jdk_option 2

# 状态报告 / 健康检查 / 单进程详情
./monitor.sh --status
./monitor.sh --check
./monitor.sh --jvm 12345

# 补丁升级（同 feature 版本）
./upgrade.sh --jdk_option 3

# 备份
./backup_setup.sh     # 首次配置（含 cron）
./backup.sh           # 立即执行

# 卸载
./uninstall.sh --jdk_option 4 --keep-backup
./uninstall.sh --all -q
```

## 关键机制

### 多版本共存与切换

- 每个 feature 版本独立目录，互不覆盖
- `/usr/local/java`（`jdk_link`）软链指向当前默认 JDK，`JAVA_HOME` 始终指向该软链
- 切换版本只更换软链 + `alternatives --set`，**不需要**修改 `/etc/profile.d/openjdk.sh`
- `alternatives` priority = feature 版本 × 100（21 → 2100，优先级最高）

### 环境变量

统一由 `/etc/profile.d/openjdk.sh` 承载（幂等重写）：

```bash
export JAVA_HOME=/usr/local/java
export CLASSPATH=.            # JDK 8 额外含 tools.jar/dt.jar
export PATH=$JAVA_HOME/bin:$PATH
```

卸载时同时清理 `/etc/profile` 中可能存在的历史残留（兼容 oneinstack `openjdk-18.sh` 的旧写法）。

### 安装方式选择

| 场景 | 推荐 |
|------|------|
| 常规服务器、希望随系统安全更新 | `package` |
| 需要精确锁定补丁版本 | `binary` + `--jdk_patch_ver` |
| 离线/内网环境 | `binary`，预先把 tar.gz 放入 `src/` |
| 老系统（CentOS 7 装 17/21、Ubuntu 16 装 11+、Debian 10+ 装 8） | `package` 会自动切到 Adoptium Temurin |

### 包管理器锁等待

Ubuntu/Debian 开机后 `unattended-upgrades`、`apt.systemd.daily` 常持有 dpkg 锁，直接安装会报
`Could not get lock /var/lib/dpkg/lock-frontend`。脚本会：

- 安装前检测 dpkg/yum 锁占用，打印占用进程并等待其结束（默认最长 600s，`options.conf` 的 `pm_lock_timeout` 可调）
- 对 apt 额外附带 `-o DPkg::Lock::Timeout` 与 `DEBIAN_FRONTEND=noninteractive`
- 等锁超时则明确报错退出，不会误判为"仓库缺包"而去回退 Adoptium

### 升级策略

- `upgrade.sh` **只做同 feature 版本的补丁升级**（17.0.x → 17.0.y）
- 跨大版本（11 → 17）会被拒绝，请用 `install.sh` 装新版本再 `switch.sh` 切换，保证可回退
- 升级前自动备份 `lib/security` + `conf`（binary 模式额外整目录 `cp -a`），失败自动回滚

### 备份内容

JDK 无业务数据，备份对象是配置态资产：

| 内容 | 说明 |
|------|------|
| `cacerts` | 证书库，企业自签 CA 都在这里，重装必丢 |
| `conf` | `java.security` / `java.policy` / `net.properties` |
| `jdk` | 完整 JDK 目录（离线复原用，体积较大） |
| 附带 | `/etc/profile.d/openjdk.sh` 与已装 JDK 清单 |

## 常见问题

**Q: 安装完 `java -version` 还是旧版本？**
A: 当前 shell 未加载新环境。执行 `source /etc/profile.d/openjdk.sh` 或重新登录。
已经在运行的 JVM 进程必须重启才会使用新 JDK。

**Q: 装了多个 JDK，业务用的还是旧的？**
A: 业务通常通过自己的 `JAVA_HOME` 或启动脚本指定 JDK。`switch.sh` 只改系统默认，
业务侧需检查其配置（如 ZooKeeper 的 `java.env`、Doris 的 `fe.conf` 中 `JAVA_HOME`）。

**Q: 卸载时提示有进程占用？**
A: 先停掉这些 JVM 服务，或使用 `--force` 强制卸载（会导致这些进程后续无法重启）。

**Q: 无外网环境如何安装？**
A: 用 `binary` 模式，提前把 Adoptium 的 `OpenJDK*-jdk_*_linux_hotspot_*.tar.gz` 放到 `src/`，
脚本检测到本地已有包会直接复用；`package` 模式则需要内网 yum/apt 源。

**Q: Adoptium 仓库不可用？**
A: `options.conf` 中的 `adoptium_deb_mirror` / `adoptium_rpm_mirror` / `adoptium_file_mirror`
可改为其他镜像；GPG 公钥已随包提供在 `src/adoptium.key`。

**Q: 安装报 `Could not get lock /var/lib/dpkg/lock-frontend`？**
A: 后台自动更新正在占用 apt。脚本已内置等锁逻辑（默认 600s）；若仍超时，可
`ps -ef | grep -E 'apt|dpkg|unattended'` 确认占用进程，等其结束后重试，或调大 `options.conf` 的 `pm_lock_timeout`。
临时禁用后台更新：`systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer`。

**Q: 是否支持 32 位系统？**
A: 不支持，`check_os.sh` 会直接拒绝。

## 组件 JDK 版本兼容参考

| 组件 | 推荐 JDK |
|------|---------|
| ZooKeeper 3.7 / 3.8 | 8 或 11 |
| ZooKeeper 3.9 | 11+ |
| Doris FE 2.0 | 8 或 11 |
| Doris FE 2.1 / 3.x | 17 |
| DolphinScheduler 3.x | 8 或 11（3.2+ 支持 17） |
| SeaTunnel 2.3.x | 8 或 11 |
| Tomcat 9 / 10 / 11 | 8+ / 11+ / 17+ |
