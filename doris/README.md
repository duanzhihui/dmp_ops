# DorisStack - Apache Doris 集群部署工具

基于 OneinStack 风格的 Apache Doris 一键部署运维工具，支持多版本安装、多种部署模式和完整集群管理。

## 核心特性

- **统一安装包**：所有版本均使用 `apache-doris-<ver>-bin-<arch>.tar.gz`（FE+BE+MS 合并）
- **三种部署模式**：
  - **standalone** — 单机部署（FE + BE）
  - **integrated** — 存算一体集群（FE 集群 + BE 集群）
  - **separated** — 存算分离集群（FDB + MS + FE + BE + Storage Vault，3.x+ 专属）
- **多版本支持**：Doris 2.1.11 / 3.0.8 / 4.1.1
- **完整运维链**：安装、卸载、升级、监控、备份

## 支持版本

| 版本 | 存算一体 | 存算分离 | 安装包名 |
|------|---------|---------|---------|
| 2.1.11 (LTS) | ✅ | ❌ | `apache-doris-2.1.11-bin-x64.tar.gz` |
| 3.0.8 | ✅ | ✅ | `apache-doris-3.0.8-bin-x64.tar.gz` |
| 4.1.1 (Latest) | ✅ | ✅ | `apache-doris-4.1.1-bin-x64.tar.gz` |

> **注意**：所有版本的安装包内含 `fe/`、`be/`、`ms/`（ms 仅 3.x+）、`tools/` 子目录。

## 系统要求

- **操作系统**: CentOS 7+, RHEL 7+, Ubuntu 18.04+, Debian 10+
- **架构**: x86_64 / aarch64
- **Java**: JDK 8（Doris 2.x）/ JDK 17（Doris 3.x+）
- **内存**: FE 建议 16GB+，BE 建议 32GB+
- **磁盘**: FE 元数据建议 SSD，BE 数据盘根据数据量规划

## 目录结构

```
doris/
├── install.sh              # 安装脚本（3 种部署模式）
├── uninstall.sh            # 卸载脚本（FE/BE/MS/FDB）
├── upgrade.sh              # 升级脚本（FE/BE/MS）
├── versions.txt            # 版本定义 + FDB 版本
├── options.conf            # 配置文件（含存算分离配置）
├── config/
│   ├── fe.conf             # FE 配置模板
│   ├── be.conf             # BE 配置模板
│   └── doris_cloud.conf    # Meta Service 配置模板
├── include/
│   ├── color.sh            # 颜色定义
│   ├── check_os.sh         # 操作系统检测
│   ├── check_env.sh        # 环境检查
│   ├── download.sh         # 统一包下载 + Extract_Component
│   ├── doris_fe.sh         # FE 安装管理（支持 cloud 模式）
│   ├── doris_be.sh         # BE 安装管理
│   ├── doris_ms.sh         # Meta Service 安装管理
│   ├── fdb.sh              # FoundationDB 部署
│   └── cluster.sh          # 存算一体 + 存算分离集群部署
├── init.d/
│   ├── doris-fe.service    # FE systemd 服务
│   ├── doris-be.service    # BE systemd 服务
│   └── doris-ms.service    # MS systemd 服务
├── src/                    # 安装包存放目录
└── tools/
    ├── cluster_manage.sh   # 集群管理（FE/BE/MS/FDB/Vaults）
    ├── backup.sh           # 备份工具
    └── monitor.sh          # 监控脚本（FE/BE/MS）
```

## 快速开始

### 1. 单机部署

```bash
# 交互式安装
bash install.sh

# 非交互式安装（最新版本）
bash install.sh --doris_ver 3 --quiet
```

### 2. 存算一体集群

编辑 `options.conf`：
```bash
deploy_mode=integrated
fe_nodes="192.168.1.1:9010,192.168.1.2:9010,192.168.1.3:9010"
be_nodes="192.168.1.4:9050,192.168.1.5:9050,192.168.1.6:9050"
priority_networks=192.168.1.0/24
```

执行部署：
```bash
bash install.sh --doris_ver 3 --deploy_mode integrated
```

### 3. 存算分离集群（3.x+ 专属）

编辑 `options.conf`：
```bash
deploy_mode=separated
fe_nodes="192.168.1.1:9010,192.168.1.2:9010,192.168.1.3:9010"
be_nodes="192.168.1.4:9050,192.168.1.5:9050,192.168.1.6:9050"
fdb_nodes="192.168.1.10,192.168.1.11,192.168.1.12"
ms_nodes="192.168.1.10:5000,192.168.1.11:5000,192.168.1.12:5000"
priority_networks=192.168.1.0/24

# S3 Storage Vault
storage_vault_type=S3
s3_endpoint=http://minio.example.com:9000
s3_access_key=your_ak
s3_secret_key=your_sk
s3_region=us-east-1
s3_bucket=doris-storage
```

执行部署：
```bash
bash install.sh --doris_ver 3 --deploy_mode separated
```

### 4. 单组件安装

```bash
bash install.sh --fe_only --doris_ver 3
bash install.sh --be_only --doris_ver 3
bash install.sh --ms_only --doris_ver 3   # Meta Service
```

### 5. 仅下载安装包

```bash
bash install.sh --doris_ver 3 --download_only
```

## 集群管理

```bash
# 查看集群状态
bash tools/cluster_manage.sh status

# 服务控制
bash tools/cluster_manage.sh start-fe
bash tools/cluster_manage.sh stop-be
bash tools/cluster_manage.sh restart-ms

# 添加/移除节点
bash tools/cluster_manage.sh add-fe 192.168.1.10
bash tools/cluster_manage.sh add-be 192.168.1.11
bash tools/cluster_manage.sh add-observer 192.168.1.12
bash tools/cluster_manage.sh drop-be 192.168.1.11

# 检查
bash tools/cluster_manage.sh check-health
bash tools/cluster_manage.sh check-fdb
bash tools/cluster_manage.sh show-vaults
```

## 升级

```bash
# 交互式升级
bash upgrade.sh

# 升级指定组件
bash upgrade.sh --fe 4.1.1
bash upgrade.sh --be 4.1.1
bash upgrade.sh --ms 4.1.1

# 全部升级
bash upgrade.sh --all 4.1.1
```

## 卸载

```bash
# 交互式卸载
bash uninstall.sh

# 全部卸载（FE + BE + MS + FDB）
bash uninstall.sh --all --quiet

# 单独卸载
bash uninstall.sh --fe
bash uninstall.sh --be
bash uninstall.sh --ms
bash uninstall.sh --fdb
```

## 备份 & 监控

```bash
# 备份
bash tools/backup.sh --all     # 完整备份
bash tools/backup.sh --conf    # 仅配置
bash tools/backup.sh --meta    # 仅元数据

# 监控（FE/BE/MS 进程、磁盘、连通性）
bash tools/monitor.sh
```

## 部署架构

### 存算一体集群

```
┌──────────┐  ┌──────────┐  ┌──────────┐
│ FE Master│  │FE Follower│  │FE Follower│
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │              │              │
┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐
│  BE Node │  │  BE Node │  │  BE Node │
│(本地磁盘) │  │(本地磁盘) │  │(本地磁盘) │
└──────────┘  └──────────┘  └──────────┘
```

### 存算分离集群

```
┌──────────────────────────────────────┐
│          FoundationDB Cluster        │
└──────────────┬───────────────────────┘
               │
┌──────────────┴───────────────────────┐
│       Meta Service (MS) Cluster      │
└──────────────┬───────────────────────┘
               │
┌──────────┐  ┌──────────┐  ┌──────────┐
│ FE Master│  │FE Follower│  │FE Follower│
│(cloud模式)│  │(cloud模式)│  │(cloud模式)│
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │              │              │
┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐
│  BE Node │  │  BE Node │  │  BE Node │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │              │              │
┌────┴──────────────┴──────────────┴───┐
│       Storage Vault (S3 / HDFS)      │
└──────────────────────────────────────┘
```

### 端口说明

| 组件 | 端口 | 用途 |
|------|------|------|
| FE | 8030 | HTTP Web UI |
| FE | 9020 | Thrift RPC |
| FE | 9030 | MySQL 协议端口 |
| FE | 9010 | 内部通信端口 |
| BE | 8040 | HTTP Web UI |
| BE | 9050 | 心跳端口 |
| BE | 8060 | BRPC 端口 |
| MS | 5000 | Meta Service BRPC 端口 |
| FDB | 4500 | FoundationDB 端口 |

## 配置说明

主要配置文件 `options.conf`：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `deploy_mode` | standalone | `standalone` / `integrated` / `separated` |
| `run_user` | doris | 运行用户 |
| `fe_install_dir` | /opt/doris/fe | FE 安装目录 |
| `be_install_dir` | /opt/doris/be | BE 安装目录 |
| `ms_install_dir` | /opt/doris/ms | MS 安装目录 |
| `fe_meta_dir` | /data/doris/fe-meta | FE 元数据目录 |
| `be_data_dir` | /data/doris/be-storage | BE 数据目录 |
| `priority_networks` | 自动检测 | 网络 CIDR |
| `fdb_nodes` | — | FDB 节点（存算分离） |
| `ms_nodes` | — | MS 节点（存算分离） |
| `storage_vault_type` | S3 | 存储类型：`S3` / `HDFS` |

## 常见问题

### Q: FE 启动失败？
查看日志：`/data/doris/fe-log/fe.log` 或 `fe.out`

### Q: BE 无法注册？
1. 检查 `priority_networks` 是否正确
2. 检查防火墙端口
3. 确认 heartbeat_service_port 一致

### Q: 存算分离模式 FE 报错？
1. 确认 FDB 集群正常：`fdbcli --exec status`
2. 确认 Meta Service 已启动
3. 检查 `fe.conf` 中 `deploy_mode=cloud`、`cluster_id`、`meta_service_endpoint` 配置

### Q: 如何检查集群状态？
```bash
mysql -uroot -P9030 -h<FE_IP> -e "show frontends; show backends;"
# 存算分离模式还可查看：
mysql -uroot -P9030 -h<FE_IP> -e "SHOW STORAGE VAULTS;"
```

## 参考文档

- [Doris 2.1 存算一体部署](https://doris.apache.org/zh-CN/docs/2.1/install/deploy-manually/integrated-storage-compute-deploy-manually)
- [Doris 3.x 存算一体部署](https://doris.apache.org/zh-CN/docs/3.x/install/deploy-manually/integrated-storage-compute-deploy-manually)
- [Doris 3.x 存算分离部署](https://doris.apache.org/zh-CN/docs/3.x/install/deploy-manually/separating-storage-compute-deploy-manually)
- [Doris 4.x 存算一体部署](https://doris.apache.org/zh-CN/docs/4.x/install/deploy-manually/integrated-storage-compute-deploy-manually)
- [Doris 4.x 存算分离部署](https://doris.apache.org/zh-CN/docs/4.x/install/deploy-manually/separating-storage-compute-deploy-manually)

## 许可证

Apache License 2.0
