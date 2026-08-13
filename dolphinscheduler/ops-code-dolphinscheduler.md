# Apache DolphinScheduler 运维代码 — AI 编程提示词

> 本文档基于 oneinstack 项目架构规范，为 **Apache DolphinScheduler** 生成完整的运维自动化脚本提示词。
> 可直接复制给 AI 编程工具（Cursor / Windsurf / Copilot）生成代码。

---

## 软件概述

**Apache DolphinScheduler** 是一个分布式、易扩展的可视化工作流任务调度平台。

### 版本信息

| 版本系列 | 具体版本 | 状态 |
|---------|---------|------|
| 3.4.x | 3.4.1 | Latest |
| 3.3.x | 3.3.2 | Stable |
| 3.2.x | 3.2.2 | LTS |

### 部署模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| standalone | 所有服务在一个进程中运行 | 测试/开发环境 |
| pseudo-cluster | 单节点多进程部署 | 小规模生产环境 |
| cluster | 多节点分布式部署 | 大规模生产环境 |

### 核心组件

| 组件 | 默认端口 | 说明 |
|------|---------|------|
| Standalone Server | 12345 | 独立服务器（standalone 模式） |
| API Server | 25333 | REST API 服务 |
| Master Server | 5678 | 任务调度主节点 |
| Worker Server | 1234 | 任务执行工作节点 |
| Alert Server | 50052 | 告警服务 |

### 外部依赖

| 依赖 | 版本要求 | 说明 |
|------|---------|------|
| JDK | 8+ | Java 运行环境 |
| ZooKeeper | 3.8+ | 注册中心（pseudo-cluster/cluster 模式必需） |
| MySQL | 5.7+ / 8.0+ | 元数据存储（可选 PostgreSQL） |
| MySQL JDBC | 8.0.16+ | MySQL 驱动 |

### 官方文档

- **3.4.1 部署文档**
  - Standalone: https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1/guide/installation/standalone
  - Pseudo-Cluster: https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1/guide/installation/pseudo-cluster
  - Cluster: https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1/guide/installation/cluster

- **3.3.2 部署文档**
  - Standalone: https://dolphinscheduler.apache.org/zh-cn/docs/3.3.2/guide/installation/standalone
  - Pseudo-Cluster: https://dolphinscheduler.apache.org/zh-cn/docs/3.3.2/guide/installation/pseudo-cluster
  - Cluster: https://dolphinscheduler.apache.org/zh-cn/docs/3.3.2/guide/installation/cluster

- **3.2.2 部署文档**
  - Standalone: https://dolphinscheduler.apache.org/zh-cn/docs/3.2.2/guide/installation/standalone
  - Pseudo-Cluster: https://dolphinscheduler.apache.org/zh-cn/docs/3.2.2/guide/installation/pseudo-cluster
  - Cluster: https://dolphinscheduler.apache.org/zh-cn/docs/3.2.2/guide/installation/cluster

---

## AI 编程提示词

```markdown
# 角色

你是一位资深的 Linux 运维自动化工程师，精通 Bash Shell 编程和 systemd 服务管理。
你的任务是为开源软件 **Apache DolphinScheduler** 编写一套完整的运维自动化脚本。

# 输入参数

## 软件基本信息

- **SOFTWARE_NAME**: Apache DolphinScheduler
- **SOFTWARE_VERSIONS**: 
  - 3.4.1 (Latest)
  - 3.3.2 (Stable)
  - 3.2.2 (LTS)
- **INSTALL_DIR**: /opt/dolphinscheduler
- **DATA_DIR**: /data/dolphinscheduler
- **LOG_DIR**: /data/dolphinscheduler/logs
- **RUN_USER**: dolphinscheduler
- **RUN_GROUP**: dolphinscheduler

## 端口配置

| 组件 | 端口变量 | 默认值 |
|------|---------|--------|
| Standalone Server | web_port | 12345 |
| API Server | api_port | 25333 |
| Master Server (RPC / Web) | master_rpc_port / master_web_port | 5678 / 5679 |
| Worker Server (RPC / Web) | worker_rpc_port / worker_web_port | 1234 / 1235 |
| Alert Server (RPC / Web) | alert_rpc_port / alert_web_port | 50052 / 50053 |

> Master/Worker/Alert 各自有两个端口：内部 RPC 端口和 Jetty actuator/metrics 端口，二者不能相同。

## 下载地址

- **主镜像**: https://downloads.apache.org/dolphinscheduler/{version}/apache-dolphinscheduler-{version}-bin.tar.gz
- **归档镜像**: https://archive.apache.org/dist/dolphinscheduler/{version}/apache-dolphinscheduler-{version}-bin.tar.gz
- **安装包格式**: apache-dolphinscheduler-{version}-bin.tar.gz

## 部署模式

| 模式 | 说明 | 依赖 |
|------|------|------|
| standalone | 所有服务在一个进程 | JDK 8+ |
| pseudo-cluster | 单节点多进程 | JDK 8+, ZooKeeper, MySQL/PostgreSQL |
| cluster | 多节点分布式 | JDK 8+, ZooKeeper, MySQL/PostgreSQL, SSH 免密 |

## 外部依赖

- **JDK**: 8+ (必需)
- **ZooKeeper**: 3.8+ (pseudo-cluster/cluster 模式必需)
- **MySQL**: 5.7+ / 8.0+ (pseudo-cluster/cluster 模式必需，可选 PostgreSQL)
- **MySQL JDBC Driver**: 8.0.33 (使用 MySQL 时必需)

# 输出要求

请生成以下文件，每个文件的代码必须完整、可直接运行：

## 文件清单

### 1. `options.conf` — 中央配置文件

**功能**: 存储所有可配置参数

**要求**:
- 镜像源配置：mirror_link, archive_mirror_link
- 时区配置：timezone
- 运行用户：run_user, run_group
- 安装目录：dolphinscheduler_home, dolphinscheduler_install_dir
- 数据目录：dolphinscheduler_data_dir, dolphinscheduler_log_dir
- 端口配置：web_port, api_port, master_rpc_port, master_web_port, worker_rpc_port, worker_web_port, alert_rpc_port, alert_web_port
- 部署模式：deploy_mode (standalone/pseudo-cluster/cluster)
- 数据库配置：db_type, db_host, db_port, db_name, db_user, db_password
- ZooKeeper 配置：zk_hosts
- 集群配置：ips, masters, workers, alert_server, api_servers, ssh_port, ssh_user, ssh_key_file
- 资源存储配置：resource_storage_type, resource_local_path, hdfs_*, s3_*
- JAVA_HOME 配置
- 备份配置：backup_dir, expired_days, backup_destination, backup_content
- 告警配置：alert_email, webhook_url

### 2. `versions.txt` — 版本号清单

**功能**: 管理所有软件版本号

**要求**:
# DolphinScheduler 版本
dolphinscheduler34_ver=3.4.1
dolphinscheduler33_ver=3.3.2
dolphinscheduler32_ver=3.2.2

# JDK 版本
jdk8_ver=8u392

# MySQL JDBC Driver 版本
mysql_jdbc_ver=8.0.33

# ZooKeeper 版本
zookeeper_ver=3.9.3
```

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

### 5. `include/download.sh` — 下载函数

**功能**: 提供可靠的文件下载能力

**要求**:
- `Download_src()` 函数，通过 `src_url` 变量传入 URL
- 多源容错：主镜像 → 归档镜像
- `Download_DolphinScheduler()` 函数，下载指定版本的 DolphinScheduler
- `Download_MySQL_JDBC()` 函数，下载 MySQL JDBC 驱动
- `Get_DolphinScheduler_Pkg()` 函数，返回安装包文件名
- 检测下载失败（文件 <1KB 且含 HTML 标签则视为错误页）
- 支持断点续传 (wget -c)
- 失败时提示用户手动下载路径

### 6. `include/check_env.sh` — 环境检测模块

**功能**: 检测和配置运行环境

**要求**:
- `Check_Deps()` — 检测并安装系统依赖（wget, tar, psmisc 等）
- `Create_User()` — 创建运行用户
- `Detect_Network()` — 检测网络并获取本机 IP
- `Configure_Sudo()` — 配置 sudo 权限（写入 /etc/sudoers.d/ 并用 visudo -c 校验）
- `Configure_SSH()` — 配置 SSH 免密登录
- `Check_Java()` — 检测 Java 环境，设置 JAVA_HOME
- `Install_Java()` — 安装 OpenJDK 8
- `Check_ZooKeeper()` — 检测 ZooKeeper 连通性
- `Check_Database()` — 检测数据库连通性
- `Print_DB_Access_Hint()` — 打印各节点所需的建库/授权 SQL
- `Has_Role()` — 判断本节点是否承担某角色（master/worker/api/alert）
- `Check_Port()` / `Check_Ports()` — 检测端口占用（按角色过滤；DolphinScheduler 自身占用不算冲突）

### 7. `include/dolphinscheduler.sh` — 安装/卸载模块

**功能**: DolphinScheduler 的安装和卸载逻辑

**要求**:
- `Install_DolphinScheduler_Standalone()` — Standalone 模式安装
  1. 检测是否已安装（幂等）
  2. 创建目录
  3. 解压安装包
  4. 配置环境变量 (dolphinscheduler_env.sh)
  5. 设置目录权限
  6. 安装 systemd 服务
  7. 验证安装结果

- `Install_DolphinScheduler_PseudoCluster()` — Pseudo-Cluster / 单个集群节点安装
  1. 创建目录
  2. 解压安装包（已解压则跳过，但仍重新配置，保证幂等且可修复失败的安装）
  3. 安装 MySQL JDBC 驱动（如使用 MySQL）
  4. 配置环境变量
  5. 配置 install_env.sh
  6. 配置 application.yaml
  7. 初始化数据库（skip_db_init=y 时跳过，schema 只在首节点初始化一次）
  8. 设置目录权限
  9. 按 node_roles 安装 systemd 服务
  - 任一步骤失败即返回非 0，不再继续安装服务

- `Configure_Env_Standalone()` — 配置 Standalone 环境
- `Configure_Env_PseudoCluster()` — 配置 Pseudo-Cluster 环境
- `Configure_Install_Env()` — 配置 install_env.sh
- `Configure_Application_Yaml()` — 配置各模块的 application.yaml
- `Install_MySQL_JDBC()` — 安装 MySQL JDBC 驱动到各模块
- `Init_Database()` — 初始化数据库
- `Install_Standalone_Service()` — 安装 Standalone systemd 服务
- `Installed_Cluster_Roles()` — 列出本节点已安装服务单元的角色
- `Write_Service_Unit()` — 生成单个 systemd 服务单元
- `Install_PseudoCluster_Services()` — 按角色安装 systemd 服务（非本节点角色的单元会被停用并删除）
- `Start_Standalone()` — 启动 Standalone 服务
- `Start_PseudoCluster()` — 按角色启动服务，失败时打印 journalctl 并返回非 0
- `Uninstall_DolphinScheduler()` — 卸载 DolphinScheduler

### 8. `include/cluster.sh` — 集群部署模块

**功能**: 多节点、按角色的集群部署逻辑

**要求**:
- `Is_Local_Node()` / `In_Node_List()` — 节点归属判断（workers 支持 ip:group 格式）
- `Get_Node_Roles()` — 由 masters/workers/api_servers/alert_server 推导某节点的角色列表
- `Build_SSH_Opts()` — 由 ssh_port / ssh_key_file 组装 ssh_opts、scp_opts（注意 ssh 用 -p、scp 用 -P）
- `Remote_Target()` / `Remote_Cmd()` — 以 ssh_user 连接，非 root 时自动加 sudo
- `Deploy_Cluster()` — 集群模式部署：校验角色配置 → 检查 SSH → 逐节点部署（首节点初始化 schema），任一节点失败即中止
- `Check_SSH_Connectivity()` / `Test_SSH()` — 检测各节点免密 SSH 连通性（跳过本机），不通则中止并提示 ssh-copy-id
- `Deploy_To_Node()` — 部署到单个节点（远端以 `--deploy_mode node --roles ...` 执行，只安装不启动）
- `Systemctl_On_Node()` — 按角色在指定节点上执行 systemctl
- `Start_Cluster()` / `Stop_Cluster()` — 按角色启停集群服务
- `Show_Cluster_Status_Full()` — 按角色显示集群状态

### 9. `include/upgrade_dolphinscheduler.sh` — 升级模块

**功能**: DolphinScheduler 版本升级逻辑

**要求**:
- `Upgrade_DolphinScheduler()` 函数：
  1. 检测当前已安装版本
  2. 获取最新可用版本
  3. 提示用户输入目标版本（有默认值）
  4. 校验版本号（新旧不能相同）
  5. 下载新版本
  6. 升级前备份（配置文件 + 数据库）
  7. 停服务 → 替换文件 → 执行数据库升级脚本 → 启服务
  8. 验证升级结果
- `Get_Latest_Version()` — 获取最新版本
- `Backup_Before_Upgrade()` — 升级前备份
- `Rollback_Upgrade()` — 回滚升级

### 10. `include/monitor_dolphinscheduler.sh` — 监控模块

**功能**: 健康检查与状态监控

**要求**:
- `Check_Process()` — 检查进程是否存活
- `Check_Port()` — 检查端口是否监听
- `Check_HTTP()` — HTTP 健康检查（API Server）
- `Check_Disk()` — 检查磁盘空间
- `Check_ZK_Connection()` — 检查 ZooKeeper 连接
- `Check_DB_Connection()` — 检查数据库连接
- `Send_Alert()` — 告警通知（邮件 + Webhook）
- `Monitor_DolphinScheduler_Status()` — 综合状态检查
- `Auto_Recovery()` — 自动恢复
- `Monitor_Loop()` — 持续监控循环

### 11. `install.sh` — 安装主入口

**功能**: 安装主控脚本

**要求**:
- 文件头：root 检查、source 配置和公共库
- getopt 参数解析，支持：
  - `--help, -h` — 显示帮助
  - `--version, -v` — 显示版本
  - `--ds_ver [1-3]` — DolphinScheduler 版本选择
  - `--deploy_mode [mode]` — 部署模式（standalone/pseudo-cluster/cluster，内部另有 node）
  - `--download_only` — 仅下载不安装
  - `--quiet, -q` — 静默模式
  - `--status` — 显示集群状态
  - `--roles [list]` — 内部选项：本节点角色列表（master,worker,api,alert）
  - `--skip_db_init` — 内部选项：不初始化共享的元数据库 schema
- 无参数时显示交互式菜单
- 有参数时静默执行
- 安装流程：
  1. 选择版本
  2. 选择部署模式、解析角色
  3. 检查环境（sudo 配置失败即退出）
  4. 检查 Java
  5. 检查外部依赖（ZooKeeper/数据库）—— 数据库不可用即退出，并打印所需授权 SQL
  6. 下载安装包
  7. 检查端口（cluster 模式下由各节点自行检查）
  8. 执行安装（任一步失败即退出）
  9. 启动服务（node 模式不启动，由控制节点统一启动）
  10. 显示安装摘要（cluster 模式打印各节点角色）

### 12. `uninstall.sh` — 卸载主入口

**功能**: 卸载主控脚本

**要求**:
- getopt 参数解析，支持：
  - `--quiet, -q` — 静默模式
  - `--all` — 卸载所有组件
  - `--standalone` — 仅卸载 Standalone
  - `--master` — 仅卸载 Master
  - `--worker` — 仅卸载 Worker
  - `--api` — 仅卸载 API
  - `--alert` — 仅卸载 Alert
- 卸载前显示将删除的文件列表
- 用户确认后执行（--quiet 跳过确认）
- 数据目录重命名备份而非直接删除
- 清理 systemd 服务
- 清理用户（如无服务残留）

### 13. `upgrade.sh` — 升级主入口

**功能**: 升级主控脚本

**要求**:
- getopt 参数解析：
  - `--version [ver]` — 目标版本
  - `--quiet, -q` — 静默模式
  - `--rollback [backup_dir]` — 回滚到备份
  - `--check` — 检查可用更新
- 无参数时显示菜单
- 升级前自动备份
- 支持回滚

### 14. `backup.sh` — 备份执行脚本

**功能**: 由 cron 调用的备份执行器

**要求**:
- 从 options.conf 读取备份配置
- 支持备份内容：
  - `db` — 数据库备份（mysqldump/pg_dump）
  - `config` — 配置文件备份
  - `logs` — 日志备份
- 支持备份目标：local, oss, s3
- 过期清理：按 expired_days 删除旧备份
- 文件命名格式：`{type}_{name}_{date}_{time}.tar.gz`

### 15. `monitor.sh` — 监控主入口

**功能**: 监控主控脚本

**要求**:
- getopt 参数解析：
  - `--status` — 显示状态报告
  - `--check` — 执行健康检查
  - `--loop [interval]` — 持续监控
  - `--recovery` — 启用自动恢复
- 自动检测已安装的组件并执行对应检查
- 输出到日志文件 + 终端
- 异常时触发告警

### 16. `init.d/dolphinscheduler-standalone.service` — Standalone systemd 服务

```ini
[Unit]
Description=Apache DolphinScheduler Standalone Server
After=network.target
Wants=network-online.target

[Service]
Type=forking
User=dolphinscheduler
Group=dolphinscheduler
Environment="JAVA_HOME=/usr/lib/jvm/java-8-openjdk"
ExecStart=/opt/dolphinscheduler/bin/dolphinscheduler-daemon.sh start standalone-server
ExecStop=/opt/dolphinscheduler/bin/dolphinscheduler-daemon.sh stop standalone-server
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
```

### 17. `init.d/dolphinscheduler-master.service` — Master systemd 服务

### 18. `init.d/dolphinscheduler-worker.service` — Worker systemd 服务

### 19. `init.d/dolphinscheduler-api.service` — API systemd 服务

### 20. `init.d/dolphinscheduler-alert.service` — Alert systemd 服务

# 代码规范约束

1. **Shell 版本**: #!/bin/bash，兼容 Bash 4.0+
2. **缩进**: 2 空格
3. **变量命名**: 小写 + 下划线（如 `install_dir`），常量大写（如 `THREAD`）
4. **函数命名**: 大驼峰（如 `Install_DolphinScheduler`, `Upgrade_DolphinScheduler`）
5. **幂等性**: 所有安装操作必须支持重复执行（已安装则跳过）
6. **错误处理**: 关键操作失败时 `kill -9 $$; exit 1`，数据操作前必须备份
7. **日志输出**: 使用 color.sh 的颜色变量（CSUCCESS/CFAILURE/CWARNING/CMSG）
8. **PATH 设置**: 脚本开头固定 `export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin`
9. **root 检查**: `[ $(id -u) != "0" ] && { echo "Error: must be root"; exit 1; }`
10. **工作目录**: 使用 `pushd/popd` 管理目录切换
11. **临时文件**: 操作完成后及时清理
12. **配置分离**: 所有可变参数放 options.conf，版本号放 versions.txt，代码中只引用变量
13. **安全**: 密码用 `/dev/urandom` 生成，不硬编码；service 使用非 root 用户运行
14. **兼容性**: 支持 x86_64 和 aarch64 架构，支持 RHEL/Debian/Ubuntu 系列

# DolphinScheduler 特殊要求

## 安装包结构

DolphinScheduler 安装包解压后的目录结构：
```
apache-dolphinscheduler-{version}-bin/
├── bin/
│   ├── dolphinscheduler-daemon.sh    # 服务启停脚本
│   └── env/
│       ├── dolphinscheduler_env.sh   # 环境变量配置
│       └── install_env.sh            # 集群部署配置
├── standalone-server/                 # Standalone 服务
├── master-server/                     # Master 服务
├── worker-server/                     # Worker 服务
├── api-server/                        # API 服务
├── alert-server/                      # Alert 服务
├── tools/                             # 工具（数据库初始化等）
│   └── bin/
│       └── upgrade-schema.sh          # 数据库初始化/升级脚本
└── ui/                                # Web UI
```

## 数据库初始化

使用 `tools/bin/upgrade-schema.sh` 脚本初始化数据库：
```bash
cd ${dolphinscheduler_install_dir}/tools
source ${dolphinscheduler_install_dir}/bin/env/dolphinscheduler_env.sh
bash bin/upgrade-schema.sh
```

## MySQL JDBC 驱动安装

需要将 MySQL JDBC 驱动复制到以下目录：
- tools/libs/
- alert-server/libs/
- api-server/libs/
- master-server/libs/
- worker-server/libs/

## 环境变量配置 (dolphinscheduler_env.sh)

关键配置项：
```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk
export DATABASE=mysql
export SPRING_PROFILES_ACTIVE=${DATABASE}
export SPRING_DATASOURCE_URL=jdbc:mysql://localhost:3306/dolphinscheduler?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true
export SPRING_DATASOURCE_USERNAME=root
export SPRING_DATASOURCE_PASSWORD=password
export REGISTRY_TYPE=zookeeper
export REGISTRY_ZOOKEEPER_CONNECT_STRING=localhost:2181
```

## 集群部署配置 (install_env.sh)

关键配置项：
```bash
ips="192.168.1.1,192.168.1.2,192.168.1.3"
sshPort="22"
masters="192.168.1.1,192.168.1.2"
workers="192.168.1.3:default"
alertServer="192.168.1.1"
apiServers="192.168.1.1"
installPath="/opt/dolphinscheduler"
deployUser="dolphinscheduler"
```

## 默认登录凭证

- **用户名**: admin
- **密码**: dolphinscheduler123

## Web UI 访问地址

- **Standalone 模式**: http://{ip}:12345/dolphinscheduler/ui
- **Pseudo-Cluster/Cluster 模式**: http://{api_server_ip}:25333/dolphinscheduler/ui

## 目录结构

```
dolphinscheduler/
├── install.sh              # 主安装入口
├── uninstall.sh            # 主卸载入口
├── upgrade.sh              # 主升级入口
├── backup.sh               # 备份执行脚本
├── monitor.sh              # 健康检查与状态监控
├── options.conf            # 中央配置文件
├── versions.txt            # 版本号清单
├── README.md               # 项目说明文档
├── include/                # 功能模块库
│   ├── color.sh            #   终端颜色定义
│   ├── check_os.sh         #   操作系统检测
│   ├── check_env.sh        #   环境检测与配置
│   ├── download.sh         #   下载函数
│   ├── dolphinscheduler.sh #   安装/卸载模块
│   ├── cluster.sh          #   集群部署模块
│   ├── upgrade_dolphinscheduler.sh  #   升级模块
│   └── monitor_dolphinscheduler.sh  #   监控模块
├── init.d/                 # systemd service 模板
│   ├── dolphinscheduler-standalone.service
│   ├── dolphinscheduler-master.service
│   ├── dolphinscheduler-worker.service
│   ├── dolphinscheduler-api.service
│   └── dolphinscheduler-alert.service
└── src/                    # 源码包存放目录
```

---

## 使用示例

### 快速安装（Standalone 模式）

```bash
# 交互式安装
./install.sh

# 静默安装
./install.sh --ds_ver 3 --deploy_mode standalone --quiet
```

### 生产环境安装（Pseudo-Cluster 模式）

```bash
# 1. 编辑配置文件
vim options.conf
# 配置数据库连接、ZooKeeper 地址等

# 2. 执行安装
./install.sh --ds_ver 3 --deploy_mode pseudo-cluster --quiet
```

### 集群部署

```bash
# 1. 配置集群节点
vim options.conf
# 设置 ips, masters, workers, alert_server, api_servers
# 设置 ssh_port / ssh_user / ssh_key_file，并提前配好 root 免密互信

# 2. 确保数据库已对所有节点 IP 授权（每个节点都直连元数据库）

# 3. 在控制节点执行，脚本按角色分发到各节点
./install.sh --deploy_mode cluster --ds_ver 3

# 4. 查看集群状态
./install.sh --status
```

### 升级

```bash
# 检查可用更新
./upgrade.sh --check

# 升级到指定版本
./upgrade.sh --version 3.4.1

# 回滚
./upgrade.sh --rollback /data/backup/dolphinscheduler/20240101
```

### 监控

```bash
# 查看状态
./monitor.sh --status

# 健康检查
./monitor.sh --check

# 持续监控（每 60 秒）
./monitor.sh --loop 60 --recovery
```

### 备份

```bash
# 手动执行备份
./backup.sh

# 设置定时备份（每天凌晨 2 点）
echo "0 2 * * * /opt/dolphinscheduler-deploy/backup.sh" >> /var/spool/cron/root
```

---

## 附录：关键代码模式

### 版本选择模式

```bash
Select_Version() {
  if [ -n "${ds_ver_option}" ]; then
    case "${ds_ver_option}" in
      1|${dolphinscheduler32_ver}) ds_ver=${dolphinscheduler32_ver} ;;
      2|${dolphinscheduler33_ver}) ds_ver=${dolphinscheduler33_ver} ;;
      3|${dolphinscheduler34_ver}) ds_ver=${dolphinscheduler34_ver} ;;
      *)
        echo "${CWARNING}Invalid ds_ver: ${ds_ver_option}${CEND}"
        exit 1
        ;;
    esac
  else
    # 交互式选择
    while :; do
      echo 'Please select Apache DolphinScheduler version:'
      echo -e "\t${CMSG}1${CEND}. DolphinScheduler ${dolphinscheduler32_ver}"
      echo -e "\t${CMSG}2${CEND}. DolphinScheduler ${dolphinscheduler33_ver}"
      echo -e "\t${CMSG}3${CEND}. DolphinScheduler ${dolphinscheduler34_ver} (Latest)"
      read -e -p "Please input a number:(Default 3 press Enter) " ds_ver_option
      ds_ver_option=${ds_ver_option:-3}
      [[ ${ds_ver_option} =~ ^[1-3]$ ]] && break
    done
    case "${ds_ver_option}" in
      1) ds_ver=${dolphinscheduler32_ver} ;;
      2) ds_ver=${dolphinscheduler33_ver} ;;
      3) ds_ver=${dolphinscheduler34_ver} ;;
    esac
  fi
}
```

### 部署模式选择模式

```bash
Select_Deploy_Mode() {
  while :; do
    echo 'Please select deployment mode:'
    echo -e "\t${CMSG}1${CEND}. Standalone (All services in one process, for testing)"
    echo -e "\t${CMSG}2${CEND}. Pseudo-Cluster (Single node, separate processes)"
    echo -e "\t${CMSG}3${CEND}. Cluster (Multi-node deployment for production)"
    read -e -p "Please input a number:(Default 1 press Enter) " deploy_option
    deploy_option=${deploy_option:-1}
    [[ ${deploy_option} =~ ^[1-3]$ ]] && break
  done
  case "${deploy_option}" in
    1) deploy_mode="standalone" ;;
    2) deploy_mode="pseudo-cluster" ;;
    3) deploy_mode="cluster" ;;
  esac
}
```

### 幂等安装模式

```bash
Install_DolphinScheduler_Standalone() {
  local ds_ver=$1

  # 幂等检测
  if [ -d "${dolphinscheduler_install_dir}" ] && [ -f "${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh" ]; then
    echo "${CWARNING}DolphinScheduler is already installed at ${dolphinscheduler_install_dir}${CEND}"
    return 0
  fi

  # 创建目录
  mkdir -p ${dolphinscheduler_install_dir}
  mkdir -p ${dolphinscheduler_data_dir}
  mkdir -p ${dolphinscheduler_log_dir}

  # 解压安装包
  tar xzf ${ds_dir}/src/${ds_pkg} -C ${dolphinscheduler_install_dir} --strip-components=1

  # 验证安装
  if [ ! -f "${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh" ]; then
    echo "${CFAILURE}Failed to extract DolphinScheduler package!${CEND}"
    return 1
  fi

  # 配置环境
  Configure_Env_Standalone "${ds_ver}"

  # 设置权限
  chown -R ${run_user}:${run_group} ${dolphinscheduler_install_dir}
  chown -R ${run_user}:${run_group} ${dolphinscheduler_data_dir}

  # 安装 systemd 服务
  Install_Standalone_Service

  echo "${CSUCCESS}DolphinScheduler ${ds_ver} (Standalone) installed successfully!${CEND}"
}
```

### 服务状态检查模式

```bash
Show_Status() {
  echo "${CMSG}========== DolphinScheduler Service Status ==========${CEND}"

  for service in standalone master worker api alert; do
    if [ -f "/lib/systemd/system/dolphinscheduler-${service}.service" ]; then
      local status=$(systemctl is-active dolphinscheduler-${service} 2>/dev/null)
      if [ "${status}" == "active" ]; then
        echo "${CSUCCESS}[RUNNING]${CEND} ${service}-server"
      else
        echo "${CFAILURE}[STOPPED]${CEND} ${service}-server"
      fi
    fi
  done
}
```

### 卸载确认模式

```bash
Uninstall_Service() {
  local service_name=$1

  if [ -f "/lib/systemd/system/dolphinscheduler-${service_name}.service" ]; then
    echo "${CMSG}Uninstalling ${service_name} server...${CEND}"
    systemctl stop dolphinscheduler-${service_name} 2>/dev/null
    systemctl disable dolphinscheduler-${service_name} 2>/dev/null
    rm -f /lib/systemd/system/dolphinscheduler-${service_name}.service
    echo "${CSUCCESS}${service_name} server uninstalled.${CEND}"
  fi
}

# 数据目录备份而非删除
if [ -d "${dolphinscheduler_data_dir}" ]; then
  local backup_name="${dolphinscheduler_data_dir}_$(date +%Y%m%d%H%M%S)"
  mv ${dolphinscheduler_data_dir} ${backup_name}
fi
```
