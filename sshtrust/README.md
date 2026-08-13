# SSH 互信工具 (sshtrust)

基于 oneinstack 架构规范的 SSH 免密互信管理工具，支持配置多台服务器 SSH 互信，可增加、删除互信机器。

## 功能特性

- **两种互信模式**：one-way（控制机→多目标单向）和 mesh（全互信网状）
- **密码认证初始化**：通过 sshpass + ssh-copy-id 分发公钥，自动检测安装 sshpass
- **支持任意用户**：默认 root，可指定任意用户（hadoop、app 等）
- **批量导入**：支持从文件读取主机列表
- **灵活的主机格式**：`host` / `user@host` / `user@host:port` / `host:port`
- **幂等操作**：重复添加同一主机不会重复分发公钥
- **交互/静默双模式**：无参数时交互菜单，有参数时静默执行

## 快速开始

### 交互模式

```bash
# 赋予执行权限
chmod +x sshtrust.sh

# 交互式菜单
./sshtrust.sh
```

### 静默模式

```bash
# 添加单台主机互信
./sshtrust.sh --add 192.168.1.10

# 添加多台主机，指定用户
./sshtrust.sh --add 192.168.1.10 192.168.1.11 --user root

# 添加带自定义端口的主机
./sshtrust.sh --add root@192.168.1.12:2222

# 从文件批量导入
./sshtrust.sh --add-file hosts.txt

# 删除互信
./sshtrust.sh --remove 192.168.1.10

# 查看当前配置
./sshtrust.sh --list

# 检查互信连通性
./sshtrust.sh --check

# 配置全互信（网状模式）
./sshtrust.sh --mesh

# 仅初始化本机密钥对
./sshtrust.sh --init
```

## 目录结构

```
sshtrust/
├── sshtrust.sh              # 主入口脚本（交互/静默双模式）
├── options.conf             # 配置文件（SSH参数 + 主机列表持久化）
├── include/
│   ├── color.sh             # 终端颜色定义
│   ├── check_os.sh          # 操作系统检测
│   ├── check_env.sh         # 环境检测（sshpass/密钥）
│   └── sshtrust_core.sh     # 核心功能模块
└── README.md                # 使用说明
```

## 配置说明

### options.conf

```bash
# SSH 互信配置
ssh_user=root              # 互信用户名
ssh_port=22                # SSH端口
ssh_key_type=rsa           # 密钥类型: rsa / ed25519 / ecdsa
ssh_key_bits=2048          # 密钥长度（rsa时生效）
ssh_key_file=~/.ssh/id_rsa # 密钥文件路径

# 互信模式
trust_mode=one-way         # one-way 或 mesh

# 互信主机列表（空格分隔，必须加双引号）
trust_hosts=""             # 如: "192.168.1.10 192.168.1.11"
```

### 批量导入文件格式

```
# hosts.txt — 每行一个主机，# 开头为注释
192.168.1.10
192.168.1.11
root@192.168.1.12:2222
# 这是注释行
app@192.168.1.13
```

## 命令行参数

| 参数 | 短选项 | 说明 |
|------|--------|------|
| `--help` | `-h` | 显示帮助 |
| `--add HOST [HOST...]` | `-a` | 添加互信机器（空格分隔多个） |
| `--add-file FILE` | `-f` | 从文件批量导入主机列表 |
| `--remove HOST [HOST...]` | `-r` | 删除互信机器 |
| `--list` | `-l` | 列出当前互信配置 |
| `--check` | `-c` | 检查互信连通性 |
| `--mesh` | `-m` | 全互信模式（所有机器互相免密） |
| `--user USER` | `-u` | 指定用户名（覆盖配置） |
| `--port PORT` | `-p` | 指定SSH端口（覆盖配置） |
| `--quiet` | `-q` | 静默模式，跳过确认 |
| `--init` | | 仅初始化本机密钥对 |
| `--password PWD` | | 传入统一密码（静默模式） |
| `--password-file FILE` | | 从文件读取逐台密码（每行一个） |

## 互信模式说明

### one-way（单向互信）

从本机（控制节点）免密登录到所有配置的远程主机。适用于运维管理场景。

```
本机 ──→ 192.168.1.10
本机 ──→ 192.168.1.11
本机 ──→ 192.168.1.12
```

### mesh（全互信网状）

所有机器之间互相免密登录。适用于 Hadoop/Spark 等集群场景。

```
192.168.1.10 ←→ 192.168.1.11
192.168.1.10 ←→ 192.168.1.12
192.168.1.11 ←→ 192.168.1.12
```

mesh 模式执行流程：
1. 本机 → 所有远程主机建立互信
2. 在每台远程主机上生成密钥对
3. 交叉分发所有主机的公钥
4. 验证所有 pair 之间的免密连通性

## 依赖

- **sshpass**：用于密码认证初始化（自动检测安装）
- **openssh-client**：ssh、ssh-keygen、ssh-copy-id（系统自带）

## 使用示例

### 场景1：运维管理多台服务器

```bash
# 初始化密钥
./sshtrust.sh --init

# 添加3台服务器
./sshtrust.sh --add 192.168.1.10 192.168.1.11 192.168.1.12

# 验证连通性
./sshtrust.sh --check

# 查看配置
./sshtrust.sh --list
```

### 场景2：Hadoop 集群全互信

```bash
# 先添加所有节点
./sshtrust.sh --add 192.168.1.10 192.168.1.11 192.168.1.12

# 配置全互信
./sshtrust.sh --mesh

# 验证
./sshtrust.sh --check
```

### 场景3：从文件批量导入

```bash
# 准备主机文件
cat > hosts.txt << EOF
192.168.1.10
192.168.1.11
root@192.168.1.12:2222
app@192.168.1.13
EOF

# 批量添加
./sshtrust.sh --add-file hosts.txt
```

### 场景4：删除互信

```bash
# 删除单台
./sshtrust.sh --remove 192.168.1.10

# 删除多台
./sshtrust.sh --remove 192.168.1.10 192.168.1.11
```

## 密码处理策略

密码在执行 `--add` 或 `--add-file` 时输入，环境检测通过后、开始分发公钥前。

### 三种密码输入方式

| 方式 | 适用场景 | 用法 |
|------|---------|------|
| 交互式统一密码 | 所有主机密码相同 | 交互菜单选择选项1，输入一次密码 |
| 交互式逐台输入 | 每台主机密码不同 | 交互菜单选择选项2，逐台输入密码（不回显） |
| `--password` 参数 | 静默模式，密码相同 | `--quiet --password mypass` |
| `--password-file` 参数 | 静默模式，密码不同 | `--quiet --password-file passwords.txt` |

### 密码文件格式

`--password-file` 每行一个密码，按主机顺序对应，`#` 开头为注释：

```
# passwords.txt
MyPass123          # 对应第1台主机
AnotherPass456     # 对应第2台主机
ThirdPass789       # 对应第3台主机
```

### 密码安全

- 密码输入不回显（`read -s`）
- 密码不持久化到 options.conf
- `--password` 参数会出现在命令历史中，建议用完清理 `history -d`

## License

Apache License 2.0
