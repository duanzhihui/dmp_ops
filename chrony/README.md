# Chrony 时间同步运维工具

基于 oneinstack 架构规范的 chrony 运维脚本集，支持**单机时间同步**与**集群时间同步**（内网 NTP Server + 多客户端）。

## 功能特性

- **两种部署模式**：standalone（单机直连公网源）/ cluster（内网 NTP Server + Client）
- **两种节点角色**：server（对内网提供 NTP 服务，支持 `local stratum` 断网兜底）/ client
- **发行版自适应**：自动识别 RHEL 系（`chronyd` + `/etc/chrony.conf`）与 Debian/Ubuntu 系（`chrony` + `/etc/chrony/chrony.conf`）
- **冲突服务自动处理**：安装前自动停用 ntpd / systemd-timesyncd / openntpd
- **配置安全**：写入前 `chronyd -p` 语法校验，保留发行版原始配置 `.orig`，每次变更带时间戳备份
- **集群批量部署**：SSH 分发，先串行部署 Server 并等待就绪，再并发部署 Client
- **集群巡检**：一条命令输出全集群 stratum / offset / leap 对齐表
- **监控告警**：进程、端口、同步状态、偏移量、可用源、客户端数，支持邮件与 Webhook
- **交互/静默双模式**：无参数走交互菜单，有参数静默执行

## 目录结构

```
chrony/
├── install.sh                  # 安装主入口
├── uninstall.sh                # 卸载主入口
├── upgrade.sh                  # 升级主入口
├── cluster.sh                  # 集群批量部署/巡检
├── monitor.sh                  # 健康检查与状态监控
├── backup.sh                   # 配置备份（cron 调用）
├── backup_setup.sh             # 备份策略配置向导
├── options.conf.template       # 中央配置模板（git 跟踪）
├── options.conf                # 运行时配置（自动生成，.gitignore）
├── versions.txt                # 版本号清单
├── include/
│   ├── color.sh                # 终端颜色
│   ├── check_os.sh             # OS 检测
│   ├── check_env.sh            # 冲突服务/时区/防火墙/SELinux/容器检测
│   ├── download.sh             # 下载函数（source 安装用）
│   ├── get_char.sh             # 交互辅助
│   ├── ensure_options_conf.sh  # options.conf 模板化引导
│   ├── chrony_config.sh        # 路径适配与配置渲染
│   ├── chrony.sh               # 安装/卸载
│   ├── cluster.sh              # 集群批量部署
│   ├── upgrade_chrony.sh       # 升级
│   └── monitor_chrony.sh       # 监控检查
├── config/
│   ├── chrony-server.conf.template
│   └── chrony-client.conf.template
├── init.d/chronyd.service      # systemd unit（仅 source 安装方式需要）
└── src/                        # 源码包存放目录
```

## 快速开始

### 单机时间同步

```bash
# 交互式
./install.sh

# 静默：同步公网源
./install.sh --quiet --role client --mode standalone \
             --ntp_servers ntp.aliyun.com,cn.pool.ntp.org

# 查看状态
./monitor.sh --status
```

### 集群时间同步

架构：1~2 台内网 NTP Server 同步公网上游，其余节点作为 Client 同步内网 Server。
公网断开时 Server 以 `local stratum 10` 继续对内服务，保证集群内部时间一致。

**方式一：逐节点部署**

```bash
# NTP Server 节点（10.0.0.11）
./install.sh --quiet --role server --mode cluster \
             --ntp_servers ntp.aliyun.com,cn.pool.ntp.org \
             --allow 10.0.0.0/24 --peer 10.0.0.12

# Client 节点
./install.sh --quiet --role client --mode cluster --ntp_servers 10.0.0.11,10.0.0.12
```

**方式二：控制机一键批量部署（推荐）**

```bash
# 1. 建立 SSH 免密（使用仓库中的 sshtrust 工具）
../sshtrust/sshtrust.sh --add 10.0.0.11 10.0.0.12 10.0.0.21 10.0.0.22

# 2. 准备节点清单
cat > hosts.txt << 'EOF'
# 角色 主机
server 10.0.0.11
server 10.0.0.12
client 10.0.0.21
client 10.0.0.22
client root@10.0.0.23:2222
EOF

# 3. 配置上游源与允许网段（也可直接编辑 options.conf）
sed -i 's@^allow_networks=.*@allow_networks=10.0.0.0/24@' options.conf

# 4. 批量部署
./cluster.sh --hosts-file hosts.txt --deploy

# 5. 巡检
./cluster.sh --check
```

巡检输出示例：

```
HOST                 ROLE     STRATUM   LAST_OFFSET(s)   LEAP       REF_ID
----------------------------------------------------------------------------
10.0.0.11            server   3         +1.234e-05       Normal     CF2E4A02
10.0.0.12            server   3         -8.100e-06       Normal     CF2E4A02
10.0.0.21            client   4         +2.300e-05       Normal     0A00000B
10.0.0.22            client   4         +1.900e-05       Normal     0A00000B
```

## 命令行参数

### install.sh

| 参数 | 说明 |
|------|------|
| `-h, --help` | 显示帮助 |
| `-v, --version` | 显示版本 |
| `-q, --quiet` | 静默模式 |
| `--role server\|client` | 部署角色 |
| `--mode standalone\|cluster` | 部署模式 |
| `--ntp_servers LIST` | 时间源（逗号分隔） |
| `--allow LIST` | Server 允许同步的网段 |
| `--peer LIST` | 对等 Server |
| `--timezone TZ` | 时区（默认 Asia/Shanghai） |
| `--install_method package\|source` | 安装方式 |
| `--no_makestep` | 安装后不强制校时 |
| `--force` | 已安装时强制重装 |

### cluster.sh

| 参数 | 说明 |
|------|------|
| `--deploy` | 批量部署全集群 |
| `--add-client HOST[,HOST]` | 新增 Client 节点 |
| `--rollout` | 只重新分发配置并重启 |
| `--check` | 巡检全集群同步状态 |
| `--hosts-file FILE` | 从文件读取节点清单 |

### monitor.sh

| 参数 | 说明 |
|------|------|
| `--check` | 健康检查（异常退出码非 0，适合 cron/Zabbix） |
| `--status` | 完整状态报告（默认） |
| `--sources` | 只显示时间源列表 |
| `--clients` | 只显示客户端列表（Server 角色） |

### uninstall.sh / upgrade.sh

```bash
./uninstall.sh --quiet --keep_package   # 只停服务还原配置，保留软件包
./upgrade.sh                            # 包管理器升级（自动备份 conf/drift/keys）
```

## 配置说明

配置文件 `options.conf` 由 `options.conf.template` 自动生成（**勿提交 git**）。
模板变更时会递增 `conf_version`，用户下次执行脚本自动备份旧配置并重建。

常用配置项：

```bash
chrony_role=client                  # server / client
deploy_mode=standalone              # standalone / cluster
timezone=Asia/Shanghai              # 集群内必须一致
upstream_ntp_servers=ntp.aliyun.com,cn.pool.ntp.org
ntp_server_hosts=                   # 集群模式下 Client 指向的内网 Server
ntp_client_hosts=                   # 集群批量部署的 Client 清单
allow_networks=                     # Server 允许同步的网段，如 10.0.0.0/24
peer_servers=                       # 对等 Server
local_stratum=10                    # 断网时的孤岛层级
force_makestep=y                    # 安装后是否强制立即校时
offset_threshold=1                  # 监控告警的偏移阈值（秒）
alert_email=
webhook_url=
```

## 定时任务

```bash
# 健康检查（每 5 分钟）
*/5 * * * * /opt/dmp_ops/chrony/monitor.sh --check >> /var/log/chrony/monitor.log 2>&1

# 配置备份（每天 3 点，也可用 ./backup_setup.sh 向导配置）
0 3 * * * /opt/dmp_ops/chrony/backup.sh >> /var/log/chrony/backup.log 2>&1
```

## chronyc 诊断速查

```bash
chronyc tracking        # 当前同步状态（最重要）
chronyc sources -v      # 所有时间源及状态
chronyc sourcestats -v  # 各源偏移/漂移统计
chronyc clients         # Server 角色的客户端列表（需 root）
chronyc activity        # 在线/离线源概览
chronyc makestep        # 立即强制跳变校时
chronyc ntpdata         # 最近一次 NTP 报文详情
timedatectl status      # 系统时钟/时区总览
```

`chronyc sources` 状态符号：

| 符号 | 含义 |
|------|------|
| `^*` | 当前同步的源 |
| `^+` | 可接受的备选源 |
| `^-` | 被合并算法排除 |
| `^?` | 不可达 |
| `^x` | 假源（falseticker） |
| `^~` | 抖动过大 |

## 常见问题

| 问题 | 原因 | 处理 |
|------|------|------|
| `chronyc sources` 全是 `^?` | 出站 123/udp 被拦截或源不可达 | 检查出站防火墙、更换上游源 |
| `Reference ID : 00000000` | 尚未选定任何源 | 等待 1~2 分钟或 `chronyc burst 4/4` |
| 服务正常但时间不同步 | ntpd/systemd-timesyncd 抢占 | 重新执行 `./install.sh`，会自动停用冲突服务 |
| Client 连不上内网 Server | Server 未 `allow` 该网段或未放行 123/udp | 检查 `allow_networks`、firewalld |
| 公网断开后集群时间漂移 | Server 未配 `local stratum` | 确认 Server 配置中有 `local stratum 10` |
| 容器内校时失败 | 容器缺少 `CAP_SYS_TIME` | 在宿主机部署 chrony，容器共享宿主时钟 |
| 升级后配置被覆盖 | 包管理器替换了 chrony.conf | `./upgrade.sh` 已自动备份并恢复 |
| 数据库出现时间跳变异常 | 执行了 `chronyc makestep` | 生产环境用 `--no_makestep`，在维护窗口手动校时 |

## 注意事项

1. **时区一致性**：集群内所有节点时区必须一致，脚本会统一设置为 `timezone` 配置项的值。
2. **时间跳变风险**：`chronyc makestep` 会使系统时间瞬间跳变，运行中的数据库、消息队列、分布式锁可能异常。生产环境首次安装建议在维护窗口执行，或使用 `--no_makestep` 让 chrony 缓慢 slew 校正。
3. **防火墙**：Server 角色需放行 `123/udp` 入站，脚本会自动处理 firewalld / ufw / iptables（iptables 规则不持久化，需自行保存）。
4. **SELinux**：无需关闭，chrony 默认策略已允许。若使用非标准路径需 `restorecon`。
5. **卸载后果**：卸载后系统无时间同步服务，时钟会逐渐漂移；如需回退到 systemd-timesyncd 执行 `timedatectl set-ntp true`。

## 参考文档

- [Chrony 官方文档](https://chrony-project.org/documentation.html)
- [chrony.conf 配置手册](https://chrony-project.org/doc/4.5/chrony.conf.html)
- [chronyc 命令手册](https://chrony-project.org/doc/4.5/chronyc.html)
- 本模块 AI 编程提示词：[ops-code-chrony.md](./ops-code-chrony.md)
- SSH 免密工具：[../sshtrust/README.md](../sshtrust/README.md)
