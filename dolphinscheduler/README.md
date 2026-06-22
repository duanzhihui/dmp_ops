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
# 1. 配置 options.conf 中的集群节点信息
# 2. 配置 SSH 免密登录
# 3. 执行安装
./install.sh --deploy_mode cluster --ds_ver 3
```

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

# 集群节点配置（cluster 模式必须）
ips=localhost
masters=localhost
workers=localhost:default
alert_server=localhost
api_servers=localhost
```

## 服务管理

### Standalone 模式

```bash
systemctl start dolphinscheduler-standalone
systemctl stop dolphinscheduler-standalone
systemctl restart dolphinscheduler-standalone
systemctl status dolphinscheduler-standalone
```

### Pseudo-Cluster / Cluster 模式

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

### 查看状态

```bash
./monitor.sh --status
```

### 健康检查

```bash
./monitor.sh --check
```

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
