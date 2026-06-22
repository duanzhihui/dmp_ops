# ZooKeeper 运维脚本

基于 oneinstack 架构规范的 Apache ZooKeeper 自动化运维脚本集。

## 支持版本

| 版本 | JDK 要求 | 状态 |
|------|---------|------|
| 3.9.5 | JDK 11+ | 最新 |
| 3.8.6 | JDK 8+ | 稳定 |
| 3.7.2 | JDK 8+ | 旧版 |

## 快速开始

### 单机模式安装

```bash
# 交互式安装
./install.sh

# 静默安装
./install.sh --standalone --zk_ver 3.9.5
```

### 集群模式安装

```bash
# 节点 1
./install.sh --cluster --zk_ver 3.9.5 --myid 1 \
  --nodes "1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"

# 节点 2
./install.sh --cluster --zk_ver 3.9.5 --myid 2 \
  --nodes "1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"

# 节点 3
./install.sh --cluster --zk_ver 3.9.5 --myid 3 \
  --nodes "1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"
```

## 目录结构

```
zookeeper/
├── install.sh          # 安装脚本
├── uninstall.sh        # 卸载脚本
├── upgrade.sh          # 升级脚本
├── backup.sh           # 备份脚本
├── backup_setup.sh     # 备份配置向导
├── monitor.sh          # 监控脚本
├── options.conf        # 配置文件
├── versions.txt        # 版本清单
├── include/            # 功能模块
│   ├── color.sh        # 颜色定义
│   ├── check_os.sh     # OS 检测
│   ├── check_env.sh    # 环境检测
│   ├── download.sh     # 下载函数
│   ├── zookeeper.sh    # 安装/卸载
│   ├── upgrade_zk.sh   # 升级模块
│   ├── cluster.sh      # 集群管理
│   └── monitor_zk.sh   # 监控模块
├── init.d/             # systemd 服务
│   └── zookeeper.service
├── config/             # 配置模板
│   ├── zoo.cfg
│   ├── java.env
│   └── log4j.properties
├── tools/              # 辅助工具
│   ├── zk_snapshot.sh  # 快照工具
│   └── zk_txnlog.sh    # 事务日志工具
└── src/                # 源码包目录
```

## 常用命令

### 服务管理

```bash
# 启动/停止/重启
systemctl start zookeeper
systemctl stop zookeeper
systemctl restart zookeeper

# 查看状态
systemctl status zookeeper
```

### 健康检查

```bash
# 四字命令
echo ruok | nc localhost 2181    # 健康检查
echo stat | nc localhost 2181    # 服务状态
echo srvr | nc localhost 2181    # 服务器信息
echo mntr | nc localhost 2181    # 监控指标
echo cons | nc localhost 2181    # 客户端连接

# 使用监控脚本
./monitor.sh --status            # 状态报告
./monitor.sh --check             # 健康检查
./monitor.sh --cluster           # 集群状态
./monitor.sh --watch             # 持续监控
```

### 备份恢复

```bash
# 配置备份策略
./backup_setup.sh

# 手动备份
./backup.sh                      # 完整备份
./backup.sh --snapshot           # 仅快照
./backup.sh --config             # 仅配置
```

### 升级

```bash
# 交互式升级
./upgrade.sh

# 指定版本升级
./upgrade.sh --zk_ver 3.9.5

# 滚动升级（集群）
./upgrade.sh --rolling --zk_ver 3.9.5
```

### 卸载

```bash
# 交互式卸载
./uninstall.sh

# 静默卸载
./uninstall.sh --quiet

# 保留数据卸载
./uninstall.sh --keep-data
```

## 配置说明

### options.conf

```bash
# 安装路径
zk_install_dir=/opt/zookeeper
zk_data_dir=/data/zookeeper
zk_log_dir=/data/zookeeper/logs

# 端口配置
zk_client_port=2181
zk_peer_port=2888
zk_election_port=3888
zk_admin_port=8080

# 部署模式
deploy_mode=standalone  # standalone 或 cluster

# 集群配置
cluster_nodes=          # 格式: "1:host1 2:host2 3:host3"
myid=1

# JVM 配置
zk_heap_size=1024m
JAVA_HOME=/usr/local/jdk
```

## 端口说明

| 端口 | 用途 |
|------|------|
| 2181 | 客户端连接 |
| 2888 | 集群数据同步 |
| 3888 | Leader 选举 |
| 8080 | Admin Server |

## 集群规模建议

| 节点数 | 容错能力 | 适用场景 |
|--------|---------|---------|
| 3 | 1 节点 | 小型生产 |
| 5 | 2 节点 | 中型生产 |
| 7 | 3 节点 | 大型生产 |

> 节点数必须为奇数

## 官方文档

- [ZooKeeper 3.9.5](https://zookeeper.apache.org/doc/r3.9.5/zookeeperStarted.html)
- [ZooKeeper 3.8.6](https://zookeeper.apache.org/doc/r3.8.6/zookeeperStarted.html)
- [ZooKeeper 3.7.2](https://zookeeper.apache.org/doc/r3.7.2/zookeeperStarted.html)

## License

Apache License 2.0
