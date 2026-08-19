# Chrony 运维代码生成提示词

> 本文档基于 `template/ops-code-template.md`（oneinstack 架构规范），为 **Chrony 时间同步服务** 定制。
> 包含两部分：**Part A 技术规格**（chrony 的领域知识与代码模式）和 **Part B AI 编程提示词**（可直接交给 AI 生成代码）。
> 支持 **单机时间同步（client）** 与 **集群时间同步（内网 NTP Server + 多客户端）** 两种场景。

---

# Part A: Chrony 技术规格

## 1. 软件概述

**Chrony** 是 NTP 协议的一个轻量级实现，用于服务器时间同步，在网络不稳定、间歇联网、虚拟机等场景下比传统 `ntpd` 收敛更快、精度更高。
自 RHEL/CentOS 7、Ubuntu 20.04 起，chrony 是**发行版默认时间同步服务**。

### 1.1 核心特性

- 快速收敛（`makestep` 可在启动时直接跳变校时）
- 支持作为 **NTP 客户端**（`chronyd` 同步上游）与 **NTP 服务端**（`allow` 对内网提供服务）
- 支持 `local stratum` 孤岛模式：外网不可达时仍能作为内网时间基准
- 支持 RTC 硬件时钟同步（`rtcsync`）
- 提供 `chronyc` 命令行进行运行时诊断

### 1.2 官方文档

| 资源 | 地址 |
|------|------|
| 官网 | https://chrony-project.org/ |
| 文档 | https://chrony-project.org/documentation.html |
| 配置手册 | https://chrony-project.org/doc/4.5/chrony.conf.html |
| chronyc 手册 | https://chrony-project.org/doc/4.5/chronyc.html |

### 1.3 版本参考

| 发行版 | chrony 版本 | 备注 |
|--------|------------|------|
| CentOS/RHEL 7 | 3.4 | 无 `pool` 指令部分选项 |
| CentOS/RHEL 8 / Rocky 8 | 4.2 | |
| RHEL 9 / Rocky 9 | 4.3+ | |
| Ubuntu 20.04 | 3.5 | |
| Ubuntu 22.04 | 4.2 | |
| Ubuntu 24.04 / Debian 12 | 4.5 | |
| 源码最新 | 4.6.1 | 仅在需要新特性时源码编译 |

> **安装方式默认 `package`（包管理器）**。chrony 是发行版基础组件，包管理器安装可自动处理 SELinux 策略、
> systemd unit、`/var/lib/chrony` 目录权限等；仅当发行版仓库版本过低且确有需求时才启用 `source` 源码编译。

## 2. 部署模式

### 2.1 单机模式 (standalone / client)

本机作为纯 NTP 客户端，直接同步公网或已有内网 NTP 源。

```
                    ┌──────────────┐
   公网 NTP 源  ───▶ │  本机 chronyd │
 (ntp.aliyun.com)    └──────────────┘
```

**配置要点**：
- 配置 2~4 个上游 `server`/`pool`，均带 `iburst`
- 不开启 `allow`（不对外提供服务）
- 关闭防火墙 123/udp 入站需求

### 2.2 集群模式 (cluster)

集群内选 1~2 台节点作为**内网 NTP Server**（同步公网上游），其余节点作为 **Client** 只同步内网 Server。
这样可保证：即使公网断开，集群内部时间仍严格一致（依靠 `local stratum`）。

```
                     ┌────────────────────┐
  公网 NTP 源 ──────▶ │  NTP Server 节点    │  allow 10.0.0.0/24
                     │  (chrony-server)   │  local stratum 10
                     └─────────┬──────────┘
                               │ 内网 123/udp
        ┌──────────────┬───────┴───────┬──────────────┐
        ▼              ▼               ▼              ▼
   Client node1   Client node2    Client node3   Client nodeN
```

| 角色 | 变量取值 | 说明 |
|------|---------|------|
| `server` | `chrony_role=server` | 同步公网上游 + 对内网 `allow` + `local stratum` 兜底 |
| `client` | `chrony_role=client` | 只同步 `ntp_server_hosts` 指定的内网 Server |

**集群一致性要求**：
1. 所有节点**时区必须一致**（默认 `Asia/Shanghai`），由 `timedatectl set-timezone` 统一设置
2. 所有节点必须**禁用** `ntpd` / `systemd-timesyncd` / `openntpd`，避免多个校时进程互相冲突
3. Server 节点必须放行 `123/udp`
4. 建议配置 2 台 Server 互为对等（`peer`），避免单点

## 3. 端口与进程说明

| 项目 | 值 | 说明 |
|------|-----|------|
| NTP 服务端口 | `123/udp` | 仅 Server 角色需对内网放行 |
| chronyc 命令端口 | `323/udp` | 默认仅监听 `127.0.0.1` / `::1`，通过 `bindcmdaddress` 控制 |
| 进程名 | `chronyd` | |
| systemd 服务名 | RHEL 系: `chronyd`；Debian/Ubuntu 系: `chrony` | 代码中必须用变量 `chrony_service` 适配 |
| 主配置文件 | RHEL 系: `/etc/chrony.conf`；Debian/Ubuntu 系: `/etc/chrony/chrony.conf` | 用变量 `chrony_conf` 适配 |
| 漂移文件 | RHEL: `/var/lib/chrony/drift`；Debian: `/var/lib/chrony/chrony.drift` | |
| 日志目录 | `/var/log/chrony` | |
| 密钥文件 | RHEL: `/etc/chrony.keys`；Debian: `/etc/chrony/chrony.keys` | |
| 运行用户 | RHEL: `chrony`；Debian: `_chrony` | 由包自动创建，脚本不需 useradd |

## 4. 目录结构规范

```
chrony/
├── install.sh                  # 安装主入口（交互/静默双模式，单机/集群）
├── uninstall.sh                # 卸载主入口
├── upgrade.sh                  # 升级主入口
├── cluster.sh                  # 集群批量部署/巡检（SSH 分发）
├── monitor.sh                  # 健康检查与状态监控
├── backup.sh                   # 配置备份执行脚本
├── backup_setup.sh             # 备份策略配置向导
├── options.conf.template       # 中央配置模板（git 跟踪，含 conf_version）
├── options.conf                # 运行时配置（.gitignore 忽略，自动生成）
├── versions.txt                # 版本号清单
├── .gitignore                  # 忽略 options.conf 及其备份
├── include/
│   ├── color.sh                #   终端颜色定义
│   ├── check_os.sh             #   OS 检测（Platform/Family/PM/ARCH/THREAD）
│   ├── check_env.sh            #   环境检测（冲突服务、时区、防火墙、SELinux）
│   ├── download.sh             #   下载函数（仅 source 安装方式使用）
│   ├── get_char.sh             #   交互输入辅助
│   ├── ensure_options_conf.sh  #   options.conf 模板化引导
│   ├── chrony.sh               #   Install_Chrony / Uninstall_Chrony
│   ├── chrony_config.sh        #   配置生成（Server/Client 两套模板渲染）
│   ├── cluster.sh              #   集群批量部署函数
│   ├── upgrade_chrony.sh       #   Upgrade_Chrony
│   └── monitor_chrony.sh       #   健康检查函数集
├── config/
│   ├── chrony-server.conf.template   # NTP Server 角色配置模板
│   └── chrony-client.conf.template   # NTP Client 角色配置模板
├── init.d/
│   └── chronyd.service         # systemd unit（仅 source 安装方式需要）
└── src/                        # 源码包存放目录（仅 source 安装方式）
```

## 5. 文件职责说明

### 5.1 主入口脚本

| 文件 | 职责 | 关键设计 |
|------|------|---------|
| `install.sh` | 安装入口：检测环境 → 停用冲突服务 → 安装 chrony → 渲染配置 → 启动 → 验证 | getopt + 交互菜单双模式；`--role server\|client` 决定配置模板 |
| `uninstall.sh` | 卸载：停服务 → 备份配置 → 卸载包 → 清理残留 | 配置文件 mv 备份而非删除 |
| `upgrade.sh` | 升级：包管理器 update 或源码替换 | 升级前备份 chrony.conf 与 drift |
| `cluster.sh` | 集群批量部署：SSH 分发脚本到各节点并按角色执行 | 依赖 sshtrust 已建立免密 |
| `monitor.sh` | 健康检查：进程/端口/同步状态/偏移量/源可达性 | 偏移量超阈值告警 |
| `backup.sh` | 备份 chrony.conf、chrony.keys、drift 文件 | 按 expired_days 清理 |

### 5.2 功能模块 (include/)

| 文件 | 核心函数 |
|------|---------|
| `check_env.sh` | `Check_Conflict_Service()`、`Check_Timezone()`、`Check_Firewall()`、`Check_SELinux()` |
| `chrony.sh` | `Install_Chrony()`、`Uninstall_Chrony()`、`Print_Chrony()` |
| `chrony_config.sh` | `Detect_Chrony_Path()`、`Generate_Server_Conf()`、`Generate_Client_Conf()`、`Apply_Chrony_Conf()` |
| `cluster.sh` | `Deploy_Cluster()`、`Deploy_Node()`、`Check_Cluster_Sync()`、`Rollout_Conf()` |
| `upgrade_chrony.sh` | `Upgrade_Chrony()` |
| `monitor_chrony.sh` | `Check_Process()`、`Check_Port()`、`Check_Tracking()`、`Check_Sources()`、`Check_Offset()`、`Check_Clients()`、`Send_Alert()`、`Monitor_Status()` |

## 6. 运维生命周期 — Chrony 专属流程

### 6.1 安装 (Install)

**流程模式：**
```
root 检查 → OS 检测 → 路径适配(chrony_conf/chrony_service) → 已安装检测(幂等)
→ 停用冲突服务(ntpd/systemd-timesyncd/openntpd) → 设置时区
→ 包管理器安装 chrony（或源码编译） → 备份原始 chrony.conf
→ 按 role 渲染配置 → 放行防火墙(Server 角色) → enable + restart
→ 强制立即校时(chronyc makestep) → 验证同步状态
```

**关键代码模式：**

```bash
# 1. 发行版路径适配（必须最先执行）
Detect_Chrony_Path() {
  case "${Family}" in
    rhel)
      chrony_conf=/etc/chrony.conf
      chrony_keys=/etc/chrony.keys
      chrony_service=chronyd
      chrony_user=chrony
      ;;
    debian|ubuntu)
      chrony_conf=/etc/chrony/chrony.conf
      chrony_keys=/etc/chrony/chrony.keys
      chrony_service=chrony
      chrony_user=_chrony
      ;;
  esac
  # 兼容：部分 Debian 新版软链到 /etc/chrony.conf
  [ ! -f "${chrony_conf}" ] && [ -f /etc/chrony.conf ] && chrony_conf=/etc/chrony.conf
}

# 2. 停用冲突的时间同步服务（chrony 与它们互斥）
Check_Conflict_Service() {
  for svc in ntpd ntp systemd-timesyncd openntpd; do
    if systemctl list-unit-files 2>/dev/null | grep -qw "^${svc}.service"; then
      if systemctl is-active --quiet ${svc}; then
        echo "${CWARNING}检测到冲突服务 ${svc} 正在运行，将停止并禁用${CEND}"
        systemctl stop ${svc} > /dev/null 2>&1
        systemctl disable ${svc} > /dev/null 2>&1
      fi
    fi
  done
  # 关闭 systemd-timesyncd 的 NTP 托管
  timedatectl set-ntp false > /dev/null 2>&1
}

# 3. 时区统一
Check_Timezone() {
  local cur_tz=$(timedatectl show -p Timezone --value 2>/dev/null)
  if [ "${cur_tz}" != "${timezone}" ]; then
    echo "${CMSG}时区 ${cur_tz} -> ${timezone}${CEND}"
    timedatectl set-timezone "${timezone}"
  fi
}

# 4. 幂等安装
if command -v chronyd > /dev/null 2>&1 && [ "${force_reinstall}" != 'y' ]; then
  echo "${CWARNING}Chrony already installed: $(chronyd -v | head -1)${CEND}"
  # 已安装则只做配置更新
  Apply_Chrony_Conf
else
  case "${install_method}" in
    package)
      if [ "${PM}" == 'yum' ]; then
        yum -y install chrony
      else
        apt-get update > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get -y install chrony
      fi
      ;;
    source)
      src_url="https://chrony-project.org/releases/chrony-${chrony_ver}.tar.gz"
      Download_src
      tar xzf chrony-${chrony_ver}.tar.gz
      pushd chrony-${chrony_ver} > /dev/null
      ./configure --prefix=/usr/local/chrony --sysconfdir=/etc --localstatedir=/var
      make -j ${THREAD} && make install
      popd > /dev/null
      /bin/cp ../init.d/chronyd.service /lib/systemd/system/
      systemctl daemon-reload
      rm -rf chrony-${chrony_ver}
      ;;
  esac
fi

# 5. 备份原始配置（只在第一次备份，避免覆盖原始副本）
[ -f "${chrony_conf}" ] && [ ! -f "${chrony_conf}.orig" ] && \
  /bin/cp -p ${chrony_conf} ${chrony_conf}.orig
[ -f "${chrony_conf}" ] && /bin/cp -p ${chrony_conf} ${chrony_conf}.$(date +%Y%m%d%H%M%S)

# 6. 启动并强制立即校时
systemctl enable ${chrony_service} > /dev/null 2>&1
systemctl restart ${chrony_service}
sleep 3
chronyc makestep > /dev/null 2>&1   # 首次强制跳变，不等待缓慢 slew

# 7. 安装后验证
if chronyc tracking > /dev/null 2>&1; then
  Leap=$(chronyc tracking | awk -F': *' '/Leap status/{print $2}')
  echo "${CSUCCESS}Chrony installed successfully! Leap status: ${Leap}${CEND}"
  chronyc sources -v
else
  echo "${CFAILURE}Chrony install failed!${CEND}"
  journalctl -u ${chrony_service} -n 30 --no-pager
  kill -9 $$; exit 1
fi
```

### 6.2 配置生成 (Config)

**Server 角色配置模板** `config/chrony-server.conf.template`：

```conf
# ===== Chrony NTP Server 配置（由 dmp_ops 自动生成，勿手工修改）=====
# 上游时间源
{{UPSTREAM_SERVERS}}

# 允许同步的内网网段（可多行）
{{ALLOW_NETWORKS}}

# 对等 Server（双 Server 高可用时启用）
{{PEER_SERVERS}}

# 外网不可达时以本机为孤岛时间基准，保证集群内部一致
local stratum {{LOCAL_STRATUM}}

# 系统时钟增益/损失速率记录
driftfile {{DRIFT_FILE}}

# 前 3 次校时若偏移大于 1 秒则直接跳变（而非缓慢 slew）
makestep 1.0 3

# 同步到 RTC 硬件时钟
rtcsync

# 闰秒处理策略
leapsectz right/UTC

# 命令端口监听地址（仅本机，安全）
bindcmdaddress 127.0.0.1
bindcmdaddress ::1

# 密钥文件
keyfile {{KEYS_FILE}}

# 日志
logdir /var/log/chrony
{{LOG_MEASUREMENTS}}
```

**Client 角色配置模板** `config/chrony-client.conf.template`：

```conf
# ===== Chrony NTP Client 配置（由 dmp_ops 自动生成，勿手工修改）=====
# 内网 NTP Server（集群模式）或公网上游（单机模式）
{{UPSTREAM_SERVERS}}

driftfile {{DRIFT_FILE}}
makestep 1.0 3
rtcsync
leapsectz right/UTC

# 客户端不对外提供服务
# allow 保持关闭

bindcmdaddress 127.0.0.1
bindcmdaddress ::1
keyfile {{KEYS_FILE}}
logdir /var/log/chrony
```

**渲染逻辑：**

```bash
Generate_Server_Conf() {
  local tmpl="${script_dir}/config/chrony-server.conf.template"
  local out=$(mktemp)

  # 上游源：公网或指定
  local upstream=""
  for s in $(echo ${upstream_ntp_servers} | tr ',' ' '); do
    upstream="${upstream}server ${s} iburst\n"
  done

  # allow 网段
  local allows=""
  for n in $(echo ${allow_networks} | tr ',' ' '); do
    allows="${allows}allow ${n}\n"
  done

  # peer（双 Server 互备）
  local peers=""
  for p in $(echo ${peer_servers} | tr ',' ' '); do
    [ -n "${p}" ] && peers="${peers}peer ${p}\n"
  done

  sed -e "s|{{UPSTREAM_SERVERS}}|${upstream}|" \
      -e "s|{{ALLOW_NETWORKS}}|${allows}|" \
      -e "s|{{PEER_SERVERS}}|${peers}|" \
      -e "s|{{LOCAL_STRATUM}}|${local_stratum}|" \
      -e "s|{{DRIFT_FILE}}|${drift_file}|" \
      -e "s|{{KEYS_FILE}}|${chrony_keys}|" \
      -e "s|{{LOG_MEASUREMENTS}}|${log_measurements}|" \
      "${tmpl}" > "${out}"
  # \n 展开
  printf '%b' "$(cat ${out})" > "${out}.rendered"
  Apply_Chrony_Conf "${out}.rendered"
}

Apply_Chrony_Conf() {
  local new_conf=$1
  # 语法校验：chronyd -Q 只做一次查询，不修改系统时钟
  if ! chronyd -Q -f "${new_conf}" > /dev/null 2>&1; then
    echo "${CFAILURE}生成的 chrony.conf 语法校验失败，已中止${CEND}"
    chronyd -Q -f "${new_conf}"
    return 1
  fi
  /bin/cp -f "${new_conf}" "${chrony_conf}"
  chmod 644 "${chrony_conf}"
  systemctl restart ${chrony_service}
}
```

### 6.3 集群部署 (Cluster)

**流程模式：**
```
读取节点清单 → 校验 SSH 免密 → 在 Server 节点执行 install.sh --role server
→ 等待 Server 同步就绪 → 并发在各 Client 节点执行 install.sh --role client
→ 全量巡检各节点 chronyc tracking → 输出集群时间偏差表
```

**关键代码模式：**

```bash
# 节点清单来自 options.conf:
#   ntp_server_hosts="10.0.0.11,10.0.0.12"
#   ntp_client_hosts="10.0.0.21,10.0.0.22,10.0.0.23"

Deploy_Node() {
  local host=$1 role=$2
  echo "${CMSG}[${host}] 部署 chrony (role=${role}) ...${CEND}"
  # 分发整个 chrony 目录
  ssh -p ${ssh_port} -o StrictHostKeyChecking=no ${ssh_user}@${host} "mkdir -p ${remote_dir}"
  scp -P ${ssh_port} -q -r ${script_dir}/* ${ssh_user}@${host}:${remote_dir}/
  ssh -p ${ssh_port} ${ssh_user}@${host} \
    "cd ${remote_dir} && bash install.sh --quiet --role ${role} \
     --ntp_servers '${ntp_server_hosts}' --timezone '${timezone}'"
  [ $? -eq 0 ] && echo "${CSUCCESS}[${host}] 部署成功${CEND}" \
                || echo "${CFAILURE}[${host}] 部署失败${CEND}"
}

Deploy_Cluster() {
  # 1. 先部署 Server（串行，确保时间基准先就绪）
  for h in $(echo ${ntp_server_hosts} | tr ',' ' '); do
    Deploy_Node "${h}" server
  done
  echo "${CMSG}等待 NTP Server 完成初次同步 ...${CEND}"
  sleep 10
  # 2. 再并发部署 Client
  for h in $(echo ${ntp_client_hosts} | tr ',' ' '); do
    Deploy_Node "${h}" client &
  done
  wait
  Check_Cluster_Sync
}

# 集群时间偏差巡检
Check_Cluster_Sync() {
  printf "%-18s %-10s %-14s %-12s %s\n" "HOST" "ROLE" "OFFSET(s)" "STRATUM" "LEAP"
  for h in $(echo "${ntp_server_hosts},${ntp_client_hosts}" | tr ',' ' '); do
    [ -z "${h}" ] && continue
    local out=$(ssh -p ${ssh_port} -o ConnectTimeout=5 ${ssh_user}@${h} \
                "chronyc tracking 2>/dev/null")
    local offset=$(echo "${out}" | awk -F': *' '/Last offset/{print $2}' | awk '{print $1}')
    local stratum=$(echo "${out}" | awk -F': *' '/Stratum/{print $2}')
    local leap=$(echo "${out}" | awk -F': *' '/Leap status/{print $2}')
    printf "%-18s %-10s %-14s %-12s %s\n" "${h}" "-" "${offset:-N/A}" "${stratum:-N/A}" "${leap:-N/A}"
  done
}
```

> **前置依赖**：集群模式需先用仓库中的 `sshtrust` 工具建立控制机到各节点的 SSH 免密：
> `../sshtrust/sshtrust.sh --add-file hosts.txt`

### 6.4 卸载 (Uninstall)

**流程模式：**
```
预览将删除/修改的内容 → 用户确认 → 停止并禁用 chronyd
→ 备份 chrony.conf / chrony.keys / drift → 卸载包（可选保留）
→ 恢复 chrony.conf.orig（如存在） → 回收防火墙规则 → 提示是否启用 systemd-timesyncd
```

```bash
Print_Chrony() {
  [ -f "${chrony_conf}" ] && echo "${chrony_conf}（将备份后恢复为 .orig）"
  [ -f "${drift_file}" ] && echo "${drift_file}"
  [ -d /var/log/chrony ] && echo "/var/log/chrony"
  echo "systemd 服务: ${chrony_service}（stop + disable）"
  [ "${keep_package}" == 'y' ] && echo "chrony 软件包: 保留" || echo "chrony 软件包: 卸载"
}

Uninstall_Chrony() {
  systemctl stop ${chrony_service} > /dev/null 2>&1
  systemctl disable ${chrony_service} > /dev/null 2>&1

  # 配置备份（重命名而非删除）
  [ -f "${chrony_conf}" ] && /bin/mv ${chrony_conf}{,.$(date +%Y%m%d%H%M%S)}
  [ -d /var/log/chrony ] && /bin/mv /var/log/chrony{,.$(date +%Y%m%d%H)}

  # 恢复发行版原始配置
  [ -f "${chrony_conf}.orig" ] && /bin/cp -p ${chrony_conf}.orig ${chrony_conf}

  # 卸载软件包
  if [ "${keep_package}" != 'y' ]; then
    [ "${PM}" == 'yum' ] && yum -y remove chrony || apt-get -y purge chrony
  fi

  # 收回防火墙放行
  command -v firewall-cmd > /dev/null 2>&1 && {
    firewall-cmd --permanent --remove-service=ntp > /dev/null 2>&1
    firewall-cmd --reload > /dev/null 2>&1
  }

  echo "${CMSG}Chrony uninstall completed! 系统当前无时间同步服务，"
  echo "如需回退到 systemd-timesyncd 请执行: timedatectl set-ntp true${CEND}"
}
```

### 6.5 升级 (Upgrade)

**流程模式：**
```
检测当前版本 → 获取可用版本 → 备份 chrony.conf + drift → 升级（yum update / apt upgrade / 源码替换）
→ 恢复配置 → 重启 → 验证 tracking 正常
```

```bash
Upgrade_Chrony() {
  command -v chronyd > /dev/null 2>&1 || {
    echo "${CWARNING}Chrony is not installed!${CEND}"; exit 1
  }
  OLD_ver=$(chronyd -v | grep -oE 'chronyd version [0-9.]+' | awk '{print $3}')
  echo "Current Version: ${CMSG}${OLD_ver}${CEND}"

  # 升级前备份（配置 + drift，drift 丢失会导致重新学习时钟漂移）
  bk=/tmp/chrony_upgrade_$(date +%Y%m%d%H%M%S)
  mkdir -p ${bk}
  /bin/cp -p ${chrony_conf} ${bk}/ 2>/dev/null
  /bin/cp -p ${drift_file} ${bk}/ 2>/dev/null
  /bin/cp -p ${chrony_keys} ${bk}/ 2>/dev/null
  echo "${CMSG}已备份到 ${bk}${CEND}"

  if [ "${install_method}" == 'package' ]; then
    [ "${PM}" == 'yum' ] && yum -y update chrony || \
      { apt-get update > /dev/null 2>&1; apt-get -y install --only-upgrade chrony; }
  else
    # 源码方式：下载新版本 → 编译 → 替换二进制
    src_url="https://chrony-project.org/releases/chrony-${NEW_ver}.tar.gz"
    Download_src
    # ... configure && make && make install ...
  fi

  # 包升级可能覆盖配置，恢复我们的版本
  /bin/cp -p ${bk}/$(basename ${chrony_conf}) ${chrony_conf} 2>/dev/null
  systemctl restart ${chrony_service}
  sleep 3

  NEW_ver_actual=$(chronyd -v | grep -oE 'chronyd version [0-9.]+' | awk '{print $3}')
  if chronyc tracking > /dev/null 2>&1; then
    echo "${CSUCCESS}Successfully upgrade from ${OLD_ver} to ${NEW_ver_actual}${CEND}"
  else
    echo "${CFAILURE}升级后服务异常，请检查 ${bk} 中的备份并手动回滚${CEND}"
    exit 1
  fi
}
```

### 6.6 备份 (Backup)

chrony 无业务数据，备份对象为**配置与状态文件**，体积极小，建议每日备份。

| 备份对象 | 路径 | 说明 |
|---------|------|------|
| 主配置 | `${chrony_conf}` | 核心 |
| 密钥 | `${chrony_keys}` | 启用认证时必需 |
| 漂移文件 | `${drift_file}` | 丢失后需重新学习时钟漂移（数小时） |
| RTC 校正 | `/var/lib/chrony/rtc` | 存在则备份 |

```bash
Chrony_Local_BK() {
  NewFile=${backup_dir}/chrony_$(hostname)_$(date +%Y%m%d_%H%M%S).tgz
  OldFile=${backup_dir}/chrony_$(hostname)_$(date +%Y%m%d --date="${expired_days} days ago")*.tgz
  [ -n "$(ls ${OldFile} 2>/dev/null)" ] && rm -f ${OldFile}
  mkdir -p ${backup_dir}
  tar czf ${NewFile} \
    ${chrony_conf} ${chrony_keys} ${drift_file} /var/lib/chrony/rtc 2>/dev/null
  [ $? -eq 0 ] && echo "${CSUCCESS}Backup OK: ${NewFile}${CEND}"
}
```

### 6.7 监控 (Monitor)

**核心指标**（全部来自 `chronyc`）：

| 指标 | 命令 | 判定 |
|------|------|------|
| 进程存活 | `pgrep -x chronyd` | 不存在 → CRITICAL，自动重启 |
| 端口监听 | `ss -unlp \| grep :123` | Server 角色未监听 → CRITICAL |
| 同步状态 | `chronyc tracking \| grep 'Leap status'` | 非 `Normal` → CRITICAL |
| 时间偏移 | `chronyc tracking \| grep 'Last offset'` | 绝对值 > `offset_threshold`（默认 1 秒）→ WARNING |
| 参考源 | `chronyc tracking \| grep 'Reference ID'` | 为 `00000000` / `7F7F0101(local)` → WARNING（未同步到真实源） |
| 可用源数 | `chronyc sources \| grep -c '^\^\*\|^\^+'` | 0 个 → CRITICAL |
| 层级 | `chronyc tracking \| grep Stratum` | > 10 → WARNING |
| 客户端数 | `chronyc clients`（Server 角色） | 数量骤降 → WARNING |

```bash
Check_Tracking() {
  local out=$(chronyc tracking 2>/dev/null)
  [ -z "${out}" ] && { Send_Alert "chronyc tracking 无响应"; return 1; }

  local leap=$(echo "${out}" | awk -F': *' '/Leap status/{print $2}')
  local refid=$(echo "${out}" | awk -F': *' '/Reference ID/{print $2}' | awk '{print $1}')
  local stratum=$(echo "${out}" | awk -F': *' '/Stratum/{print $2}')

  if [ "${leap}" != "Normal" ]; then
    echo "${CFAILURE}[CRITICAL] 时钟未同步, Leap status=${leap}${CEND}"
    Send_Alert "chrony 未同步: Leap status=${leap}"
    return 1
  fi
  if [ "${refid}" == "00000000" ]; then
    echo "${CWARNING}[WARNING] 无有效参考源 (Reference ID=00000000)${CEND}"
    Send_Alert "chrony 无有效参考源"
    return 1
  fi
  echo "${CSUCCESS}[OK] 同步正常 stratum=${stratum} refid=${refid}${CEND}"
  return 0
}

Check_Offset() {
  local offset=$(chronyc tracking 2>/dev/null | awk -F': *' '/Last offset/{print $2}' | awk '{print $1}')
  # 取绝对值（offset 可能带 + / - 号，单位秒，科学计数法需 awk 处理）
  local abs=$(awk -v v="${offset}" 'BEGIN{v=v<0?-v:v; printf "%.9f", v}')
  local exceed=$(awk -v a="${abs}" -v t="${offset_threshold}" 'BEGIN{print (a>t)?1:0}')
  if [ "${exceed}" == "1" ]; then
    echo "${CWARNING}[WARNING] 时间偏移 ${abs}s 超过阈值 ${offset_threshold}s${CEND}"
    Send_Alert "时间偏移 ${abs}s 超过阈值 ${offset_threshold}s"
    return 1
  fi
  echo "${CSUCCESS}[OK] 时间偏移 ${abs}s${CEND}"
  return 0
}

Monitor_Status() {
  echo "========== Chrony Status: $(date '+%F %T') =========="
  echo "版本      : $(chronyd -v | head -1)"
  echo "角色      : ${chrony_role}"
  echo "时区      : $(timedatectl show -p Timezone --value)"
  echo "系统时间  : $(date '+%F %T %Z')"
  echo "---- chronyc tracking ----"; chronyc tracking
  echo "---- chronyc sources -v ----"; chronyc sources -v
  echo "---- chronyc sourcestats ----"; chronyc sourcestats
  [ "${chrony_role}" == 'server' ] && { echo "---- chronyc clients ----"; chronyc clients; }
}
```

## 7. 配置文件规范

### 7.1 options.conf.template 结构

```bash
# ===== 配置版本号（勿手动修改，由 options.conf.template 同步）=====
conf_version=1

# ===== 安装方式 =====
# package: 包管理器安装（推荐，发行版默认组件）
# source : 源码编译安装（仅当仓库版本过低时使用）
install_method=package

# ===== 部署角色 =====
# server: 内网 NTP 服务端（同步公网 + 对内网提供服务）
# client: NTP 客户端（同步指定上游）
chrony_role=client

# ===== 部署模式 =====
# standalone: 单机（client 直连公网源）
# cluster   : 集群（server + 多 client）
deploy_mode=standalone

# ===== 时区（集群内必须一致）=====
timezone=Asia/Shanghai

# ===== 上游 NTP 源（server 角色 / 单机 client 使用，逗号分隔）=====
upstream_ntp_servers=ntp.aliyun.com,ntp1.aliyun.com,cn.pool.ntp.org,ntp.tuna.tsinghua.edu.cn

# ===== 内网 NTP Server 地址（cluster 模式下 client 指向它，逗号分隔）=====
ntp_server_hosts=

# ===== 集群 Client 节点清单（cluster.sh 批量部署用，逗号分隔）=====
ntp_client_hosts=

# ===== Server 角色专属 =====
# 允许同步的网段，逗号分隔，如 10.0.0.0/24,192.168.1.0/24
allow_networks=
# 对等 Server（双 Server 高可用），逗号分隔
peer_servers=
# 外网不可达时的孤岛层级（10 表示本机作为 stratum 10 时间源）
local_stratum=10

# ===== chrony 运行参数 =====
# 记录测量日志（调试用，生产可留空）
log_measurements=
# 是否自动放行防火墙 123/udp（server 角色）
open_firewall=y

# ===== SSH 批量部署（cluster 模式）=====
ssh_user=root
ssh_port=22
remote_dir=/tmp/dmp_ops_chrony

# ===== 监控告警 =====
# 时间偏移告警阈值（秒）
offset_threshold=1
alert_email=
webhook_url=
log_dir=/var/log/chrony

# ===== 备份配置 =====
backup_dir=/data/backup/chrony
expired_days=7
backup_destination=local
backup_content=conf

# ===== 自动检测（运行时由脚本填充，勿手动修改）=====
chrony_conf=
chrony_keys=
chrony_service=
drift_file=
```

### 7.2 versions.txt 结构

```bash
# Chrony 版本号清单
# package 方式安装时忽略本文件，由发行版仓库决定版本
chrony_ver=4.6.1

# 各发行版仓库默认版本（参考）
# rhel7_chrony_ver=3.4
# rhel8_chrony_ver=4.2
# rhel9_chrony_ver=4.3
# ubuntu2204_chrony_ver=4.2
# ubuntu2404_chrony_ver=4.5
```

### 7.3 .gitignore 内容

```
# 运行时生成的配置文件（由 options.conf.template 同步，勿提交）
options.conf
options.conf.bak
options.conf.bak.*
options.conf.[0-9]*
src/*.tar.gz
```

## 8. systemd 服务文件

> **package 安装方式无需本文件**，发行版已自带 unit。仅 `source` 安装方式需要。

`init.d/chronyd.service`：

```ini
[Unit]
Description=chrony NTP client/server
After=network.target
Conflicts=ntpd.service systemd-timesyncd.service openntpd.service

[Service]
Type=forking
PIDFile=/run/chrony/chronyd.pid
PermissionsStartOnly=true
ExecStartPre=/bin/mkdir -p /run/chrony
ExecStartPre=/bin/chown chrony:chrony /run/chrony
ExecStart=/usr/local/chrony/sbin/chronyd -f /etc/chrony.conf
ExecStopPost=/bin/rm -f /run/chrony/chronyd.sock
Restart=always
RestartSec=5
PrivateTmp=yes
ProtectHome=yes
ProtectSystem=full

[Install]
WantedBy=multi-user.target
```

## 9. 命令行参数设计

### 9.1 install.sh

| 参数 | 说明 | 示例 |
|------|------|------|
| `-h, --help` | 显示帮助 | |
| `-v, --version` | 显示脚本版本 | |
| `-q, --quiet` | 静默模式，跳过确认 | |
| `--role` | 部署角色 server/client | `--role server` |
| `--mode` | 部署模式 standalone/cluster | `--mode cluster` |
| `--ntp_servers` | 上游/内网 Server 地址（逗号分隔） | `--ntp_servers 10.0.0.11,10.0.0.12` |
| `--allow` | Server 允许的网段（逗号分隔） | `--allow 10.0.0.0/24` |
| `--peer` | 对等 Server | `--peer 10.0.0.12` |
| `--timezone` | 时区 | `--timezone Asia/Shanghai` |
| `--install_method` | package/source | `--install_method package` |
| `--force` | 已安装时强制重装/重写配置 | |

### 9.2 cluster.sh

| 参数 | 说明 |
|------|------|
| `--deploy` | 批量部署全集群（先 Server 后 Client） |
| `--add-client HOST[,HOST]` | 新增 Client 节点并部署 |
| `--rollout` | 只重新分发配置并重启，不重装 |
| `--check` | 巡检全集群同步状态与偏差 |
| `--hosts-file FILE` | 从文件读取节点清单 |

### 9.3 monitor.sh

| 参数 | 说明 |
|------|------|
| `--check` | 执行健康检查（cron 用） |
| `--status` | 输出完整状态报告 |
| `--sources` | 只显示时间源列表 |
| `--clients` | 只显示客户端列表（Server 角色） |

### 9.4 典型用法

```bash
# --- 单机模式 ---
./install.sh                                      # 交互式
./install.sh --quiet --role client --mode standalone \
             --ntp_servers ntp.aliyun.com,cn.pool.ntp.org

# --- 集群模式：在 NTP Server 节点上 ---
./install.sh --quiet --role server --mode cluster \
             --ntp_servers ntp.aliyun.com --allow 10.0.0.0/24 --peer 10.0.0.12

# --- 集群模式：在 Client 节点上 ---
./install.sh --quiet --role client --mode cluster --ntp_servers 10.0.0.11,10.0.0.12

# --- 集群模式：控制机一键批量部署（需先建立 SSH 免密）---
../sshtrust/sshtrust.sh --add-file hosts.txt
./cluster.sh --deploy
./cluster.sh --check

# --- 日常运维 ---
./monitor.sh --status
./monitor.sh --check          # 加入 cron: */5 * * * * /opt/dmp_ops/chrony/monitor.sh --check
./upgrade.sh
./uninstall.sh --quiet --keep_package
```

## 10. chronyc 常用诊断命令速查

```bash
chronyc tracking          # 当前同步状态（最重要）：参考源、层级、偏移、频率
chronyc sources -v        # 所有时间源及其状态（^* 当前源, ^+ 备选, ^- 被排除, ? 不可达）
chronyc sourcestats -v    # 各源的偏移/漂移统计
chronyc clients           # 本机作为 Server 时的客户端列表（需 root）
chronyc activity          # 在线/离线源数量概览
chronyc makestep          # 立即强制跳变校时（不等 slew）
chronyc burst 4/4         # 立即发起一轮快速测量
chronyc ntpdata           # 最近一次 NTP 报文详情
timedatectl status        # 系统时钟/时区/NTP 托管状态总览
```

**`chronyc sources` 状态符号含义：**

| 符号 | 含义 |
|------|------|
| `^*` | 当前同步的源（最佳） |
| `^+` | 可接受的备选源 |
| `^-` | 被合并算法排除的源 |
| `^?` | 不可达 / 尚未建立连接 |
| `^x` | 被判定为"假源"（falseticker） |
| `^~` | 抖动过大，可靠性低 |

---

# Part B: AI 编程完整提示词

> 以下提示词可直接复制给 AI 编程工具，生成 chrony 完整运维代码。

```markdown
# 角色

你是一位资深的 Linux 运维自动化工程师，精通 Bash Shell 编程、systemd 服务管理与 NTP/chrony 时间同步。
你的任务是为 **Chrony 时间同步服务** 编写一套完整的运维自动化脚本，需同时支持
**单机时间同步** 与 **集群时间同步（内网 NTP Server + 多 Client）** 两种场景。

# 软件信息

| 项目 | 值 |
|------|-----|
| SOFTWARE_NAME | Chrony |
| INSTALL_METHOD | package（默认，yum/apt）+ source（可选，chrony-4.6.1） |
| 进程名 | chronyd |
| systemd 服务名 | RHEL 系 `chronyd` / Debian 系 `chrony`（必须变量化适配） |
| 主配置文件 | RHEL 系 `/etc/chrony.conf` / Debian 系 `/etc/chrony/chrony.conf`（必须变量化适配） |
| 运行用户 | RHEL `chrony` / Debian `_chrony`（由包创建，不需 useradd） |
| 服务端口 | 123/udp（Server 角色）、323/udp（chronyc，仅本机） |
| 漂移文件 | `/var/lib/chrony/drift`（RHEL）/ `/var/lib/chrony/chrony.drift`（Debian） |
| 默认时区 | Asia/Shanghai |
| 默认上游源 | ntp.aliyun.com, ntp1.aliyun.com, cn.pool.ntp.org, ntp.tuna.tsinghua.edu.cn |
| 健康检查 | `chronyc tracking` / `chronyc sources -v`（无 HTTP 接口） |

# 部署模式

1. **standalone（单机）**：本机 client 角色，直连公网 NTP 源。
2. **cluster（集群）**：1~2 台 server 角色节点同步公网并 `allow` 内网网段、配置 `local stratum 10` 兜底；
   其余节点 client 角色只指向内网 server。控制机通过 SSH 批量部署与巡检。

# 输出要求

请生成以下文件，每个文件的代码必须完整、可直接运行：

## 文件清单

### 1. `options.conf.template` — 中央配置模板
- 顶部包含 `conf_version=1`
- 分组：安装方式 / 部署角色与模式 / 时区 / 上游源 / 集群节点 / Server 专属(allow_networks, peer_servers, local_stratum)
  / SSH 批量部署 / 监控告警(offset_threshold, alert_email, webhook_url) / 备份 / 自动检测字段
- 自动检测字段（chrony_conf、chrony_keys、chrony_service、drift_file）默认留空，运行时由脚本探测填充

### 2. `.gitignore`
忽略 `options.conf`、`options.conf.bak*`、`options.conf.[0-9]*`、`src/*.tar.gz`

### 3. `versions.txt` — 版本号清单
`chrony_ver=4.6.1`，并注释列出各发行版仓库默认版本

### 4. `include/color.sh`
提供 `CSUCCESS`(绿) / `CFAILURE`(红) / `CWARNING`(黄) / `CMSG`(青) / `CEND`(重置)

### 5. `include/check_os.sh`
支持 CentOS/RHEL 7+、Rocky/Alma、Debian 9+、Ubuntu 18+、麒麟/统信等国产化衍生版；
输出 `Platform`、`Family`(rhel/debian/ubuntu)、`PM`(yum/dnf/apt-get)、`ARCH`(x86_64/aarch64)、`THREAD`、`VERSION_MAIN_ID`

### 6. `include/check_env.sh` — 环境检测
- `Check_Conflict_Service()`：检测并停止禁用 ntpd / ntp / systemd-timesyncd / openntpd，执行 `timedatectl set-ntp false`
- `Check_Timezone()`：对比并统一时区（`timedatectl set-timezone ${timezone}`）
- `Check_Firewall()`：Server 角色时放行 123/udp（firewalld 用 `--add-service=ntp`，ufw 用 `allow 123/udp`，iptables 兜底）
- `Check_SELinux()`：SELinux enforcing 时提示（chrony 默认策略已允许，无需关闭 SELinux）
- `Check_Network()`：探测上游源可达性（`chronyd -Q` 或 `ping`/`nc -uz`），不可达时警告但不中断

### 7. `include/download.sh`
`Download_src()` 多源容错（chrony-project.org → 镜像），检测 HTML 错误页，支持 `wget -c`。仅 source 方式使用。

### 8. `include/ensure_options_conf.sh`
`Ensure_Options_Conf <module_dir>`：三态判定（不存在→从模板创建；conf_version 一致→沿用；不一致→备份后重建）。
备份命名：有版本号 `options.conf.<旧版本>`，无版本号 `options.conf.bak`，重名追加序号。

### 9. `include/chrony_config.sh` — 路径适配与配置生成
- `Detect_Chrony_Path()`：按 Family 设置 `chrony_conf`、`chrony_keys`、`chrony_service`、`chrony_user`、`drift_file`，
  并回写到 options.conf（`sed -i "s@^chrony_conf=.*@chrony_conf=${chrony_conf}@"`）
- `Generate_Server_Conf()`：渲染 `config/chrony-server.conf.template`（上游 server iburst、allow 网段、peer、
  local stratum、driftfile、makestep 1.0 3、rtcsync、leapsectz、bindcmdaddress、keyfile、logdir）
- `Generate_Client_Conf()`：渲染 `config/chrony-client.conf.template`（只含上游源，无 allow / local）
- `Apply_Chrony_Conf()`：**写入前必须用 `chronyd -Q -f <file>` 做语法校验**，失败则中止且不覆盖现有配置；
  成功则备份现配置（带时间戳）后覆盖并 `systemctl restart`

### 10. `include/chrony.sh` — 安装/卸载模块
- `Install_Chrony()`：
  1. `Detect_Chrony_Path`
  2. 幂等检测（已安装且非 --force 时只更新配置，不重装包）
  3. `Check_Conflict_Service` + `Check_Timezone`
  4. 包管理器安装（yum/dnf/apt，apt 需 `DEBIAN_FRONTEND=noninteractive`）或源码编译
  5. 首次安装时保存 `${chrony_conf}.orig` 原始副本
  6. 按 `chrony_role` 渲染并应用配置
  7. `Check_Firewall`（Server 角色）
  8. `systemctl enable` + `restart`，sleep 3 后执行 `chronyc makestep` 强制立即校时
  9. 验证：`chronyc tracking` 可用且 Leap status 正常，打印 `chronyc sources -v`
  10. 失败时打印 `journalctl -u ${chrony_service} -n 30 --no-pager` 并退出
- `Print_Chrony()`：卸载预览
- `Uninstall_Chrony()`：停服务 → 禁用 → 配置/日志 mv 备份 → 恢复 .orig → 可选卸载包（`--keep_package` 保留）
  → 收回防火墙规则 → 提示回退 systemd-timesyncd 的命令

### 11. `include/cluster.sh` — 集群批量部署模块
- `Load_Hosts()`：从 options.conf 或 `--hosts-file` 读取节点清单，支持 `host` / `user@host` / `user@host:port` 格式
- `Check_SSH()`：校验各节点 SSH 免密可达，不可达时提示先用 `../sshtrust/sshtrust.sh` 建立互信
- `Deploy_Node(host, role)`：scp 分发整个目录到 `${remote_dir}`，远端执行 `install.sh --quiet --role <role> ...`
- `Deploy_Cluster()`：**先串行部署 Server 并等待其同步就绪（sleep + 轮询 tracking），再并发部署 Client**
- `Add_Client(hosts)`：增量添加 Client 节点
- `Rollout_Conf()`：只重新渲染分发配置并重启，不重装软件包
- `Check_Cluster_Sync()`：SSH 到各节点采集 `chronyc tracking`，输出对齐表格
  （HOST / ROLE / STRATUM / LAST_OFFSET / LEAP / REF_ID），并高亮偏移超阈值的节点

### 12. `include/upgrade_chrony.sh` — 升级模块
`Upgrade_Chrony()`：检测当前版本 → 升级前备份（chrony.conf + drift + keys 到 /tmp 带时间戳目录）
→ `yum update chrony` / `apt install --only-upgrade chrony` / 源码替换 → **恢复被包覆盖的配置**
→ 重启 → 验证 tracking，失败时提示备份目录以便回滚

### 13. `include/monitor_chrony.sh` — 监控模块
`Check_Process()`（不存在则自动 `systemctl restart` 并二次确认）、`Check_Port()`（Server 角色查 123/udp）、
`Check_Tracking()`（Leap status 必须 Normal，Reference ID 不得为 00000000）、
`Check_Sources()`（至少 1 个 `^*` 或 `^+` 源）、`Check_Offset()`（用 awk 取绝对值并与 `offset_threshold` 比较，
注意 offset 可能为科学计数法）、`Check_Clients()`（Server 角色统计客户端数）、
`Check_Disk()`、`Send_Alert()`（写 `${log_dir}/monitor.log` + 邮件 + Webhook）、
`Monitor_Status()`（版本/角色/时区/系统时间/tracking/sources -v/sourcestats/clients）

### 14. `install.sh` — 安装主入口
- 文件头：`export PATH=...`、root 检查、`script_dir=$(cd "$(dirname "$0")" && pwd)`
- source 顺序：`ensure_options_conf.sh` → `Ensure_Options_Conf "${script_dir}"` → `options.conf` → `color.sh` → 其余模块
- getopt 解析：`-h/--help`、`-v/--version`、`-q/--quiet`、`--role`、`--mode`、`--ntp_servers`、`--allow`、
  `--peer`、`--timezone`、`--install_method`、`--force`
- 无参数时交互菜单：选择部署模式 → 选择角色 → 输入上游源/内网 Server → 输入 allow 网段（Server）→ 确认时区
- 所有交互结果 `sed -i` 持久化回 options.conf
- 完成后打印摘要：版本、角色、配置文件路径、服务名、上游源、allow 网段、当前 tracking 概要

### 15. `uninstall.sh` — 卸载主入口
getopt：`-q/--quiet`、`--keep_package`、`--keep_conf`；先 `Print_Chrony()` 预览 → 确认 → `Uninstall_Chrony()`

### 16. `upgrade.sh` — 升级主入口
getopt：`-q/--quiet`、`--version [x.x.x]`（source 方式）；无参数时显示当前版本并确认后升级

### 17. `cluster.sh` — 集群管理主入口
getopt：`--deploy`、`--add-client HOST[,HOST]`、`--rollout`、`--check`、`--hosts-file FILE`、`-q/--quiet`；
无参数时显示交互菜单

### 18. `monitor.sh` — 监控主入口
getopt：`--check`、`--status`、`--sources`、`--clients`；默认行为等同 `--status`；
`--check` 输出精简、异常时退出码非 0（便于 cron/Zabbix 采集）

### 19. `backup.sh` — 备份执行脚本
备份 `${chrony_conf}`、`${chrony_keys}`、`${drift_file}`、`/var/lib/chrony/rtc`；
文件名 `chrony_$(hostname)_%Y%m%d_%H%M%S.tgz`；按 `expired_days` 清理；支持 local / remote(rsync/scp) 目标

### 20. `backup_setup.sh` — 备份配置向导
交互选择备份目标与保留天数，写回 options.conf，并写入 cron（`0 3 * * *`）

### 21. `config/chrony-server.conf.template`
含占位符 `{{UPSTREAM_SERVERS}}`、`{{ALLOW_NETWORKS}}`、`{{PEER_SERVERS}}`、`{{LOCAL_STRATUM}}`、
`{{DRIFT_FILE}}`、`{{KEYS_FILE}}`、`{{LOG_MEASUREMENTS}}`

### 22. `config/chrony-client.conf.template`
含占位符 `{{UPSTREAM_SERVERS}}`、`{{DRIFT_FILE}}`、`{{KEYS_FILE}}`

### 23. `init.d/chronyd.service`
仅 source 安装方式使用；`Type=forking`、`Conflicts=ntpd.service systemd-timesyncd.service`、`Restart=always`

### 24. `README.md`
使用说明：目录结构、单机/集群快速开始、参数表、chronyc 诊断速查、常见问题（时间跳变影响数据库、
容器内无法校时、虚拟机 host 时间同步冲突、防火墙未放行 123/udp）

# 代码规范约束

1. **Shell 版本**: `#!/bin/bash`，兼容 Bash 4.0+
2. **缩进**: 2 空格
3. **变量命名**: 小写 + 下划线；常量大写（`THREAD`、`PM`、`ARCH`）
4. **函数命名**: 大驼峰（`Install_Chrony`、`Check_Tracking`）
5. **幂等性**: 重复执行安装不报错；已安装时只更新配置
6. **发行版适配**: 严禁硬编码 `/etc/chrony.conf` 或 `chronyd` 服务名，一律用 `${chrony_conf}` / `${chrony_service}`
7. **配置安全**: 覆盖 chrony.conf 前必须 `chronyd -Q -f` 语法校验 + 带时间戳备份；首次安装保留 `.orig`
8. **冲突互斥**: 安装前必须停用 ntpd / systemd-timesyncd / openntpd
9. **错误处理**: 关键失败 `kill -9 $$; exit 1`，并打印 `journalctl` 最近日志
10. **日志输出**: 统一使用 color.sh 颜色变量
11. **PATH**: 脚本开头 `export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin`
12. **root 检查**: `[ $(id -u) != "0" ] && { echo "Error: must be root"; exit 1; }`
13. **配置分离**: 可变参数放 `options.conf.template`（含 `conf_version`），版本号放 `versions.txt`；
    入口脚本 source `options.conf` 前必须先调用 `Ensure_Options_Conf`
14. **集群安全**: SSH 批量操作前必须校验免密可达；并发部署用 `&` + `wait`，单节点失败不影响其他节点
15. **兼容性**: 支持 x86_64 / aarch64，支持 RHEL 7-9、Rocky/Alma、Debian 10+、Ubuntu 18.04+
16. **时间安全**: `chronyc makestep` 会导致时间跳变，脚本中必须提示"数据库/中间件在运行时慎用"

# 关键实现提示

1. **`chronyc tracking` 输出解析**用 `awk -F': *'`，字段名含空格（如 `Leap status`、`Last offset`）
2. **offset 可能是科学计数法**（如 `1.234e-06`），比较必须用 awk 数值运算而非 shell 整数比较
3. **Debian 系 apt 安装**需 `DEBIAN_FRONTEND=noninteractive`，避免交互卡住
4. **Debian 12+ 的 chrony 配置**可能包含 `sourcedir /run/chrony-dhcp`，DHCP 会注入源，
   生成配置时应保留或显式说明已移除
5. **集群 Server 就绪判定**：轮询 `chronyc tracking` 直到 `Leap status` 为 `Normal` 或超时（默认 60s）
6. **`local stratum 10`** 是集群一致性的关键：公网断开时 Server 仍以本地时钟对外服务，
   Client 继续跟随，保证集群内部相对一致
7. **容器环境**：容器内通常无法修改时钟（缺少 `CAP_SYS_TIME`），脚本应检测并明确报错提示在宿主机部署

请基于以上规范，生成 **Chrony** 的完整运维代码。每个文件独立输出，包含完整可运行的代码。
```

---

# 附录：常见问题与运维要点

| 问题 | 原因 | 处理 |
|------|------|------|
| `chronyc sources` 全是 `^?` | 防火墙拦截 123/udp 出站，或上游源不可达 | 检查出站规则、更换上游源 |
| `Reference ID : 00000000 ()` | 尚未选定任何源 | 等待 1~2 分钟或 `chronyc burst 4/4` |
| 时间不同步但服务正常 | 存在 ntpd/systemd-timesyncd 抢占 | `Check_Conflict_Service` 停用冲突服务 |
| Client 连不上内网 Server | Server 未 `allow` 该网段，或未放行 123/udp | 检查 `allow` 配置与 firewalld |
| 公网断开后集群时间漂移 | Server 未配置 `local stratum` | Server 配置 `local stratum 10` |
| 容器内校时失败 | 缺少 `CAP_SYS_TIME` | 在宿主机部署 chrony，容器共享宿主时钟 |
| 升级后配置被覆盖 | 包管理器替换了 chrony.conf | 升级流程中先备份、升级后恢复 |
| 数据库出现异常时间跳变 | 执行了 `chronyc makestep` | 仅在初次安装/维护窗口执行 makestep |

# 参考文档

- [Chrony 官方文档](https://chrony-project.org/documentation.html)
- [chrony.conf 配置手册](https://chrony-project.org/doc/4.5/chrony.conf.html)
- [chronyc 命令手册](https://chrony-project.org/doc/4.5/chronyc.html)
- [RHEL 9 — Configuring time synchronization](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_basic_system_settings/configuring-time-synchronization_configuring-basic-system-settings)
- [Ubuntu Server — Time Synchronisation](https://documentation.ubuntu.com/server/how-to/networking/use-timedatectl-and-timesyncd/)
- 本仓库 SSH 免密工具：`../sshtrust/README.md`
