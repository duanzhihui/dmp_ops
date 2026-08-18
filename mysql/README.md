# MySQL 运维自动化脚本

基于 oneinstack 项目提炼的 MySQL 数据库运维自动化脚本集。

## 目录结构

```
mysql/
├── install.sh              # 安装主入口（交互/静默双模式）
├── uninstall.sh            # 卸载主入口
├── upgrade.sh              # 升级主入口
├── backup.sh               # 备份执行脚本（由 cron 调用）
├── backup_setup.sh         # 备份策略配置向导
├── monitor.sh              # 健康检查与状态监控
├── reset_password.sh       # 重置 root 密码工具
├── mgr_setup.sh            # MGR 双活配置主入口
├── options.conf            # 中央配置文件
├── versions.txt            # 版本号清单
├── include/                # 功能模块库
│   ├── color.sh            # 终端颜色定义
│   ├── check_os.sh         # 操作系统检测
│   ├── check_dir.sh        # 安装目录检测
│   ├── download.sh         # 下载函数
│   ├── get_char.sh         # 交互输入辅助
│   ├── mysql-8.4.sh        # MySQL 8.4 安装模块
│   ├── mysql-8.0.sh        # MySQL 8.0 安装模块
│   ├── upgrade_db.sh       # 升级模块
│   ├── monitor_mysql.sh    # 监控模块
│   └── mgr_setup.sh        # MGR 操作模块库
├── config/                 # 配置文件模板
│   └── my.cnf              # MySQL 配置模板
├── tools/                  # 辅助工具
│   └── db_bk.sh            # 单库备份脚本
└── src/                    # 源码包存放目录
```

## 快速开始

### 安装 MySQL

```bash
# 交互式安装
./install.sh

# 静默安装 MySQL 8.4
./install.sh --mysql_option 0 -q

# 静默安装 MySQL 8.0，指定密码
./install.sh --mysql_option 1 -p mypassword -q
```

### 卸载 MySQL

```bash
# 交互式卸载
./uninstall.sh

# 静默卸载
./uninstall.sh -q --mysql
```

### 升级 MySQL

```bash
# 交互式升级
./upgrade.sh

# 查看当前版本
./upgrade.sh -v
```

### 备份配置

```bash
# 配置备份策略
./backup_setup.sh

# 手动执行备份
./backup.sh
```

### 监控

```bash
# 运行健康检查
./monitor.sh --check

# 查看状态报告
./monitor.sh --status

# 运行所有检查
./monitor.sh --all
```

### 重置密码

```bash
# 交互式重置（需要当前密码）
./reset_password.sh

# 强制重置（忘记密码）
./reset_password.sh -f

# 指定新密码
./reset_password.sh -p newpassword
```

### MGR 双活部署

MySQL Group Replication（MGR）单主模式：一写多读 + 主挂自动选新主，**并非"双写双活"**。
多主双写需改 `group_replication_single_primary_mode=OFF`，当前脚本未实现。

#### 前置条件

- **≥3 节点**（MGR 要求多数派，2 节点无法容忍单点故障）
- 所有节点 **同版本同配置**（MySQL 8.0 或 8.4）
- 节点间网络互通，开放 **3306**（MySQL）与 **33061**（MGR 通信）端口
- 主机名解析正常（`hostname -I` 能返回正确 IP）

#### 配置示例（3 节点）

在每个节点的 `options.conf` 中配置 MGR 段：

```bash
# 节点1 (192.168.1.10) - 首节点，负责引导
mgr_enable=1
mgr_group_name=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee   # 全组一致，用 uuidgen 生成
mgr_local_address=192.168.1.10:33061
mgr_group_seeds=192.168.1.10:33061,192.168.1.11:33061,192.168.1.12:33061
mgr_bootstrap=1                                        # 仅首节点设 1
mgr_server_id=10                                       # 全组唯一

# 节点2 (192.168.1.11)
mgr_enable=1
mgr_group_name=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee   # 与节点1相同
mgr_local_address=192.168.1.11:33061
mgr_group_seeds=192.168.1.10:33061,192.168.1.11:33061,192.168.1.12:33061
mgr_bootstrap=0
mgr_server_id=11

# 节点3 (192.168.1.12)
mgr_enable=1
mgr_group_name=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
mgr_local_address=192.168.1.12:33061
mgr_group_seeds=192.168.1.10:33061,192.168.1.11:33061,192.168.1.12:33061
mgr_bootstrap=0
mgr_server_id=12
```

#### 操作流程

```bash
# 1. 各节点安装 MySQL（mgr_enable=1 会自动配置 GTID/ROW/MGR 参数并安装插件）
./install.sh --mysql_option 0 -q

# 2. 首节点引导启动新 group
./mgr_setup.sh --bootstrap

# 3. 其余节点加入现有 group
./mgr_setup.sh --join

# 4. 验证 group 状态
./mgr_setup.sh --status
```

#### MGR 管理

```bash
./mgr_setup.sh --bootstrap              # 引导启动新 group（仅首节点）
./mgr_setup.sh --join                   # 加入现有 group
./mgr_setup.sh --remove                 # 退出 group
./mgr_setup.sh --status                 # 查看 group 成员与状态
./mgr_setup.sh --set-primary <id>       # 强制切换主
./mgr_setup.sh --check                  # 前置条件检查
./mgr_setup.sh --install-plugin         # 仅安装 group_replication 插件
```

#### MGR 监控

```bash
# 检查 MGR group 状态
./monitor.sh --mgr

# 完整健康检查（mgr_enable=1 时自动检查 MGR，跳过传统主从复制）
./monitor.sh --check

# cron 定时监控
*/5 * * * * /path/to/mysql/monitor.sh --check -q
```

#### 注意事项

1. **单主模式语义**：仅 PRIMARY 节点可写，SECONDARY 节点只读。主节点故障时自动选举新主。
2. **`performance_schema` 改 ON**：MGR 依赖 performance_schema，启用后增加约 100-400MB 内存占用（视连接数）。
3. **`binlog_format` 改 ROW**：MGR 要求 ROW 格式，日志体积大于 mixed。
4. **`conf_version` 升级**：从旧版升级时 `options.conf` 会自动备份为 `options.conf.1` 并从模板重建，
   需从备份文件回填 `dbrootpwd` 等旧值。
5. **`server-id` 唯一性**：`mgr_server_id` 留空时按本机 IP 末段生成，需手工确认全组唯一。
6. **MySQL 8.0 vs 8.4 参数差异**：8.0 需要 `transaction_write_set_extraction=XXHASH64` 等参数，
   8.4 已废弃这些参数（写入会报错）。脚本按版本自动适配。

## 支持的系统

- CentOS/RHEL 7+
- Debian 9+
- Ubuntu 16+
- AlmaLinux 8+
- Rocky Linux 8+

## 支持的 MySQL 版本

- MySQL 8.4 (LTS, 推荐)
- MySQL 8.0
- MySQL 5.7

## 安装方式

- **二进制安装** (默认，推荐): 快速，适合生产环境
- **源码编译**: 可自定义编译选项，适合特殊需求

## 配置说明

### options.conf

主要配置项：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| mysql_install_dir | 安装目录 | /usr/local/mysql |
| mysql_data_dir | 数据目录 | /data/mysql |
| dbrootpwd | root 密码 | 自动生成 |
| backup_dir | 备份目录 | /data/backup |
| expired_days | 备份保留天数 | 5 |

### 备份目标

支持多种备份目标：

- **local**: 本地备份
- **remote**: 远程服务器 (rsync/scp)
- **oss**: 阿里云 OSS
- **cos**: 腾讯云 COS
- **s3**: AWS S3

## 监控告警

支持多种告警方式：

- 邮件通知
- Webhook (钉钉/企业微信/Slack)

监控项：

- MySQL 进程存活
- 端口监听状态
- 连接数使用率
- 主从复制状态
- 慢查询数量
- 磁盘空间使用

## 常见问题

### libaio.so.1 / libncurses.so.5 找不到

MySQL 官方预编译包链接的是旧 soname，而 Ubuntu 24.04+（64 位 time_t 迁移）只提供
`libaio.so.1t64`，ncurses 也只剩 `.so.6`，直接运行会报：

```
mysqld: error while loading shared libraries: libaio.so.1: cannot open shared object file
mysql:  error while loading shared libraries: libncurses.so.5: cannot open shared object file
```

`install.sh` 会自动安装 `libaio1t64` / `libncurses6` 并由 `Fix_Compat_Libs`（见
`include/check_os.sh`）补齐兼容软链，无需手工处理。若在旧版本上已安装失败，先执行
`./uninstall.sh` 清理后重新安装。

## 注意事项

1. 所有脚本需要 root 权限运行
2. 卸载时数据目录会被重命名备份，不会直接删除
3. 升级只支持小版本升级（如 8.0.35 → 8.0.39）
4. 密码不能包含 `+` 和 `&` 字符

## License

MIT License
