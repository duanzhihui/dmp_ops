# DolphinSchedulerStack

Apache DolphinScheduler 集群部署工具

## 支持版本

- DolphinScheduler 3.4.1 (Latest)
- DolphinScheduler 3.3.2
- DolphinScheduler 3.2.2

## 部署模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| **standalone** | 单机模式，所有服务在一个进程中，内置 H2 数据库和 Zookeeper | 快速体验、开发测试 |
| **pseudo-cluster** | 伪集群模式，单机多进程，需要外部 Zookeeper 和数据库 | 功能测试、小规模生产 |
| **cluster** | 集群模式，多机部署，支持高可用 | 生产环境 |

## 快速开始

### 1. Standalone 模式（推荐新手）

```bash
# 交互式安装
./install.sh

# 或静默安装
./install.sh --deploy_mode standalone --ds_ver 3 --quiet
```

### 2. Pseudo-Cluster 模式

```bash
# 1. 先安装并启动 ZooKeeper
# 2. 配置 options.conf 中的数据库和 ZooKeeper 连接信息
# 3. 执行安装
./install.sh --deploy_mode pseudo-cluster --ds_ver 3
```

### 3. Cluster 模式

```bash
# 1. 配置 options.conf 中的集群节点信息（ips / masters / workers / api_servers / alert_server）
# 2. 确保数据库已对所有节点 IP 授权，ZooKeeper 已启动
# 3. 在控制节点执行安装（脚本会自动分发到各节点）
./install.sh --deploy_mode cluster --ds_ver 3

# 查看集群状态
./install.sh --status
```

集群模式是**按角色部署**的：`ips` 中的每个节点必须至少出现在
`masters` / `workers` / `api_servers` / `alert_server` 之一，节点只会安装并启用
自己所属角色的 systemd 服务。元数据库 schema 是共享的，只会在 `ips` 的**第一个节点**
初始化一次。

**前提**：控制节点能以 `ssh_user`（默认 `root`）免密 SSH 到所有节点，相关配置为
`options.conf` 中的 `ssh_port` / `ssh_user` / `ssh_key_file`。部署用户
`dolphinscheduler` 是脚本在各节点上创建的，因此不能用它来引导一台全新的机器。
若尚未配置免密：

```bash
ssh-copy-id -p 22 root@<节点IP>
```

**数据库授权**：每个节点都会直连元数据库，所以账号必须对所有节点地址授权：

```sql
CREATE DATABASE IF NOT EXISTS dolphinscheduler DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'dolphinscheduler'@'10.0.50.%' IDENTIFIED BY '<password>';
GRANT ALL PRIVILEGES ON dolphinscheduler.* TO 'dolphinscheduler'@'10.0.50.%';
FLUSH PRIVILEGES;
```

否则会看到 `Host '<ip>' is not allowed to connect to this MySQL server`，安装会在
初始化数据库前直接中止。

## 目录结构

```
dolphinscheduler/
├── install.sh              # 主安装入口
├── uninstall.sh            # 卸载脚本
├── upgrade.sh              # 升级脚本
├── backup.sh               # 备份脚本
├── monitor.sh              # 监控脚本
├── options.conf            # 中央配置文件
├── versions.txt            # 版本号清单
├── include/                # 功能模块库
│   ├── color.sh            # 终端颜色定义
│   ├── check_os.sh         # 操作系统检测
│   ├── check_env.sh        # 环境检查
│   ├── download.sh         # 下载函数
│   ├── dolphinscheduler.sh # 安装/卸载模块
│   ├── cluster.sh          # 集群部署模块
│   ├── upgrade_dolphinscheduler.sh  # 升级模块
│   └── monitor_dolphinscheduler.sh  # 监控模块
├── init.d/                 # systemd 服务文件
│   ├── dolphinscheduler-standalone.service
│   ├── dolphinscheduler-master.service
│   ├── dolphinscheduler-worker.service
│   ├── dolphinscheduler-api.service
│   └── dolphinscheduler-alert.service
└── src/                    # 源码包存放目录
```

## 配置说明

### options.conf 主要配置项

```bash
# 部署模式
deploy_mode=standalone  # standalone / pseudo-cluster / cluster

# 安装目录
dolphinscheduler_install_dir=/opt/dolphinscheduler

# 数据库配置（pseudo-cluster 和 cluster 模式必须）
db_type=mysql           # mysql / postgresql
db_host=localhost
db_port=3306
db_name=dolphinscheduler
db_user=root
db_password=

# ZooKeeper 配置（pseudo-cluster 和 cluster 模式必须）
zk_hosts=localhost:2181

# 端口配置（pseudo-cluster / cluster 模式）
api_port=25333
master_rpc_port=5678    # master 内部 RPC 端口
master_web_port=5679    # master actuator/metrics 端口
worker_rpc_port=1234
worker_web_port=1235
alert_rpc_port=50052
alert_web_port=50053

# 集群节点配置（cluster 模式必须）
ips=localhost
masters=localhost
workers=localhost:default   # ip:分组，分组会真正生效，见下文
alert_server=localhost
api_servers=localhost

# 集群部署用的 SSH 配置（需提前配置好免密）
ssh_port=22
ssh_user=root
ssh_key_file=          # 留空表示使用 ssh_user 的默认密钥

# 注册中心命名空间（所有角色必须一致）
registry_namespace=dolphinscheduler

# 过载保护（DolphinScheduler 原生默认开启且阈值偏低）
server_load_protection_enabled=false
server_load_protection_max_cpu=0.9
server_load_protection_max_jvm_cpu=0.9
server_load_protection_max_memory=0.9
server_load_protection_max_disk=0.9

# 注册地址所用网卡（多网卡机器务必指定）
network_interface_preferred=      # 例如 eth0，留空自动探测
network_interface_restrict=docker0
network_priority_strategy=default

# 任务执行工作目录（common.properties: data.basedir.path）
data_basedir_path=/data/dolphinscheduler/exec
```

> 填写了 `db_password` 后建议 `chmod 600 options.conf`。

### 影响任务派发的三项配置

任务实例的 `host` 字段只有在 **Master 成功把任务派发给某个 Worker 之后**才会写入。
以下三项任何一项不对，任务都会停在「提交成功」且 `host` 为空：

| 配置项 | 作用 | 不配会怎样 |
|--------|------|-----------|
| `workers=ip:分组` | 3.3+ 写入 `worker-server/conf/application.yaml` 的 `worker.group`；<br>3.2.x 写入 `t_ds_worker_group` 表 | 工作流选了某个分组，但该分组下没有 Worker，任务永远派发不出去 |
| `server_load_protection_*` | Master / Worker 的过载保护开关与阈值 | 原生默认阈值 0.7（3.2.x）/ 0.8（3.3+），节点内存或磁盘稍高就上报 BUSY，Master 直接跳过该 Worker |
| `network_interface_preferred` | 服务注册到注册中心时使用的网卡 | 多网卡机器可能注册一个别的节点路由不到的 IP，派发时 RPC 连接失败 |

这三项都会在 `install.sh` / `upgrade.sh` 时自动落到各模块的 `application.yaml`
与 `common.properties`，`./monitor.sh --check` 也会直接读注册中心校验实际生效情况。

> `bin/env/install_env.sh` **不会**被本工具写入：它只被 DolphinScheduler 自带的
> `install.sh` 读取，而本工具全程使用自己生成的 systemd unit 启动服务。

## 服务管理

### Standalone 模式

```bash
systemctl start dolphinscheduler-standalone
systemctl stop dolphinscheduler-standalone
systemctl restart dolphinscheduler-standalone
systemctl status dolphinscheduler-standalone
```

### Pseudo-Cluster / Cluster 模式

Cluster 模式下每个节点只有自己角色对应的服务单元，因此下面的命令需在拥有该角色的节点上执行。

```bash
# Master Server
systemctl {start|stop|restart|status} dolphinscheduler-master

# Worker Server
systemctl {start|stop|restart|status} dolphinscheduler-worker

# API Server
systemctl {start|stop|restart|status} dolphinscheduler-api

# Alert Server
systemctl {start|stop|restart|status} dolphinscheduler-alert
```

## 访问 Web UI

- **Standalone 模式**: http://localhost:12345/dolphinscheduler/ui
- **Pseudo-Cluster / Cluster 模式**: http://localhost:25333/dolphinscheduler/ui

默认账号密码：
- 用户名: `admin`
- 密码: `dolphinscheduler123`

## 常用命令

### 启动 / 停止整个集群

`monitor.sh` 提供一键启停，按部署模式自动分发：

```bash
# 启动整个集群（standalone / pseudo-cluster / cluster 通用）
./monitor.sh --start

# 停止整个集群
./monitor.sh --stop
```

**启动顺序与依赖校验**：cluster / pseudo-cluster 模式下按角色顺序启动，
且后一角色只有在前一角色的**所有节点**都 `active` 之后才会启动：

1. `master` —— 必须全部 active，否则中止启动（master 是其他角色的依赖）
2. `worker` —— 依赖 master
3. `api` —— 依赖 master
4. `alert` —— 独立，最后启动

**停止顺序**为反向：`alert → api → worker → master`。

cluster 模式下只需在控制节点（`options.conf` 中配置了 `ips` 的节点）执行，
脚本会经 SSH 遍历所有节点按角色启停；各节点无需单独操作。

### 查看状态

```bash
./monitor.sh --status
```

### 健康检查

```bash
./monitor.sh --check
```

除进程 / 端口 / HTTP / 磁盘外，还会直接读取注册中心（ZooKeeper）校验：

- Worker 是否真的注册成功（没有注册 → 任务 `host` 必为空）
- 注册到了哪个 Worker 分组，与 `options.conf` 中 `workers=ip:分组` 是否一致
- 每个 Worker 上报的 `serverStatus` 是 `NORMAL` 还是 `BUSY`（过载保护）

这一项需要 `zkCli.sh`；找不到时会输出 `[SKIP]`，可在 `options.conf` 的
`zk_cli` 中指定绝对路径。

### 任务实例 host 为空的排查

```bash
# 1. 任务实例选的是哪个 worker group
mysql -h<db_host> -u<db_user> -p <db_name> -e \
  "select id,name,state,host,worker_group,submit_time from t_ds_task_instance order by id desc limit 10;"

# 2. 注册中心里到底有哪些 worker、在哪个组下、是否 BUSY
./monitor.sh --check

# 3. Master 有没有在喊找不到 worker
grep -E "NoSuitableWorker|Cannot find worker|dispatch.*fail|Connection refused" \
  /opt/dolphinscheduler/master-server/logs/dolphinscheduler-master.log | tail -50

# 4. 从 Master 节点验证 Worker RPC 端口可达
nc -vz <worker_ip> 1234
```

### 持续监控

```bash
# 每 60 秒检查一次，发现故障写日志（不外发）
./monitor.sh --loop 60

# 持续监控 + 自动重启故障服务
./monitor.sh --loop 60 --recovery
```

### Cluster 模式集群级监控

Cluster 模式下，**只需在控制节点**（`options.conf` 中配置了 `ips` 的节点）执行
`monitor.sh`，脚本会经 SSH 遍历所有节点，统一检查整个集群。各节点无需单独跑。

```bash
# 全集群状态总览（每个节点每个角色的 active/inactive/unknown）
./monitor.sh --status

# 全集群健康检查：每节点按角色检查进程/端口/HTTP/磁盘，
# 共享组件（ZooKeeper / 元数据库）只在控制节点查一次
./monitor.sh --check

# 持续监控全集群（60s 一轮），发现故障写日志
./monitor.sh --loop 60

# 持续监控 + 自动重启故障服务
./monitor.sh --loop 60 --recovery
```

监控日志写入 `${dolphinscheduler_log_dir}/monitor.log`（默认
`/data/dolphinscheduler/logs/monitor.log`）。当 `options.conf` 中的
`alert_email` 和 `webhook_url` 均为空时，`Send_Alert` 只写日志文件，不外发。

### 升级

```bash
./upgrade.sh --version 3.4.1
```

### 备份

```bash
./backup.sh
```

### 卸载

```bash
./uninstall.sh --all
```

## 依赖环境

- **操作系统**: CentOS 7+, Debian 9+, Ubuntu 16+
- **JDK**: 1.8+（必须配置 JAVA_HOME）
- **数据库**: MySQL 5.7+ 或 PostgreSQL 8.2.15+（pseudo-cluster 和 cluster 模式）
- **ZooKeeper**: 3.4.6+（pseudo-cluster 和 cluster 模式）
- **psmisc**: 进程树分析工具

## 参考文档

- [DolphinScheduler 官方文档](https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1)
- [Standalone 部署](https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1/guide/installation/standalone)
- [Pseudo-Cluster 部署](https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1/guide/installation/pseudo-cluster)
- [Cluster 部署](https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1/guide/installation/cluster)

## License

Apache License 2.0
