# Apache ZooKeeper 运维代码生成提示词

> 本文档为 **Apache ZooKeeper** 定制的运维自动化脚本生成提示词。
> 基于 oneinstack 项目架构规范，可直接交给 AI 编程工具生成完整的 ZooKeeper 运维代码。

---

# Part A: ZooKeeper 技术规格

## 1. 软件概述

**Apache ZooKeeper** 是一个开源的分布式协调服务，提供配置管理、命名服务、分布式同步和组服务等功能。广泛用于 Hadoop、Kafka、HBase、Doris 等分布式系统的协调管理。

### 1.1 支持版本

| 版本系列 | 推荐版本 | JDK 要求 | 发布日期 |
|---------|---------|---------|---------|
| 3.9.x | **3.9.5** | JDK 11+ | 2025 |
| 3.8.x | **3.8.6** | JDK 8+ | 2024 |
| 3.7.x | **3.7.2** | JDK 8+ | 2023 |

### 1.2 官方文档

- **3.9.5**: https://zookeeper.apache.org/doc/r3.9.5/zookeeperStarted.html
- **3.8.6**: https://zookeeper.apache.org/doc/r3.8.6/zookeeperStarted.html
- **3.7.2**: https://zookeeper.apache.org/doc/r3.7.2/zookeeperStarted.html

### 1.3 核心特性

- **高可用**: 集群模式支持 2N+1 节点，容忍 N 节点故障
- **强一致性**: ZAB 协议保证数据一致性
- **顺序访问**: 所有更新操作全局有序
- **原子性**: 更新操作要么成功要么失败，无中间状态
- **实时性**: 客户端可获取最新数据视图

## 2. 部署模式

### 2.1 单机模式 (Standalone)

适用于开发测试环境，单节点运行。

```
┌─────────────────────────────────┐
│         ZooKeeper Server        │
│  ┌───────────┐ ┌─────────────┐  │
│  │  Leader   │ │   Follower  │  │
│  │  (N/A)    │ │    (N/A)    │  │
│  └───────────┘ └─────────────┘  │
│         Port: 2181              │
└─────────────────────────────────┘
```

### 2.2 集群模式 (Replicated/Ensemble)

生产环境推荐，至少 3 节点（奇数个）。

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Node 1    │    │   Node 2    │    │   Node 3    │
│  (Leader)   │◄──►│ (Follower)  │◄──►│ (Follower)  │
│  Port:2181  │    │  Port:2181  │    │  Port:2181  │
│  Port:2888  │    │  Port:2888  │    │  Port:2888  │
│  Port:3888  │    │  Port:3888  │    │  Port:3888  │
└─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
                    ZAB Protocol
                  (Leader Election)
```

## 3. 端口说明

| 端口 | 用途 | 说明 |
|------|------|------|
| **2181** | Client Port | 客户端连接端口 |
| **2888** | Peer Port | 集群节点间数据同步端口 |
| **3888** | Leader Election Port | Leader 选举通信端口 |
| **8080** | Admin Server | 管理接口（3.5.0+，可选） |

## 4. 目录结构规范

```
zookeeper/
├── install.sh              # 主安装入口（交互/静默双模式）
├── uninstall.sh            # 主卸载入口
├── upgrade.sh              # 主升级入口
├── backup.sh               # 备份执行脚本（由 cron 调用）
├── backup_setup.sh         # 备份策略配置向导
├── monitor.sh              # 健康检查与状态监控
├── options.conf            # 中央配置文件（路径、端口、集群配置）
├── versions.txt            # 版本号清单
├── include/                # 功能模块库
│   ├── color.sh            #   终端颜色定义
│   ├── check_os.sh         #   操作系统检测与适配
│   ├── check_env.sh        #   环境检测（JDK 版本检查）
│   ├── download.sh         #   下载函数（多源容错）
│   ├── zookeeper.sh        #   ZooKeeper 安装/卸载模块
│   ├── upgrade_zk.sh       #   ZooKeeper 升级模块
│   ├── cluster.sh          #   集群部署与管理
│   └── monitor_zk.sh       #   ZooKeeper 监控模块
├── init.d/                 # systemd service 模板
│   └── zookeeper.service   #   ZooKeeper 服务文件
├── config/                 # 配置文件模板
│   ├── zoo.cfg             #   ZooKeeper 主配置模板
│   ├── zoo_cluster.cfg     #   集群模式配置模板
│   ├── log4j.properties    #   日志配置模板
│   └── java.env            #   JVM 参数配置
├── tools/                  # 辅助工具脚本
│   ├── zk_snapshot.sh      #   快照备份脚本
│   └── zk_txnlog.sh        #   事务日志清理脚本
└── src/                    # 源码包存放目录
```

## 5. 文件职责说明

### 5.1 主入口脚本

| 文件 | 职责 | 关键设计 |
|------|------|---------|
| `install.sh` | 安装主入口，支持单机/集群模式选择 | getopt 参数 + 交互菜单；`--standalone` / `--cluster` |
| `uninstall.sh` | 卸载主入口，停止服务、清理数据 | 数据目录重命名备份而非删除 |
| `upgrade.sh` | 升级主入口，支持滚动升级 | 版本校验 + 配置保留 + 数据迁移 |
| `backup.sh` | 备份执行器，备份快照和事务日志 | 支持本地/远程/云存储多目标 |
| `backup_setup.sh` | 备份配置向导 | 配置持久化到 options.conf |
| `monitor.sh` | 健康检查与状态监控 | 四字命令检测 + Leader/Follower 状态 |

### 5.2 功能模块 (include/)

| 文件 | 职责 | 核心函数 |
|------|------|---------|
| `color.sh` | 终端颜色定义 | `CSUCCESS`/`CFAILURE`/`CWARNING`/`CMSG`/`CEND` |
| `check_os.sh` | OS 检测 | 输出 `Platform`、`Family`、`PM`、`ARCH` |
| `check_env.sh` | 环境检测 | `Check_JDK()` — 检测 JDK 版本是否满足要求 |
| `download.sh` | 下载函数 | `Download_src()` — 多源容错下载 |
| `zookeeper.sh` | 安装/卸载 | `Install_ZooKeeper()`、`Uninstall_ZooKeeper()` |
| `upgrade_zk.sh` | 升级逻辑 | `Upgrade_ZooKeeper()` — 版本升级 |
| `cluster.sh` | 集群管理 | `Deploy_Cluster()`、`Add_Node()`、`Remove_Node()` |
| `monitor_zk.sh` | 监控检查 | `Check_ZK_Status()`、`Check_ZK_Mode()` |

### 5.3 配置文件

| 文件 | 职责 |
|------|------|
| `options.conf` | 中央配置：安装路径、数据目录、端口、集群节点列表、JVM 参数 |
| `versions.txt` | 版本号清单，支持多版本选择 |
| `config/zoo.cfg` | ZooKeeper 主配置模板 |
| `config/java.env` | JVM 堆内存、GC 参数配置 |

## 6. 运维生命周期 — ZooKeeper 专属流程

### 6.1 安装 (Install)

**流程模式：**
```
JDK 检测 → 已安装检测 → 下载二进制包 → 解压部署 → 生成 zoo.cfg → 生成 myid(集群) → 创建用户 → 注册 systemd → 启动服务 → 验证四字命令
```

**关键代码模式：**

```bash
# 1. JDK 版本检测（ZooKeeper 3.9+ 需要 JDK 11+）
Check_JDK() {
  if [ ! -x "${JAVA_HOME}/bin/java" ]; then
    echo "${CFAILURE}JDK not found! Please install JDK first.${CEND}"
    exit 1
  fi
  local java_ver=$(${JAVA_HOME}/bin/java -version 2>&1 | head -1 | awk -F'"' '{print $2}' | awk -F'.' '{print $1}')
  if [ "${zk_ver%%.*}" -ge "3" ] && [ "${zk_ver#*.}" -ge "9" ]; then
    [ "${java_ver}" -lt 11 ] && {
      echo "${CFAILURE}ZooKeeper 3.9+ requires JDK 11+, current: ${java_ver}${CEND}"
      exit 1
    }
  fi
}

# 2. 已安装检测 — 幂等性保证
[ -e "${zk_install_dir}/bin/zkServer.sh" ] && {
  echo "${CWARNING}ZooKeeper already installed!${CEND}"
  exit 0
}

# 3. 下载（多源容错）
src_url="https://archive.apache.org/dist/zookeeper/zookeeper-${zk_ver}/apache-zookeeper-${zk_ver}-bin.tar.gz"
Download_src

# 4. 解压部署（二进制包，无需编译）
tar xzf apache-zookeeper-${zk_ver}-bin.tar.gz
mv apache-zookeeper-${zk_ver}-bin ${zk_install_dir}

# 5. 生成配置文件
cat > ${zk_install_dir}/conf/zoo.cfg << EOF
tickTime=2000
initLimit=10
syncLimit=5
dataDir=${zk_data_dir}
dataLogDir=${zk_log_dir}
clientPort=${zk_client_port}
admin.serverPort=${zk_admin_port}
admin.enableServer=true
4lw.commands.whitelist=*
autopurge.snapRetainCount=3
autopurge.purgeInterval=1
EOF

# 6. 集群模式：生成 myid 文件
if [ "${deploy_mode}" == "cluster" ]; then
  echo "${myid}" > ${zk_data_dir}/myid
  # 添加集群节点配置
  for node in ${cluster_nodes}; do
    echo "server.${node%%:*}=${node#*:}:2888:3888" >> ${zk_install_dir}/conf/zoo.cfg
  done
fi

# 7. 创建系统用户
id -u zookeeper >/dev/null 2>&1 || useradd -M -s /sbin/nologin zookeeper
chown -R zookeeper:zookeeper ${zk_install_dir} ${zk_data_dir} ${zk_log_dir}

# 8. 注册 systemd 服务
/bin/cp ${script_dir}/init.d/zookeeper.service /lib/systemd/system/
systemctl daemon-reload
systemctl enable zookeeper
systemctl start zookeeper

# 9. 安装验证（使用四字命令）
sleep 3
if echo "ruok" | nc -w 2 127.0.0.1 ${zk_client_port} | grep -q "imok"; then
  echo "${CSUCCESS}ZooKeeper installed successfully!${CEND}"
else
  echo "${CFAILURE}ZooKeeper install failed!${CEND}"
  systemctl status zookeeper
  exit 1
fi
```

### 6.2 卸载 (Uninstall)

**流程模式：**
```
预览删除内容 → 用户确认 → 停止服务 → 禁用服务 → 备份数据目录 → 删除安装目录 → 删除用户 → 清理环境
```

**关键代码模式：**

```bash
# 1. 预览 — 显示将删除的内容
Print_ZooKeeper() {
  echo "${CMSG}The following will be removed:${CEND}"
  [ -e "${zk_install_dir}" ] && echo "  - ${zk_install_dir}"
  [ -e "${zk_data_dir}" ] && echo "  - ${zk_data_dir} (will be backed up)"
  [ -e "${zk_log_dir}" ] && echo "  - ${zk_log_dir}"
  [ -e "/lib/systemd/system/zookeeper.service" ] && echo "  - /lib/systemd/system/zookeeper.service"
}

# 2. 执行卸载
Uninstall_ZooKeeper() {
  # 停止服务
  systemctl stop zookeeper > /dev/null 2>&1
  systemctl disable zookeeper > /dev/null 2>&1
  
  # 删除 service 文件
  rm -f /lib/systemd/system/zookeeper.service
  systemctl daemon-reload
  
  # 数据目录：重命名备份（保留快照和事务日志）
  [ -e "${zk_data_dir}" ] && /bin/mv ${zk_data_dir}{,_bak_$(date +%Y%m%d%H%M)}
  
  # 删除安装目录和日志目录
  rm -rf ${zk_install_dir}
  rm -rf ${zk_log_dir}
  
  # 清理环境变量
  sed -i "s@${zk_install_dir}/bin:@@" /etc/profile
  sed -i '/ZOOKEEPER_HOME/d' /etc/profile
  
  # 删除用户
  id -u zookeeper >/dev/null 2>&1 && userdel zookeeper
  
  echo "${CSUCCESS}ZooKeeper uninstall completed!${CEND}"
  echo "${CMSG}Data backup: ${zk_data_dir}_bak_$(date +%Y%m%d%H%M)${CEND}"
}
```

### 6.3 升级 (Upgrade)

**流程模式：**
```
检测当前版本 → 版本校验 → 升级前备份 → 下载新版本 → 停服务 → 替换文件(保留配置) → 启动服务 → 验证四字命令
```

**关键代码模式：**

```bash
Upgrade_ZooKeeper() {
  # 1. 检测当前版本
  [ ! -e "${zk_install_dir}/bin/zkServer.sh" ] && {
    echo "${CWARNING}ZooKeeper is not installed!${CEND}"; exit 1
  }
  
  # 从 zookeeper-version.txt 或 jar 包获取版本
  OLD_ver=$(cat ${zk_install_dir}/zookeeper-version.txt 2>/dev/null || \
            ls ${zk_install_dir}/lib/zookeeper-*.jar | grep -oP '\d+\.\d+\.\d+' | head -1)
  
  echo "Current Version: ${CMSG}${OLD_ver}${CEND}"
  
  # 2. 获取可用版本列表
  echo "Available versions: 3.9.5, 3.8.6, 3.7.2"
  read -e -p "Please input upgrade version: " NEW_ver
  
  # 3. 版本校验
  [ "${NEW_ver}" == "${OLD_ver}" ] && {
    echo "${CWARNING}Same version, skip upgrade${CEND}"; exit 0
  }
  
  # 主版本校验（3.7 -> 3.8 允许，3.7 -> 4.0 需确认）
  OLD_major="${OLD_ver%%.*}"
  NEW_major="${NEW_ver%%.*}"
  [ "${OLD_major}" != "${NEW_major}" ] && {
    echo "${CWARNING}Cross major version upgrade detected!${CEND}"
    read -e -p "Continue? [y/n]: " confirm
    [ "${confirm}" != "y" ] && exit 0
  }
  
  # 4. 升级前备份
  echo "${CMSG}Backing up current installation...${CEND}"
  backup_dir="${zk_install_dir}_backup_$(date +%Y%m%d%H%M)"
  cp -a ${zk_install_dir} ${backup_dir}
  
  # 备份配置文件
  cp ${zk_install_dir}/conf/zoo.cfg ${zk_install_dir}/conf/zoo.cfg.bak
  cp ${zk_install_dir}/conf/java.env ${zk_install_dir}/conf/java.env.bak 2>/dev/null
  
  # 5. 下载新版本
  src_url="https://archive.apache.org/dist/zookeeper/zookeeper-${NEW_ver}/apache-zookeeper-${NEW_ver}-bin.tar.gz"
  Download_src
  
  # 6. 停止服务
  systemctl stop zookeeper
  
  # 7. 替换文件（保留配置和数据）
  tar xzf apache-zookeeper-${NEW_ver}-bin.tar.gz
  rm -rf ${zk_install_dir}/lib ${zk_install_dir}/bin
  cp -a apache-zookeeper-${NEW_ver}-bin/lib ${zk_install_dir}/
  cp -a apache-zookeeper-${NEW_ver}-bin/bin ${zk_install_dir}/
  
  # 恢复配置文件
  cp ${zk_install_dir}/conf/zoo.cfg.bak ${zk_install_dir}/conf/zoo.cfg
  
  # 记录新版本
  echo "${NEW_ver}" > ${zk_install_dir}/zookeeper-version.txt
  
  # 8. 启动服务并验证
  chown -R zookeeper:zookeeper ${zk_install_dir}
  systemctl start zookeeper
  
  sleep 3
  if echo "ruok" | nc -w 2 127.0.0.1 ${zk_client_port} | grep -q "imok"; then
    echo "${CSUCCESS}Successfully upgraded from ${OLD_ver} to ${NEW_ver}${CEND}"
    rm -rf apache-zookeeper-${NEW_ver}-bin
  else
    echo "${CFAILURE}Upgrade failed! Rolling back...${CEND}"
    systemctl stop zookeeper
    rm -rf ${zk_install_dir}
    mv ${backup_dir} ${zk_install_dir}
    systemctl start zookeeper
    exit 1
  fi
}
```

### 6.4 备份 (Backup)

**流程模式：**
```
备份快照文件 → 备份事务日志 → 备份配置文件 → 打包压缩 → 上传到目标存储 → 过期清理
```

**ZooKeeper 备份要点：**
- **快照文件 (snapshot)**: `${dataDir}/version-2/snapshot.*` — 数据快照
- **事务日志 (txnlog)**: `${dataDir}/version-2/log.*` — 事务日志
- **配置文件**: `zoo.cfg`, `myid`, `java.env`

**关键代码模式：**

```bash
# === ZooKeeper 备份函数 ===
ZK_Backup() {
  local backup_name="zk_backup_$(date +%Y%m%d_%H%M%S)"
  local backup_file="${backup_dir}/${backup_name}.tar.gz"
  local temp_dir="/tmp/${backup_name}"
  
  mkdir -p ${temp_dir}
  
  # 1. 备份快照和事务日志
  echo "${CMSG}Backing up snapshots and transaction logs...${CEND}"
  cp -a ${zk_data_dir}/version-2 ${temp_dir}/ 2>/dev/null
  
  # 2. 备份配置文件
  echo "${CMSG}Backing up configuration files...${CEND}"
  mkdir -p ${temp_dir}/conf
  cp ${zk_install_dir}/conf/zoo.cfg ${temp_dir}/conf/
  cp ${zk_data_dir}/myid ${temp_dir}/conf/ 2>/dev/null
  cp ${zk_install_dir}/conf/java.env ${temp_dir}/conf/ 2>/dev/null
  
  # 3. 打包压缩
  tar czf ${backup_file} -C /tmp ${backup_name}
  rm -rf ${temp_dir}
  
  echo "${CSUCCESS}Backup created: ${backup_file}${CEND}"
  
  # 4. 过期清理
  find ${backup_dir} -name "zk_backup_*.tar.gz" -mtime +${expired_days} -delete
}

# === 在线快照备份（推荐） ===
ZK_Snapshot_Backup() {
  # 使用 zkSnapShotToolkit 创建一致性快照
  ${zk_install_dir}/bin/zkSnapShotToolkit.sh -d ${zk_data_dir} > /dev/null 2>&1
  
  # 获取最新快照
  latest_snapshot=$(ls -t ${zk_data_dir}/version-2/snapshot.* 2>/dev/null | head -1)
  
  if [ -n "${latest_snapshot}" ]; then
    cp ${latest_snapshot} ${backup_dir}/snapshot_$(date +%Y%m%d_%H%M%S)
    echo "${CSUCCESS}Snapshot backup: ${latest_snapshot}${CEND}"
  fi
}

# === 云存储备份 ===
ZK_OSS_Backup() {
  ZK_Backup
  local latest_backup=$(ls -t ${backup_dir}/zk_backup_*.tar.gz | head -1)
  
  if [ -n "${latest_backup}" ]; then
    ossutil cp -f ${latest_backup} oss://${oss_bucket}/zookeeper/$(date +%F)/
    if [ $? -eq 0 ]; then
      echo "${CSUCCESS}Uploaded to OSS: ${latest_backup}${CEND}"
      # 清理远程过期备份
      ossutil rm -rf oss://${oss_bucket}/zookeeper/$(date +%F --date="${expired_days} days ago")/
    fi
  fi
}
```

### 6.5 监控 (Monitor)

**ZooKeeper 四字命令 (4LW Commands)：**

| 命令 | 用途 | 示例输出 |
|------|------|---------|
| `ruok` | 健康检查 | `imok` |
| `stat` | 服务状态 | 连接数、延迟、模式 |
| `srvr` | 服务器信息 | 版本、模式、节点数 |
| `mntr` | 监控指标 | Prometheus 格式指标 |
| `cons` | 客户端连接 | 连接列表 |
| `envi` | 环境信息 | JVM、OS 信息 |

**流程模式：**
```
四字命令检测 → Leader/Follower 状态 → 连接数检查 → 延迟检查 → 磁盘空间 → 告警通知
```

**关键代码模式：**

```bash
# === ZooKeeper 监控函数 ===

# 1. 基础健康检查（ruok）
Check_ZK_Health() {
  local host=${1:-127.0.0.1}
  local port=${2:-2181}
  
  local response=$(echo "ruok" | nc -w 2 ${host} ${port} 2>/dev/null)
  if [ "${response}" == "imok" ]; then
    echo "${CSUCCESS}[OK] ZooKeeper is healthy${CEND}"
    return 0
  else
    echo "${CFAILURE}[CRITICAL] ZooKeeper health check failed!${CEND}"
    Send_Alert "ZooKeeper health check failed on ${host}:${port}"
    return 1
  fi
}

# 2. 获取服务器状态（srvr）
Check_ZK_Status() {
  local host=${1:-127.0.0.1}
  local port=${2:-2181}
  
  local status=$(echo "srvr" | nc -w 2 ${host} ${port} 2>/dev/null)
  
  if [ -n "${status}" ]; then
    local mode=$(echo "${status}" | grep "Mode:" | awk '{print $2}')
    local connections=$(echo "${status}" | grep "Connections:" | awk '{print $2}')
    local outstanding=$(echo "${status}" | grep "Outstanding:" | awk '{print $2}')
    local znode_count=$(echo "${status}" | grep "Node count:" | awk '{print $3}')
    
    echo "${CMSG}=== ZooKeeper Status ===${CEND}"
    echo "  Mode: ${mode}"
    echo "  Connections: ${connections}"
    echo "  Outstanding: ${outstanding}"
    echo "  ZNode Count: ${znode_count}"
    
    # 检查是否为 Leader（集群模式）
    if [ "${mode}" == "leader" ]; then
      echo "${CSUCCESS}  This node is LEADER${CEND}"
    elif [ "${mode}" == "follower" ]; then
      echo "${CMSG}  This node is FOLLOWER${CEND}"
    elif [ "${mode}" == "standalone" ]; then
      echo "${CMSG}  Running in STANDALONE mode${CEND}"
    fi
    
    return 0
  else
    echo "${CFAILURE}[ERROR] Cannot get ZooKeeper status${CEND}"
    return 1
  fi
}

# 3. 获取监控指标（mntr）— Prometheus 格式
Check_ZK_Metrics() {
  local host=${1:-127.0.0.1}
  local port=${2:-2181}
  
  local metrics=$(echo "mntr" | nc -w 2 ${host} ${port} 2>/dev/null)
  
  if [ -n "${metrics}" ]; then
    # 提取关键指标
    local avg_latency=$(echo "${metrics}" | grep "zk_avg_latency" | awk '{print $2}')
    local max_latency=$(echo "${metrics}" | grep "zk_max_latency" | awk '{print $2}')
    local outstanding=$(echo "${metrics}" | grep "zk_outstanding_requests" | awk '{print $2}')
    local watch_count=$(echo "${metrics}" | grep "zk_watch_count" | awk '{print $2}')
    
    echo "${CMSG}=== ZooKeeper Metrics ===${CEND}"
    echo "  Avg Latency: ${avg_latency}ms"
    echo "  Max Latency: ${max_latency}ms"
    echo "  Outstanding Requests: ${outstanding}"
    echo "  Watch Count: ${watch_count}"
    
    # 延迟告警阈值
    if [ "${avg_latency}" -gt 100 ]; then
      echo "${CWARNING}[WARNING] High average latency: ${avg_latency}ms${CEND}"
      Send_Alert "ZooKeeper high latency: ${avg_latency}ms"
    fi
    
    return 0
  fi
  return 1
}

# 4. 检查客户端连接数
Check_ZK_Connections() {
  local host=${1:-127.0.0.1}
  local port=${2:-2181}
  local max_connections=${3:-1000}
  
  local cons=$(echo "cons" | nc -w 2 ${host} ${port} 2>/dev/null | wc -l)
  
  echo "  Active Connections: ${cons}"
  
  if [ "${cons}" -gt "${max_connections}" ]; then
    echo "${CWARNING}[WARNING] Too many connections: ${cons}${CEND}"
    Send_Alert "ZooKeeper connections exceeded: ${cons}/${max_connections}"
    return 1
  fi
  return 0
}

# 5. 集群状态检查
Check_ZK_Cluster() {
  echo "${CMSG}=== ZooKeeper Cluster Status ===${CEND}"
  
  for node in ${cluster_nodes}; do
    local host="${node%%:*}"
    local port="${node#*:}"
    port=${port:-2181}
    
    echo -n "  Node ${host}:${port} - "
    local mode=$(echo "srvr" | nc -w 2 ${host} ${port} 2>/dev/null | grep "Mode:" | awk '{print $2}')
    
    if [ -n "${mode}" ]; then
      if [ "${mode}" == "leader" ]; then
        echo "${CSUCCESS}LEADER${CEND}"
      else
        echo "${CMSG}${mode}${CEND}"
      fi
    else
      echo "${CFAILURE}UNREACHABLE${CEND}"
      Send_Alert "ZooKeeper node unreachable: ${host}:${port}"
    fi
  done
}

# 6. 主监控函数
Monitor_ZooKeeper() {
  echo "========== ZooKeeper Monitor: $(date) =========="
  
  Check_ZK_Health
  Check_ZK_Status
  Check_ZK_Metrics
  Check_ZK_Connections
  
  # 集群模式检查
  [ -n "${cluster_nodes}" ] && Check_ZK_Cluster
  
  # 磁盘空间检查
  Check_Disk 85
}
```

## 7. 配置文件规范

### 7.1 options.conf 结构

```bash
# ===== ZooKeeper 安装配置 =====
zk_install_dir=/opt/zookeeper
zk_data_dir=/data/zookeeper
zk_log_dir=/data/zookeeper/logs

# ===== 端口配置 =====
zk_client_port=2181
zk_peer_port=2888
zk_election_port=3888
zk_admin_port=8080

# ===== 部署模式 =====
# standalone: 单机模式
# cluster: 集群模式
deploy_mode=standalone

# ===== 集群配置（仅集群模式） =====
# 格式: myid:host 多个节点用空格分隔
# 示例: "1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"
cluster_nodes=
myid=1

# ===== JVM 配置 =====
zk_heap_size=1024m
zk_jvm_opts="-XX:+UseG1GC"

# ===== JDK 配置 =====
JAVA_HOME=/usr/local/jdk

# ===== 备份配置 =====
backup_dir=/data/backup/zookeeper
expired_days=7
backup_destination=local
oss_bucket=
s3_bucket=

# ===== 告警配置 =====
alert_email=
webhook_url=
```

### 7.2 versions.txt 结构

```bash
# ZooKeeper 版本号清单
# 格式: zk{major}{minor}_ver=x.x.x

zk39_ver=3.9.5
zk38_ver=3.8.6
zk37_ver=3.7.2

# 默认安装版本
zk_ver=3.9.5
```

### 7.3 zoo.cfg 配置模板

```properties
# ZooKeeper 基础配置
tickTime=2000
initLimit=10
syncLimit=5

# 数据目录
dataDir=${zk_data_dir}
dataLogDir=${zk_log_dir}

# 客户端端口
clientPort=${zk_client_port}

# Admin Server（3.5.0+）
admin.serverPort=${zk_admin_port}
admin.enableServer=true

# 四字命令白名单
4lw.commands.whitelist=*

# 自动清理快照和日志
autopurge.snapRetainCount=3
autopurge.purgeInterval=1

# 最大客户端连接数
maxClientCnxns=60

# 集群配置（动态生成）
# server.1=192.168.1.10:2888:3888
# server.2=192.168.1.11:2888:3888
# server.3=192.168.1.12:2888:3888
```

### 7.4 java.env JVM 配置

```bash
# ZooKeeper JVM 配置
export JAVA_HOME=${JAVA_HOME}
export ZK_SERVER_HEAP=${zk_heap_size}

# GC 配置（推荐 G1GC）
export SERVER_JVMFLAGS="-XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+ParallelRefProcEnabled"

# JMX 配置（可选）
# export JMXPORT=9999
# export JMXAUTH=false
# export JMXSSL=false
```

## 8. systemd 服务文件

```ini
[Unit]
Description=Apache ZooKeeper Server
Documentation=https://zookeeper.apache.org/doc/current/
After=network.target

[Service]
Type=forking
User=zookeeper
Group=zookeeper

Environment="JAVA_HOME=/usr/local/jdk"
Environment="ZK_HOME=/opt/zookeeper"
Environment="ZOOCFGDIR=/opt/zookeeper/conf"

ExecStart=/opt/zookeeper/bin/zkServer.sh start
ExecStop=/opt/zookeeper/bin/zkServer.sh stop
ExecReload=/opt/zookeeper/bin/zkServer.sh restart

PIDFile=/opt/zookeeper/data/zookeeper_server.pid

Restart=on-failure
RestartSec=10

LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
```

## 9. 命令行参数设计

**install.sh 参数：**

| 参数 | 说明 | 示例 |
|------|------|------|
| `--help` | 显示帮助 | |
| `--version` | 显示版本 | |
| `--quiet` | 静默模式 | |
| `--standalone` | 单机模式安装 | |
| `--cluster` | 集群模式安装 | |
| `--zk_ver` | 指定 ZK 版本 | `--zk_ver 3.9.5` |
| `--myid` | 指定节点 ID | `--myid 1` |
| `--nodes` | 指定集群节点 | `--nodes "1:10.0.0.1 2:10.0.0.2"` |

**uninstall.sh 参数：**

| 参数 | 说明 |
|------|------|
| `--quiet` | 跳过确认 |
| `--keep-data` | 保留数据目录 |

**upgrade.sh 参数：**

| 参数 | 说明 |
|------|------|
| `--zk_ver` | 指定升级版本 |
| `--rolling` | 滚动升级（集群） |

---

# Part B: AI 编程完整提示词

> 以下提示词可直接复制给 AI 编程工具（如 Cursor/Windsurf/Copilot），生成完整的 ZooKeeper 运维代码。

---

## 提示词全文

```markdown
# 角色

你是一位资深的 Linux 运维自动化工程师，精通 Bash Shell 编程、systemd 服务管理和分布式系统运维。
你的任务是为 **Apache ZooKeeper** 编写一套完整的运维自动化脚本。

# 软件信息

- **软件名称**: Apache ZooKeeper
- **支持版本**: 3.9.5, 3.8.6, 3.7.2
- **默认版本**: 3.9.5
- **安装方式**: binary（二进制包）
- **运行依赖**: JDK 8+（3.9+ 需要 JDK 11+）
- **运行用户**: zookeeper
- **默认端口**:
  - Client Port: 2181
  - Peer Port: 2888
  - Election Port: 3888
  - Admin Port: 8080
- **下载地址**: https://archive.apache.org/dist/zookeeper/zookeeper-{version}/apache-zookeeper-{version}-bin.tar.gz
- **健康检查**: 四字命令 `echo ruok | nc localhost 2181`

# 部署模式

1. **单机模式 (standalone)**: 单节点运行，适用于开发测试
2. **集群模式 (cluster)**: 3/5/7 节点集群，适用于生产环境

# 输出要求

请生成以下文件，每个文件的代码必须完整、可直接运行：

## 文件清单

### 1. `options.conf` — 中央配置文件
**要求**:
- ZooKeeper 安装路径、数据目录、日志目录
- 端口配置：client_port, peer_port, election_port, admin_port
- 部署模式：standalone / cluster
- 集群配置：cluster_nodes, myid
- JVM 配置：heap_size, jvm_opts
- JDK 路径：JAVA_HOME
- 备份配置：backup_dir, expired_days, backup_destination
- 告警配置：alert_email, webhook_url

### 2. `versions.txt` — 版本号清单
**要求**:
- 支持版本：zk39_ver=3.9.5, zk38_ver=3.8.6, zk37_ver=3.7.2
- 默认版本：zk_ver=3.9.5

### 3. `include/color.sh` — 颜色定义
**要求**:
- CSUCCESS(绿)、CFAILURE(红)、CWARNING(黄)、CMSG(青)、CEND(重置)

### 4. `include/check_os.sh` — 操作系统检测
**要求**:
- 输出变量: Platform, Family, PM, ARCH, THREAD
- 支持 CentOS/RHEL 7+, Debian 9+, Ubuntu 16+

### 5. `include/check_env.sh` — 环境检测
**要求**:
- `Check_JDK()` — 检测 JDK 是否安装及版本
- ZooKeeper 3.9+ 需要 JDK 11+，3.7/3.8 需要 JDK 8+
- 检测 JAVA_HOME 环境变量
- 检测 nc (netcat) 工具是否安装

### 6. `include/download.sh` — 下载函数
**要求**:
- `Download_src()` 函数
- 多源容错：Apache Archive → 镜像站
- 支持断点续传

### 7. `include/zookeeper.sh` — 安装/卸载模块
**要求**:
- `Install_ZooKeeper()` 函数：
  1. JDK 版本检测
  2. 已安装检测（幂等）
  3. 下载二进制包
  4. 解压到安装目录
  5. 生成 zoo.cfg 配置文件
  6. 集群模式：生成 myid 文件，添加 server.X 配置
  7. 生成 java.env JVM 配置
  8. 创建 zookeeper 用户
  9. 设置目录权限
  10. 注册 systemd 服务
  11. 启动服务
  12. 使用四字命令验证（ruok -> imok）
- `Uninstall_ZooKeeper()` 函数：
  1. 停止服务
  2. 禁用服务
  3. 数据目录重命名备份
  4. 删除安装目录
  5. 清理环境变量

### 8. `include/upgrade_zk.sh` — 升级模块
**要求**:
- `Upgrade_ZooKeeper()` 函数：
  1. 检测当前版本
  2. 版本校验（主版本一致性检查）
  3. 升级前备份（配置 + 数据）
  4. 下载新版本
  5. 停服务 → 替换 lib/bin 目录 → 保留配置
  6. 启动服务并验证
  7. 失败时自动回滚

### 9. `include/cluster.sh` — 集群管理模块
**要求**:
- `Deploy_Cluster()` — 部署集群（生成所有节点配置）
- `Add_Node()` — 添加节点（动态扩容）
- `Remove_Node()` — 移除节点
- `Check_Cluster_Status()` — 检查集群状态（Leader/Follower）

### 10. `include/monitor_zk.sh` — 监控模块
**要求**:
- `Check_ZK_Health()` — ruok 健康检查
- `Check_ZK_Status()` — srvr 状态检查（Mode/Connections/ZNode）
- `Check_ZK_Metrics()` — mntr 指标检查（延迟/请求数）
- `Check_ZK_Connections()` — cons 连接数检查
- `Check_ZK_Cluster()` — 集群状态检查
- `Send_Alert()` — 告警通知（邮件 + Webhook）

### 11. `install.sh` — 安装主入口
**要求**:
- getopt 参数：--help, --version, --quiet, --standalone, --cluster
- 参数：--zk_ver, --myid, --nodes
- 无参数时显示交互菜单（选择版本、部署模式）
- 安装完成显示摘要（版本、路径、端口、模式）

### 12. `uninstall.sh` — 卸载主入口
**要求**:
- 参数：--quiet, --keep-data
- 卸载前预览
- 数据目录备份

### 13. `upgrade.sh` — 升级主入口
**要求**:
- 参数：--zk_ver, --rolling
- 支持滚动升级（集群模式）

### 14. `backup.sh` — 备份执行脚本
**要求**:
- 备份快照文件 (snapshot.*)
- 备份事务日志 (log.*)
- 备份配置文件 (zoo.cfg, myid, java.env)
- 支持本地/OSS/S3 多目标
- 过期清理

### 15. `backup_setup.sh` — 备份配置向导
**要求**:
- 交互式配置备份策略
- 设置 cron 定时任务

### 16. `monitor.sh` — 监控主入口
**要求**:
- 参数：--status, --check
- 四字命令检测
- 集群状态检测
- 告警通知

### 17. `init.d/zookeeper.service` — systemd 服务文件
**要求**:
- Type=forking
- User=zookeeper
- ExecStart/Stop 使用 zkServer.sh
- 环境变量：JAVA_HOME, ZK_HOME, ZOOCFGDIR

### 18. `config/zoo.cfg` — 配置模板
**要求**:
- tickTime, initLimit, syncLimit
- dataDir, dataLogDir, clientPort
- admin.serverPort, admin.enableServer
- 4lw.commands.whitelist=*
- autopurge 配置

### 19. `config/java.env` — JVM 配置模板
**要求**:
- JAVA_HOME
- ZK_SERVER_HEAP
- SERVER_JVMFLAGS (G1GC 推荐)

# 代码规范约束

1. **Shell 版本**: #!/bin/bash，兼容 Bash 4.0+
2. **缩进**: 2 空格
3. **变量命名**: 小写 + 下划线（如 `zk_install_dir`）
4. **函数命名**: 大驼峰（如 `Install_ZooKeeper`, `Check_ZK_Health`）
5. **幂等性**: 已安装则跳过
6. **错误处理**: 关键操作失败时退出，数据操作前备份
7. **日志输出**: 使用 color.sh 颜色变量
8. **四字命令**: 使用 `echo "cmd" | nc -w 2 host port` 格式
9. **配置分离**: 可变参数放 options.conf，版本号放 versions.txt
10. **安全**: service 使用 zookeeper 用户运行
11. **兼容性**: 支持 x86_64 和 aarch64 架构

请基于以上规范，生成 Apache ZooKeeper 的完整运维代码。每个文件独立输出，包含完整可运行的代码。
```

---

## 提示词使用说明

### 如何使用

1. **复制上述提示词**（从 `# 角色` 到最后的 `请基于以上规范...`）
2. **粘贴到 AI 编程工具**（Cursor / Windsurf / ChatGPT 等）
3. AI 将生成一套完整的 ZooKeeper 运维脚本

### 快速部署示例

**单机模式安装：**
```bash
./install.sh --standalone --zk_ver 3.9.5
```

**集群模式安装：**
```bash
# 节点 1
./install.sh --cluster --zk_ver 3.9.5 --myid 1 --nodes "1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"

# 节点 2
./install.sh --cluster --zk_ver 3.9.5 --myid 2 --nodes "1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"

# 节点 3
./install.sh --cluster --zk_ver 3.9.5 --myid 3 --nodes "1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"
```

### 常用运维命令

```bash
# 查看状态
./monitor.sh --status

# 健康检查
./monitor.sh --check

# 升级版本
./upgrade.sh --zk_ver 3.9.5

# 备份数据
./backup.sh

# 卸载（保留数据）
./uninstall.sh --keep-data
```

---

# 附录：ZooKeeper 运维速查表

## A. 四字命令速查

| 命令 | 用途 | 示例 |
|------|------|------|
| `ruok` | 健康检查 | `echo ruok \| nc localhost 2181` → `imok` |
| `stat` | 服务状态 | 连接数、延迟、Leader/Follower |
| `srvr` | 服务器信息 | 版本、模式、节点数 |
| `mntr` | 监控指标 | Prometheus 格式 |
| `cons` | 客户端连接 | 连接列表详情 |
| `envi` | 环境信息 | JVM、OS 信息 |
| `conf` | 配置信息 | zoo.cfg 配置项 |
| `wchs` | Watch 统计 | Watch 数量 |
| `dump` | 会话信息 | 活跃会话和临时节点 |

## B. 常见问题排查

| 问题 | 排查命令 | 解决方案 |
|------|---------|---------|
| 服务无法启动 | `journalctl -u zookeeper` | 检查 JDK、端口占用、权限 |
| 集群无 Leader | `echo stat \| nc localhost 2181` | 检查 myid、节点连通性 |
| 连接数过高 | `echo cons \| nc localhost 2181` | 调整 maxClientCnxns |
| 延迟过高 | `echo mntr \| nc localhost 2181` | 检查磁盘 IO、网络 |
| 磁盘空间不足 | `du -sh ${dataDir}` | 调整 autopurge 参数 |

## C. 配置参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `tickTime` | 2000 | 心跳间隔（毫秒） |
| `initLimit` | 10 | Follower 初始同步超时（tickTime 倍数） |
| `syncLimit` | 5 | Follower 同步超时（tickTime 倍数） |
| `maxClientCnxns` | 60 | 单 IP 最大连接数（0=不限） |
| `autopurge.snapRetainCount` | 3 | 保留快照数量 |
| `autopurge.purgeInterval` | 1 | 清理间隔（小时，0=禁用） |

## D. JVM 调优建议

| 场景 | 堆内存 | GC 策略 |
|------|--------|---------|
| 开发测试 | 512m | 默认 |
| 小型生产 | 1g-2g | G1GC |
| 大型生产 | 4g-8g | G1GC + 调优 |

```bash
# 推荐 JVM 参数
export SERVER_JVMFLAGS="-Xms2g -Xmx2g -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
```

## E. 集群规模建议

| 节点数 | 容错能力 | 适用场景 |
|--------|---------|---------|
| 3 | 1 节点故障 | 小型生产 |
| 5 | 2 节点故障 | 中型生产 |
| 7 | 3 节点故障 | 大型生产 |

> **注意**: 节点数必须为奇数，超过 7 节点会增加选举延迟。
