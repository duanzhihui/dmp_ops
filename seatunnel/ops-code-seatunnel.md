# SeaTunnel 运维代码 — AI 编程提示词

> 本文档基于 oneinstack 项目的运维代码模板，为 **Apache SeaTunnel** 定制的 AI 编程提示词。
> 适用版本：SeaTunnel 2.3.x（2.3.13）

---

# 角色

你是一位资深的 Linux 运维自动化工程师，精通 Bash Shell 编程和 systemd 服务管理。
你的任务是为开源软件 **Apache SeaTunnel** 编写一套完整的运维自动化脚本。

# 软件概述

**Apache SeaTunnel** 是一个高性能、分布式的数据集成平台，支持海量数据的实时同步。
- **官网**: https://seatunnel.apache.org/
- **引擎**: SeaTunnel Engine (Zeta) — 自研高性能引擎
- **架构**: 支持 Local 模式、混合集群模式（Hybrid）、分离集群模式（Separated）

# 输入参数

## 基础参数

| 参数 | 值 |
|------|-----|
| SOFTWARE_NAME | SeaTunnel |
| SOFTWARE_VERSION | 2.3.13 |
| INSTALL_DIR | /opt/seatunnel |
| DATA_DIR | /opt/seatunnel/data |
| LOG_DIR | /opt/seatunnel/logs |
| RUN_USER | seatunnel |
| DOWNLOAD_URL | https://archive.apache.org/dist/seatunnel/{version}/apache-seatunnel-{version}-bin.tar.gz |
| INSTALL_METHOD | binary（二进制包） |
| JAVA_VERSION | Java 8 或 11 |

## 部署模式

SeaTunnel Engine (Zeta) 支持三种部署模式：

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| **local** | 单机本地模式，每个任务启动独立进程，任务完成后退出 | 快速验证、开发测试 |
| **hybrid** | 混合集群模式，Master 和 Worker 在同一进程，所有节点可运行作业并参与选举 | 小规模集群 |
| **separated** | 分离集群模式，Master 和 Worker 分离，Master 负责调度，Worker 负责执行 | **生产推荐** |

## 服务端口

| 服务 | 默认端口 | 说明 |
|------|---------|------|
| Hazelcast | 5801 | 集群通信端口 |
| REST API | 5801 | 作业提交和管理 |
| Metrics | 5802 | 监控指标（可选） |

## 关键配置文件

| 文件 | 路径 | 说明 |
|------|------|------|
| seatunnel.yaml | config/seatunnel.yaml | 引擎主配置（slot、checkpoint、imap 等） |
| hazelcast.yaml | config/hazelcast.yaml | 集群网络配置（节点发现、端口） |
| hazelcast-client.yaml | config/hazelcast-client.yaml | 客户端配置 |
| jvm_options | config/jvm_options | 混合模式 JVM 参数 |
| jvm_master_options | config/jvm_master_options | 分离模式 Master JVM 参数 |
| jvm_worker_options | config/jvm_worker_options | 分离模式 Worker JVM 参数 |
| jvm_client_options | config/jvm_client_options | 客户端 JVM 参数 |
| plugin_config | config/plugin_config | 连接器插件配置 |

## 关键目录结构

```
/opt/seatunnel/
├── bin/                    # 可执行脚本
│   ├── seatunnel.sh        #   作业提交脚本
│   ├── seatunnel-cluster.sh#   集群启动脚本
│   ├── install-plugin.sh   #   插件安装脚本
│   └── stop-seatunnel-cluster.sh  # 集群停止脚本
├── config/                 # 配置文件目录
│   ├── seatunnel.yaml      #   引擎配置
│   ├── hazelcast.yaml      #   集群配置
│   ├── hazelcast-client.yaml # 客户端配置
│   ├── jvm_options         #   JVM 参数
│   └── plugin_config       #   插件列表
├── connectors/             # 连接器插件目录
├── lib/                    # 核心依赖库
├── logs/                   # 日志目录
├── plugins/                # 插件目录
└── licenses/               # 许可证文件
```

# 输出要求

请生成以下文件，每个文件的代码必须完整、可直接运行：

## 文件清单

### 1. `options.conf` — 中央配置文件

**功能**: 存储所有可配置参数
**要求**:
- 安装路径、数据目录、日志目录、运行用户
- 部署模式配置：`deploy_mode`（local/hybrid/separated）
- 集群配置：`cluster_name`、`cluster_members`（逗号分隔的 IP 列表）
- JVM 参数：`jvm_heap_size`（如 2g）
- 连接器配置：`connectors`（需要安装的连接器列表）
- 备份相关字段：backup_dir, expired_days, backup_destination, backup_content
- 使用 `key=value` 格式，用注释分组

### 2. `versions.txt` — 版本号清单

**功能**: 管理 SeaTunnel 及依赖的版本号
**要求**:
- 与 options.conf 分离，便于独立更新
- 命名格式：`seatunnel_ver=2.3.13`
- 包含 Java 版本要求

### 3. `include/color.sh` — 颜色定义

**功能**: 定义终端彩色输出变量
**要求**:
- 提供 `CSUCCESS`(绿)、`CFAILURE`(红)、`CWARNING`(黄)、`CMSG`(青)、`CEND`(重置)
- 兼容不同终端

### 4. `include/check_os.sh` — 操作系统检测

**功能**: 检测操作系统类型、版本、架构
**要求**:
- 支持 CentOS/RHEL 7+, Debian 9+, Ubuntu 16+, 及其衍生版
- 输出变量: `Platform`, `Family`(rhel/debian/ubuntu), `PM`(yum/apt-get), `ARCH`, `THREAD`
- 检测 ARM/x86_64 架构
- 检测 32/64 位

### 5. `include/check_java.sh` — Java 环境检测

**功能**: 检测和验证 Java 环境
**要求**:
- `Check_Java()` 函数：检测 JAVA_HOME 是否设置
- `Verify_Java_Version()` 函数：验证 Java 版本（需要 8 或 11）
- `Install_Java()` 函数：如果未安装，提示或自动安装 OpenJDK
- 设置 JAVA_HOME 环境变量

### 6. `include/download.sh` — 下载函数

**功能**: 提供可靠的文件下载能力
**要求**:
- `Download_src()` 函数，通过 `src_url` 变量传入 URL
- 多源容错：Apache 官方 → 镜像站
- 检测下载失败（文件 <1KB 且含 HTML 标签则视为错误页）
- 支持断点续传 (wget -c)
- 失败时提示用户手动下载路径

### 7. `include/seatunnel.sh` — 安装/卸载模块

**功能**: SeaTunnel 的安装和卸载逻辑
**要求**:
- `Install_SeaTunnel()` 函数，完整安装流程：
  1. 检测是否已安装（幂等）
  2. 检测 Java 环境
  3. 下载安装包 apache-seatunnel-${ver}-bin.tar.gz
  4. 解压到安装目录
  5. 安装连接器插件（调用 bin/install-plugin.sh）
  6. 创建系统用户 seatunnel
  7. 生成配置文件（seatunnel.yaml、hazelcast.yaml）
  8. 设置目录权限
  9. 配置环境变量 SEATUNNEL_HOME
  10. 根据部署模式复制并注册 systemd service
  11. 验证安装结果
- `Uninstall_SeaTunnel()` 函数

### 8. `include/seatunnel_config.sh` — 配置生成模块

**功能**: 生成 SeaTunnel 配置文件
**要求**:
- `Generate_Seatunnel_Yaml()` 函数：生成 seatunnel.yaml
  - 配置 slot 数量（基于 CPU 核心数）
  - 配置 checkpoint 存储（本地或 HDFS）
  - 配置 imap 备份数
  - 配置历史作业过期时间
- `Generate_Hazelcast_Yaml()` 函数：生成 hazelcast.yaml
  - 配置集群名称
  - 配置网络端口
  - 配置节点发现（TCP-IP 模式）
  - 配置集群成员列表
- `Generate_Hazelcast_Client_Yaml()` 函数：生成 hazelcast-client.yaml
- `Generate_JVM_Options()` 函数：生成 JVM 参数文件

### 9. `include/upgrade_seatunnel.sh` — 升级模块

**功能**: SeaTunnel 的版本升级逻辑
**要求**:
- `Upgrade_SeaTunnel()` 函数：
  1. 检测当前已安装版本（从 lib 目录的 jar 包名解析）
  2. 获取最新可用版本（curl Apache 下载页面）
  3. 提示用户输入目标版本（有默认值）
  4. 校验版本号（新旧不能相同、主版本须一致 2.3.x）
  5. 升级前备份（config/、connectors/、plugins/ 目录）
  6. 保护运行中的作业（提示用户先 savepoint）
  7. 停服务
  8. 下载新版本并解压
  9. 恢复配置文件
  10. 启服务
  11. 验证升级结果

### 10. `include/monitor_seatunnel.sh` — 监控模块

**功能**: 健康检查与状态监控
**要求**:
- `Check_Process()` — 检查 SeaTunnel Engine 进程是否存活
- `Check_Port()` — 检查 5801 端口是否监听
- `Check_REST_API()` — 调用 REST API 检查集群状态
  - GET http://localhost:5801/hazelcast/rest/cluster 获取集群信息
  - GET http://localhost:5801/hazelcast/rest/maps/running-jobs 获取运行中作业
- `Check_Java_Process()` — 检查 Java 进程内存使用
- `Check_Disk()` — 检查磁盘空间（日志目录、checkpoint 目录）
- `Check_Cluster_Health()` — 检查集群节点健康状态
- `Send_Alert()` — 告警通知（邮件 + Webhook）
- `Monitor_Status()` — 输出状态报告（版本、运行时间、作业数、资源占用）

### 11. `install.sh` — 安装主入口

**功能**: 安装主控脚本
**要求**:
- 文件头：root 检查、source 配置和公共库
- getopt 参数解析，支持：
  - `--help`, `-h`: 显示帮助
  - `--version`, `-v`: 显示版本
  - `--quiet`, `-q`: 静默模式
  - `--deploy_mode [local|hybrid|separated]`: 指定部署模式
  - `--cluster_name [name]`: 指定集群名称
  - `--cluster_members [ip1,ip2,...]`: 指定集群成员
  - `--connectors [list]`: 指定要安装的连接器
- 无参数时显示交互式菜单（选择部署模式、配置集群）
- 有参数时静默执行
- 安装完成后显示摘要信息（版本、路径、端口、部署模式）

### 12. `uninstall.sh` — 卸载主入口

**功能**: 卸载主控脚本
**要求**:
- getopt 参数解析，支持 `--quiet`, `--keep_data`
- 卸载前显示将删除的文件列表（Print_SeaTunnel 函数）
- 用户确认后执行（--quiet 跳过确认）
- 数据目录重命名备份而非直接删除
- 清理 /etc/profile.d/seatunnel.sh 环境变量
- 清理 systemd service 文件

### 13. `upgrade.sh` — 升级主入口

**功能**: 升级主控脚本
**要求**:
- getopt 参数解析，`--version [x.x.x]`
- 无参数时显示当前版本和最新版本，提示输入目标版本
- 升级前提示用户保存运行中的作业
- source upgrade 模块并调用

### 14. `backup.sh` — 备份执行脚本

**功能**: 由 cron 调用的备份执行器
**要求**:
- 从 options.conf 读取备份配置
- 备份内容：
  - config/ 目录（配置文件）
  - connectors/ 目录（连接器插件）
  - 作业配置文件
- 支持多种备份目标：local, remote, oss, s3
- 过期清理：按 expired_days 删除旧备份
- 文件命名格式：`seatunnel_backup_{date}_{time}.tgz`

### 15. `backup_setup.sh` — 备份配置向导

**功能**: 交互式配置备份策略
**要求**:
- 交互式选择备份目标（本地/远程/云存储）
- 交互式选择备份内容
- 配置云存储凭证并测试连通性
- 将配置写入 options.conf
- 设置 cron 定时任务

### 16. `monitor.sh` — 监控主入口

**功能**: 监控主控脚本
**要求**:
- 可由 cron 定时调用或手动执行
- 支持参数：
  - `--status`: 显示状态报告
  - `--check`: 执行健康检查
  - `--jobs`: 显示运行中的作业列表
  - `--cluster`: 显示集群节点状态
- 输出到日志文件 + 终端
- 异常时触发告警

### 17. `cluster.sh` — 集群管理脚本

**功能**: 集群部署和管理
**要求**:
- `Deploy_Hybrid_Cluster()` — 部署混合模式集群
- `Deploy_Separated_Cluster()` — 部署分离模式集群
- `Add_Node()` — 添加集群节点
- `Remove_Node()` — 移除集群节点
- `Scale_Workers()` — 扩缩 Worker 节点
- 支持 SSH 批量部署到多节点

### 18. `init.d/seatunnel.service` — 混合模式 systemd 服务文件

**功能**: 混合模式 systemd unit 定义
**要求**:
```ini
[Unit]
Description=Apache SeaTunnel Engine (Hybrid Mode)
After=network.target

[Service]
Type=forking
User=seatunnel
Group=seatunnel
Environment=SEATUNNEL_HOME=/opt/seatunnel
Environment=JAVA_HOME=/usr/lib/jvm/java
ExecStart=/opt/seatunnel/bin/seatunnel-cluster.sh -d
ExecStop=/opt/seatunnel/bin/stop-seatunnel-cluster.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=1000000
LimitNPROC=1000000

[Install]
WantedBy=multi-user.target
```

### 19. `init.d/seatunnel-master.service` — 分离模式 Master systemd 服务文件

**功能**: 分离模式 Master systemd unit 定义
**要求**:
```ini
[Unit]
Description=Apache SeaTunnel Engine Master
After=network.target

[Service]
Type=forking
User=seatunnel
Group=seatunnel
Environment=SEATUNNEL_HOME=/opt/seatunnel
Environment=JAVA_HOME=/usr/lib/jvm/java
ExecStart=/opt/seatunnel/bin/seatunnel-cluster.sh -d -r master
ExecStop=/opt/seatunnel/bin/stop-seatunnel-cluster.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=1000000
LimitNPROC=1000000

[Install]
WantedBy=multi-user.target
```

### 20. `init.d/seatunnel-worker.service` — 分离模式 Worker systemd 服务文件

**功能**: 分离模式 Worker systemd unit 定义
**要求**:
```ini
[Unit]
Description=Apache SeaTunnel Engine Worker
After=network.target seatunnel-master.service

[Service]
Type=forking
User=seatunnel
Group=seatunnel
Environment=SEATUNNEL_HOME=/opt/seatunnel
Environment=JAVA_HOME=/usr/lib/jvm/java
ExecStart=/opt/seatunnel/bin/seatunnel-cluster.sh -d -r worker
ExecStop=/opt/seatunnel/bin/stop-seatunnel-cluster.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=1000000
LimitNPROC=1000000

[Install]
WantedBy=multi-user.target
```

### 21. `config/seatunnel.yaml.template` — 引擎配置模板

**功能**: SeaTunnel Engine 配置模板
**要求**:
```yaml
seatunnel:
  engine:
    backup-count: 1
    queue-type: blockingqueue
    slot-service:
      dynamic-slot: true
    checkpoint:
      interval: 10000
      timeout: 60000
      storage:
        type: localfile
        max-retained: 3
        plugin-config:
          namespace: /opt/seatunnel/checkpoint
    history-job-expire-minutes: 1440
    classloader-cache-mode: true
    job-schedule-strategy: RANDOM
```

### 22. `config/hazelcast.yaml.template` — 集群配置模板

**功能**: Hazelcast 集群配置模板
**要求**:
```yaml
hazelcast:
  cluster-name: seatunnel
  network:
    rest-api:
      enabled: true
      endpoint-groups:
        CLUSTER_READ:
          enabled: true
        DATA:
          enabled: true
    join:
      tcp-ip:
        enabled: true
        member-list:
          - 127.0.0.1
    port:
      auto-increment: false
      port: 5801
  properties:
    hazelcast.invocation.max.retry.count: 20
    hazelcast.tcp.join.port.try.count: 30
    hazelcast.logging.type: log4j2
    hazelcast.operation.generic.thread.count: 50
```

# 代码规范约束

1. **Shell 版本**: #!/bin/bash，兼容 Bash 4.0+
2. **缩进**: 2 空格
3. **变量命名**: 小写 + 下划线（如 `install_dir`），常量大写（如 `THREAD`）
4. **函数命名**: 大驼峰（如 `Install_SeaTunnel`, `Upgrade_SeaTunnel`）
5. **幂等性**: 所有安装操作必须支持重复执行（已安装则跳过）
6. **错误处理**: 关键操作失败时 `kill -9 $$; exit 1`，数据操作前必须备份
7. **日志输出**: 使用 color.sh 的颜色变量（CSUCCESS/CFAILURE/CWARNING/CMSG）
8. **PATH 设置**: 脚本开头固定 `export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin`
9. **root 检查**: `[ $(id -u) != "0" ] && { echo "Error: must be root"; exit 1; }`
10. **工作目录**: 使用 `pushd/popd` 管理目录切换
11. **临时文件**: 操作完成后及时清理
12. **配置分离**: 所有可变参数放 options.conf，版本号放 versions.txt，代码中只引用变量
13. **安全**: service 使用非 root 用户 seatunnel 运行
14. **兼容性**: 支持 x86_64 和 aarch64 架构，支持 RHEL/Debian/Ubuntu 系列
15. **Java 依赖**: 安装前必须检测 Java 8 或 11 环境

# SeaTunnel 特有注意事项

## 1. 连接器插件管理

```bash
# 安装所有连接器
sh bin/install-plugin.sh ${version}

# 或只安装指定连接器（编辑 config/plugin_config）
--seatunnel-connectors--
connector-fake
connector-console
connector-jdbc
connector-kafka
--end--
```

## 2. 部署模式启动命令

```bash
# Local 模式（单次作业）
$SEATUNNEL_HOME/bin/seatunnel.sh --config job.conf -e local

# Hybrid 模式（集群）
$SEATUNNEL_HOME/bin/seatunnel-cluster.sh -d

# Separated 模式
# Master 节点
$SEATUNNEL_HOME/bin/seatunnel-cluster.sh -d -r master
# Worker 节点
$SEATUNNEL_HOME/bin/seatunnel-cluster.sh -d -r worker
```

## 3. 作业提交和管理

```bash
# 提交作业到集群
$SEATUNNEL_HOME/bin/seatunnel.sh --config job.conf

# 查看作业列表
$SEATUNNEL_HOME/bin/seatunnel.sh -l

# 取消作业
$SEATUNNEL_HOME/bin/seatunnel.sh -can <job_id>

# 创建 savepoint
$SEATUNNEL_HOME/bin/seatunnel.sh --savepoint <job_id>

# 从 savepoint 恢复
$SEATUNNEL_HOME/bin/seatunnel.sh --config job.conf --restore <savepoint_path>
```

## 4. REST API

```bash
# 获取集群信息
curl http://localhost:5801/hazelcast/rest/cluster

# 获取运行中的作业
curl http://localhost:5801/hazelcast/rest/maps/running-jobs

# 提交作业（POST）
curl -X POST http://localhost:5801/hazelcast/rest/maps/submit-job \
  -H "Content-Type: application/json" \
  -d @job.json
```

## 5. 升级注意事项

- 升级前必须阅读[不向前兼容的更新](https://seatunnel.apache.org/zh-CN/docs/2.3.13/introduction/concepts/incompatible-changes)
- 备份 config/、connectors/、plugins/ 目录
- 对有状态作业先创建 savepoint
- 升级后先提交验证任务，再恢复正式作业

# 参考文档

- [部署文档](https://seatunnel.apache.org/zh-CN/docs/2.3.13/getting-started/locally/deployment)
- [快速开始](https://seatunnel.apache.org/zh-CN/docs/2.3.13/getting-started/locally/quick-start-seatunnel-engine)
- [Local 模式部署](https://seatunnel.apache.org/zh-CN/docs/2.3.13/engines/zeta/local-mode-deployment/)
- [混合集群部署](https://seatunnel.apache.org/zh-CN/docs/2.3.13/engines/zeta/hybrid-cluster-deployment/)
- [分离集群部署](https://seatunnel.apache.org/zh-CN/docs/2.3.13/engines/zeta/separated-cluster-deployment/)
- [版本升级](https://seatunnel.apache.org/zh-CN/docs/2.3.13/engines/zeta/version-upgrade)

---

请基于以上规范，生成 **Apache SeaTunnel** 的完整运维代码。每个文件独立输出，包含完整可运行的代码。
