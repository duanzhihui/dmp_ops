# 开源软件运维代码模板 — 架构规范与 AI 编程提示词

> 本文档基于 oneinstack 项目的完整代码分析，提炼出适用于**任意开源软件**的通用 Shell 运维代码模板。
> 包含两部分：**Part A 架构规范**（代码应该长什么样）和 **Part B AI 编程提示词**（直接交给 AI 生成代码）。

---

# Part A: 架构规范

## 1. 目录结构规范

```
{project_name}/
├── install.sh              # 主安装入口（交互/静默双模式）
├── uninstall.sh            # 主卸载入口
├── upgrade.sh              # 主升级入口
├── backup.sh               # 备份执行脚本（由 cron 调用）
├── backup_setup.sh         # 备份策略配置向导
├── monitor.sh              # 健康检查与状态监控
├── options.conf.template   # 中央配置模板（git 跟踪，含 conf_version 版本号）
├── options.conf            # 运行时配置（.gitignore 忽略，由模板自动生成/升级）
├── versions.txt            # 版本号清单（与 options.conf 分离）
├── .gitignore              # 忽略 options.conf 及其备份文件
├── include/                # 功能模块库
│   ├── color.sh            #   终端颜色定义
│   ├── check_os.sh         #   操作系统检测与适配
│   ├── check_dir.sh        #   安装目录检测与变量初始化
│   ├── download.sh         #   下载函数（多源容错）
│   ├── get_char.sh         #   交互输入辅助函数
│   ├── ensure_options_conf.sh  # options.conf 模板化引导（创建/备份/升级）
│   ├── {software}.sh       #   软件安装模块（Install/Uninstall 函数）
│   ├── upgrade_{type}.sh   #   软件升级模块（Upgrade 函数）
│   └── monitor_{type}.sh   #   监控检查模块（Check/Status 函数）
├── init.d/                 # systemd service 模板
│   └── {software}.service  #   每个软件一个 unit 文件
├── config/                 # 软件配置文件模板
│   └── {software}.conf     #   Nginx/Apache 等配置模板
├── tools/                  # 辅助工具脚本
│   ├── db_bk.sh            #   数据库单库备份脚本
│   └── website_bk.sh       #   网站目录备份脚本
└── src/                    # 源码包存放目录
```

## 2. 文件职责说明

### 2.1 主入口脚本

| 文件 | 职责 | 关键设计 |
|------|------|---------|
| `install.sh` | 安装主入口，负责参数解析、交互选择、调用 include 模块执行安装 | getopt 长短选项 + 交互菜单双模式；source 模块脚本 |
| `uninstall.sh` | 卸载主入口，按组件逐一停止服务、删除文件、清理环境 | Print_XXX 预览 + Uninstall_XXX 执行的确认模式 |
| `upgrade.sh` | 升级主入口，检测当前版本、下载新版本、备份旧版本、替换并重启 | 自动获取最新版本号 + 版本比对校验 |
| `backup.sh` | 备份执行器，由 cron 定时调用，根据 options.conf 配置执行备份 | 策略模式：按 backup_destination 分发到不同后端 |
| `backup_setup.sh` | 备份配置向导，交互式设置备份目标、内容、凭证并写入 options.conf | 配置持久化到 options.conf |
| `monitor.sh` | 健康检查与状态监控，检测进程、端口、资源使用 | 定时执行 + 告警通知 |

### 2.2 公共库模块 (include/)

| 文件 | 职责 | 核心函数/逻辑 |
|------|------|-------------|
| `color.sh` | 定义终端颜色变量 | `CSUCCESS`(绿)、`CFAILURE`(红)、`CWARNING`(黄)、`CMSG`(青)、`CEND`(重置) |
| `check_os.sh` | 检测 OS 发行版、版本、架构、包管理器 | 输出 `Platform`、`Family`(rhel/debian/ubuntu)、`PM`(yum/apt-get)、`ARCH`、`THREAD` |
| `check_dir.sh` | 检测已安装软件的实际路径，设置统一变量 | 遍历多个可能路径，设置 `db_install_dir`、`web_install_dir` 等 |
| `download.sh` | 文件下载函数，支持多源容错和完整性校验 | `Download_src()` — URL 数组逐一尝试，检测 HTML 错误页 |
| `get_char.sh` | 读取单个字符（用于"按任意键继续"） | `get_char()` |
| `{software}.sh` | 单个软件的安装/卸载逻辑 | `Install_{software}()`、`Uninstall_{software}()` |
| `upgrade_{type}.sh` | 单个软件的升级逻辑 | `Upgrade_{software}()` |

### 2.3 服务管理 (init.d/)

每个软件一个 `.service` 文件，遵循 systemd unit 标准格式。

### 2.4 配置文件

| 文件 | 职责 |
|------|------|
| `options.conf.template` | 配置模板（git 跟踪）：含 `conf_version` 版本号与所有默认值，模板改动时递增版本号 |
| `options.conf` | 运行时配置（.gitignore 忽略）：首次运行由模板自动生成，模板版本变更时自动备份旧配置并重建 |
| `versions.txt` | 所有软件的版本号清单，与 options.conf 分离以便独立更新 |
| `include/ensure_options_conf.sh` | options.conf 引导函数：检测模板版本，按需创建/备份/升级 options.conf |

## 3. 运维生命周期 — 五大阶段代码模式

### 3.1 安装 (Install)

**流程模式：**
```
前置检查 → 参数解析 → 已安装检测 → 下载源码包 → 解压编译 → 配置文件生成 → 创建用户 → 注册 systemd 服务 → 启动服务 → 安装后验证
```

**关键代码模式（从 oneinstack 提炼）：**

```bash
# 1. 已安装检测 — 幂等性保证
[ -e "${install_dir}/bin/{software}" ] && {
  echo "${CWARNING}{Software} already installed!${CEND}"
  exit 0
}

# 2. 下载（多源容错）
src_url="https://example.com/{software}-${ver}.tar.gz"
Download_src  # include/download.sh 提供

# 3. 编译安装
tar xzf {software}-${ver}.tar.gz
pushd {software}-${ver} > /dev/null
./configure --prefix=${install_dir}
make -j ${THREAD} && make install
popd > /dev/null

# 4. 安装后验证
if [ -f "${install_dir}/bin/{software}" ]; then
  echo "${CSUCCESS}{Software} installed successfully!${CEND}"
  rm -rf {software}-${ver}
else
  echo "${CFAILURE}{Software} install failed!${CEND}"
  kill -9 $$; exit 1
fi

# 5. 创建系统用户
id -u {user} >/dev/null 2>&1
[ $? -ne 0 ] && useradd -M -s /sbin/nologin {user}
chown -R {user}:{user} ${install_dir}

# 6. 注册 systemd 服务
/bin/cp ../init.d/{software}.service /lib/systemd/system/
sed -i "s@/opt/{software}@${install_dir}@g" /lib/systemd/system/{software}.service
systemctl enable {software}
systemctl start {software}
```

### 3.2 卸载 (Uninstall)

**流程模式：**
```
预览将删除的内容 → 用户确认 → 停止服务 → 禁用服务 → 删除 service 文件 → 备份数据目录(mv+日期后缀) → 删除安装目录 → 删除用户 → 清理环境变量 → 清理 options.conf
```

**关键代码模式：**

```bash
# 1. 预览 — 告诉用户将删除什么
Print_{Software}() {
  [ -e "${install_dir}" ] && echo ${install_dir}
  [ -e "/lib/systemd/system/{software}.service" ] && echo /lib/systemd/system/{software}.service
}

# 2. 确认
Uninstall_status() {
  while :; do
    read -e -p "Do you want to uninstall? [y/n]: " uninstall_flag
    [[ ${uninstall_flag} =~ ^[y,n]$ ]] && break
  done
}

# 3. 执行卸载
Uninstall_{Software}() {
  service {software} stop > /dev/null 2>&1
  [ -e "/lib/systemd/system/{software}.service" ] && {
    systemctl disable {software} > /dev/null 2>&1
    rm -f /lib/systemd/system/{software}.service
  }
  # 数据目录：重命名备份而非直接删除
  [ -e "${data_dir}" ] && /bin/mv ${data_dir}{,$(date +%Y%m%d%H)}
  # 安装目录：直接删除
  rm -rf ${install_dir}
  # 清理环境变量
  sed -i "s@${install_dir}/bin:@@" /etc/profile
  # 清理配置
  sed -i 's@^{software}pwd=.*@{software}pwd=@' ./options.conf
  # 删除用户
  id -u {user} >/dev/null 2>&1 && userdel {user}
  echo "${CMSG}{Software} uninstall completed!${CEND}"
}
```

### 3.3 升级 (Upgrade)

**流程模式：**
```
检测当前版本 → 获取最新可用版本 → 用户输入目标版本 → 版本校验(主版本必须一致) → 升级前备份 → 下载新版本 → 停服务 → 替换文件 → 启动服务 → 升级后验证
```

**关键代码模式：**

```bash
Upgrade_{Software}() {
  # 1. 检测当前版本
  [ ! -e "${install_dir}/bin/{software}" ] && {
    echo "${CWARNING}{Software} is not installed!${CEND}"; exit 1
  }
  OLD_ver=$(${install_dir}/bin/{software} --version | awk '{print $NF}')

  # 2. 获取最新版本（从官方页面或 API）
  Latest_ver=$(curl -s https://api.github.com/repos/{org}/{repo}/releases/latest | grep tag_name | awk -F'"' '{print $4}')

  # 3. 版本比对
  echo "Current Version: ${CMSG}${OLD_ver}${CEND}"
  read -e -p "Please input upgrade version(default: ${Latest_ver}): " NEW_ver
  NEW_ver=${NEW_ver:-${Latest_ver}}
  [ "${NEW_ver}" == "${OLD_ver}" ] && {
    echo "${CWARNING}Same version, skip upgrade${CEND}"; exit 0
  }

  # 4. 升级前备份
  /bin/mv ${install_dir}/bin/{software}{,_$(date +%m%d)}

  # 5. 下载并替换
  wget -c https://example.com/{software}-${NEW_ver}.tar.gz
  tar xzf {software}-${NEW_ver}.tar.gz
  # ... 编译或直接替换二进制 ...

  # 6. 重启验证
  systemctl restart {software}
  echo "Successfully upgrade from ${OLD_ver} to ${NEW_ver}"
}
```

### 3.4 备份 (Backup)

**流程模式：**
```
备份配置向导(一次性) → cron 定时调用 → 按内容类型(db/web)分别执行 → 按目标(local/remote/oss/s3/...)分发 → 过期清理
```

**关键代码模式：**

```bash
# === backup_setup.sh — 一次性配置向导 ===
# 选择备份目标 → 选择备份内容 → 配置凭证 → 写入 options.conf
# 最终设置 cron:
# echo "0 2 * * * /path/to/backup.sh" >> /var/spool/cron/root

# === backup.sh — 执行器（策略模式） ===
# 按目标分发
for DEST in $(echo ${backup_destination} | tr ',' ' '); do
  if [ "${DEST}" == 'local' ]; then
    [ -n "$(echo ${backup_content} | grep -ow db)" ] && DB_Local_BK
    [ -n "$(echo ${backup_content} | grep -ow web)" ] && WEB_Local_BK
  fi
  if [ "${DEST}" == 'oss' ]; then
    [ -n "$(echo ${backup_content} | grep -ow db)" ] && DB_OSS_BK
    [ -n "$(echo ${backup_content} | grep -ow web)" ] && WEB_OSS_BK
  fi
  # ... 更多后端 ...
done

# === 单库备份函数模式 ===
DB_Local_BK() {
  DumpFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H%M%S).sql
  NewFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H%M%S).tgz
  OldFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d --date="${expired_days} days ago")*.tgz
  # 删除过期备份
  [ -n "$(ls ${OldFile} 2>/dev/null)" ] && rm -f ${OldFile}
  # 执行备份
  mysqldump -uroot -p${dbrootpwd} --databases ${DBname} > ${DumpFile}
  tar czf ${NewFile} ${DumpFile##*/}
  rm -f ${DumpFile}
}

# === 云存储备份函数模式 ===
DB_OSS_BK() {
  # ... 执行本地备份 ...
  ossutil cp -f ${backup_dir}/${DB_FILE} oss://${oss_bucket}/$(date +%F)/${DB_FILE}
  if [ $? -eq 0 ]; then
    ossutil rm -rf oss://${oss_bucket}/$(date +%F --date="${expired_days} days ago")/
    # 如果不保留本地副本则删除
    [ -z "$(echo ${backup_destination} | grep -ow 'local')" ] && rm -f ${backup_dir}/${DB_FILE}
  fi
}
```

### 3.5 监控 (Monitor)

> 注: oneinstack 未直接实现监控模块，以下基于行业最佳实践设计。

**流程模式：**
```
进程存活检查 → 端口可达检查 → 服务响应检查 → 资源使用检查 → 日志异常检查 → 告警通知
```

**关键代码模式：**

```bash
# === monitor.sh ===

# 1. 进程存活检查
Check_Process() {
  local service_name=$1
  local process_name=$2
  if ! pgrep -x "${process_name}" > /dev/null 2>&1; then
    echo "${CFAILURE}[CRITICAL] ${service_name} process is NOT running!${CEND}"
    # 尝试自动恢复
    systemctl restart ${service_name}
    if pgrep -x "${process_name}" > /dev/null 2>&1; then
      echo "${CSUCCESS}[RECOVERED] ${service_name} restarted successfully${CEND}"
      Send_Alert "${service_name} was down, auto-recovered"
    else
      Send_Alert "${service_name} is DOWN and auto-recovery FAILED"
      return 1
    fi
  fi
  return 0
}

# 2. 端口可达检查
Check_Port() {
  local service_name=$1
  local port=$2
  local host=${3:-127.0.0.1}
  if ! ss -tlnp | grep -q ":${port} "; then
    echo "${CFAILURE}[CRITICAL] ${service_name} port ${port} is NOT listening!${CEND}"
    Send_Alert "${service_name} port ${port} not listening"
    return 1
  fi
  return 0
}

# 3. HTTP 健康检查
Check_HTTP() {
  local service_name=$1
  local url=$2
  local expected_code=${3:-200}
  local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "${url}")
  if [ "${http_code}" != "${expected_code}" ]; then
    echo "${CFAILURE}[WARNING] ${service_name} HTTP check failed: ${http_code}${CEND}"
    Send_Alert "${service_name} HTTP ${url} returned ${http_code}"
    return 1
  fi
  return 0
}

# 4. 磁盘空间检查
Check_Disk() {
  local threshold=${1:-85}
  local alert_sent=0
  df -h | awk 'NR>1{gsub(/%/,"",$5); if($5 > '${threshold}') print $0}' | while read line; do
    echo "${CWARNING}[WARNING] Disk usage high: ${line}${CEND}"
    Send_Alert "Disk usage warning: ${line}"
    alert_sent=1
  done
  return ${alert_sent}
}

# 5. 告警通知（可扩展：邮件/钉钉/飞书/Webhook）
Send_Alert() {
  local message=$1
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${timestamp}] ALERT: ${message}" >> ${log_dir}/monitor.log

  # 邮件通知
  if [ -n "${alert_email}" ]; then
    echo "${message}" | mail -s "[Monitor Alert] $(hostname)" ${alert_email}
  fi

  # Webhook 通知（钉钉/飞书/Slack 等）
  if [ -n "${webhook_url}" ]; then
    curl -s -X POST "${webhook_url}" \
      -H 'Content-Type: application/json' \
      -d "{\"text\": \"[$(hostname)] ${timestamp} ${message}\"}"
  fi
}

# 6. 主检查循环
Monitor_All() {
  echo "========== Monitor Check: $(date) =========="
  # 从 options.conf 读取已安装组件，逐一检查
  [ -e "${nginx_install_dir}/sbin/nginx" ] && {
    Check_Process "nginx" "nginx"
    Check_Port "nginx" 80
    Check_HTTP "nginx" "http://127.0.0.1/"
  }
  [ -d "${db_install_dir}/support-files" ] && {
    Check_Process "mysqld" "mysqld"
    Check_Port "mysqld" 3306
  }
  [ -e "${redis_install_dir}/bin/redis-server" ] && {
    Check_Process "redis-server" "redis-server"
    Check_Port "redis-server" 6379
  }
  Check_Disk 85
}
```

## 4. 公共库函数规范

### 4.1 颜色输出 (color.sh)

```bash
CSI=$'\033['
CEND="${CSI}0m"
CSUCCESS="${CSI}32m"      # 绿色 — 成功
CFAILURE="${CSI}1;31m"    # 红色 — 失败
CWARNING="${CSI}1;33m"    # 黄色 — 警告
CMSG="${CSI}1;36m"        # 青色 — 信息
```

### 4.2 OS 检测 (check_os.sh)

**必须输出的变量：**

| 变量 | 说明 | 示例 |
|------|------|------|
| `Platform` | 发行版名称（小写） | centos, ubuntu, debian |
| `Family` | 系统族 | rhel, debian, ubuntu |
| `PM` | 包管理器 | yum, apt-get |
| `ARCH` | 架构 | x86_64, aarch64 |
| `THREAD` | CPU 线程数 | 4 |
| `VERSION_MAIN_ID` | 主版本号 | 7, 22, 12 |

### 4.3 下载函数 (download.sh)

**设计要点：**
- 多 URL 源容错（主镜像 → 备用镜像 → 官方源）
- 检测下载的文件是否为 HTML 错误页（<1KB + 含 HTML 标签）
- 支持断点续传 (`wget -c`)
- 下载失败时给出手动下载提示

### 4.4 交互/静默双模式

```bash
# 参数解析（getopt 标准模式）
ARG_NUM=$#
TEMP=$(getopt -o hqv --long help,quiet,version,option: -- "$@" 2>/dev/null)
eval set -- "${TEMP}"

# 无参数时显示交互菜单
if [ ${ARG_NUM} == 0 ]; then
  Menu  # 交互式菜单函数
else
  # 按参数静默执行
  [ "${flag}" == 'y' ] && Do_Action
fi
```

## 5. 配置管理规范

### 5.1 options.conf 结构

> `options.conf` 由 `options.conf.template` 在运行时自动生成，**勿手动创建或提交到 git**。
> 模板文件顶部必须包含 `conf_version` 版本号字段，模板内容变更时递增该版本号。

```bash
# ===== 配置版本号（勿手动修改，由 options.conf.template 同步）=====
conf_version=1

# ===== 镜像源 =====
mirror_link=https://mirrors.example.com

# ===== 安装路径 =====
{software}_install_dir=/opt/{software}

# ===== 数据目录 =====
{software}_data_dir=/data/{software}

# ===== 运行用户 =====
run_user=www
run_group=www

# ===== 自动生成（不可手动修改）=====
{software}pwd=           # 安装时自动生成

# ===== 备份配置 =====
backup_dir=/data/backup
expired_days=5
backup_destination=      # local,remote,oss,cos,s3
backup_content=          # db,web
oss_bucket=
s3_bucket=
db_name=
website_name=
```

### 5.2 versions.txt 结构

```bash
# 每个软件一个版本变量，命名格式：{software}{major_ver}_ver
nginx_ver=1.31.0
mysql80_ver=8.0.39
redis_ver=8.4.0
php84_ver=8.4.16
```

### 5.3 options.conf 模板化与版本自管理

**目的**：避免 `git pull` 更新代码时覆盖用户已修改的 `options.conf`。

**机制**：git 只跟踪 `options.conf.template`（含 `conf_version` 版本号），`options.conf` 加入 `.gitignore`，由 `include/ensure_options_conf.sh` 在脚本启动时自动管理。

**.gitignore 内容**：

```
# 运行时生成的配置文件（由 options.conf.template 同步，勿提交）
options.conf
options.conf.bak
options.conf.bak.*
options.conf.[0-9]*
```

**引导函数 `Ensure_Options_Conf <module_dir>`**（定义于 `include/ensure_options_conf.sh`）：

| 场景 | 条件 | 行为 |
|------|------|------|
| 模板不存在 | 无 `options.conf.template` | 直接返回（兼容无模板场景） |
| 首次运行 | `options.conf` 不存在 | `cp 模板 options.conf`，提示已创建 |
| 版本一致 | `conf_version` 与模板相同 | 沿用现有 `options.conf`（保留用户修改） |
| 版本升级 | `conf_version` 与模板不同 | 备份旧配置 → 从模板重建 |
| 旧版无版本字段 | `options.conf` 无 `conf_version` 行 | 备份为 `options.conf.bak` → 从模板重建 |

**备份命名规则**：
- 旧版有版本号：`options.conf.<旧版本>`（重名则追加 `.1`/`.2`...）
- 旧版无版本号：`options.conf.bak`（重名则追加 `.1`/`.2`...）

**入口脚本注入模式**（所有 source options.conf 的脚本均需在加载前注入）：

```bash
# 获取脚本目录
script_dir=$(cd "$(dirname "$0")" && pwd)

# 加载配置和公共库
. "${script_dir}/include/ensure_options_conf.sh"   # 先加载引导函数
Ensure_Options_Conf "${script_dir}"                 # 再执行引导（创建/备份/升级 options.conf）
. "${script_dir}/options.conf"                      # 最后加载（已确保存在且为最新版本）
. "${script_dir}/include/color.sh"
# ... 其他 include
```

**模板变更流程**（开发者）：
1. 修改 `options.conf.template`（新增/调整配置项）
2. 递增模板中的 `conf_version=N`
3. 提交到 git
4. 用户 `git pull` 后首次运行任意脚本时，`Ensure_Options_Conf` 自动备份旧 `options.conf` 并从新模板重建

**ensure_options_conf.sh 完整实现**：

```bash
#!/bin/bash
# options.conf 模板化引导逻辑
# 功能: 运行时根据 options.conf.template 与版本号自动创建/备份/升级 options.conf
# 用法: Ensure_Options_Conf <module_dir>

Ensure_Options_Conf() {
  local module_dir="$1"
  local tmpl="${module_dir}/options.conf.template"
  local conf="${module_dir}/options.conf"

  # 模板不存在，兼容无模板场景
  [ -f "${tmpl}" ] || return 0

  # 读取模板版本号
  local tmpl_ver
  tmpl_ver=$(grep -E '^conf_version=' "${tmpl}" 2>/dev/null | head -1 | cut -d= -f2-)
  tmpl_ver="${tmpl_ver#\"}"; tmpl_ver="${tmpl_ver%\"}"
  tmpl_ver="${tmpl_ver#\'}"; tmpl_ver="${tmpl_ver%\'}"
  tmpl_ver=$(echo "${tmpl_ver}" | tr -d '[:space:]')

  # options.conf 不存在 -> 从模板创建
  if [ ! -f "${conf}" ]; then
    cp -p "${tmpl}" "${conf}"
    echo "${CMSG}[options.conf] 已从模板创建 (version=${tmpl_ver})${CEND}"
    return 0
  fi

  # 读取现有 options.conf 版本号
  local cur_ver
  cur_ver=$(grep -E '^conf_version=' "${conf}" 2>/dev/null | head -1 | cut -d= -f2-)
  cur_ver="${cur_ver#\"}"; cur_ver="${cur_ver%\"}"
  cur_ver="${cur_ver#\'}"; cur_ver="${cur_ver%\'}"
  cur_ver=$(echo "${cur_ver}" | tr -d '[:space:]')

  # 版本一致 -> 沿用
  if [ -n "${cur_ver}" ] && [ "${cur_ver}" = "${tmpl_ver}" ]; then
    return 0
  fi

  # 版本不一致 -> 备份后重建
  local bak
  if [ -z "${cur_ver}" ]; then
    bak="${conf}.bak"
    local i=1
    while [ -e "${bak}" ]; do bak="${conf}.bak.${i}"; i=$((i + 1)); done
  else
    bak="${conf}.${cur_ver}"
    local i=1
    while [ -e "${bak}" ]; do bak="${conf}.${cur_ver}.${i}"; i=$((i + 1)); done
  fi

  cp -p "${conf}" "${bak}"
  cp -p "${tmpl}" "${conf}"
  echo "${CMSG}[options.conf] 版本变更 (旧=${cur_ver:-unknown} 新=${tmpl_ver})，旧配置已备份为 ${bak}${CEND}"
}
```

## 6. 服务管理规范 (systemd unit 模板)

```ini
[Unit]
Description={Software} Service
After=network.target

[Service]
Type=forking
PIDFile=/var/run/{software}/{software}.pid
User={user}
Group={group}

Environment=statedir=/var/run/{software}
PermissionsStartOnly=true
ExecStartPre=/bin/mkdir -p ${statedir}
ExecStartPre=/bin/chown -R {user}:{user} ${statedir}
ExecStart=/opt/{software}/bin/{software} -c /opt/{software}/etc/{software}.conf
ExecStop=/bin/kill -s TERM $MAINPID
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
LimitNOFILE=1000000
LimitNPROC=1000000
LimitCORE=1000000

[Install]
WantedBy=multi-user.target
```

## 7. 错误处理与日志规范

```bash
# 1. 所有输出同时记录到日志
{command} 2>&1 | tee -a ${install_log}

# 2. 安装失败时立即终止
if [ ! -f "${install_dir}/bin/{software}" ]; then
  echo "${CFAILURE}{Software} install failed!${CEND}" && \
    grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
  kill -9 $$; exit 1
fi

# 3. 数据目录删除前必须备份
/bin/mv ${data_dir}{,$(date +%Y%m%d%H)}  # 重命名而非 rm

# 4. 密码生成
password=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c8)
```

## 8. 命令行参数设计规范

**标准参数表：**

| 参数 | 短选项 | 说明 |
|------|--------|------|
| `--help` | `-h` | 显示帮助 |
| `--version` | `-v` | 显示版本 |
| `--quiet` | `-q` | 静默模式，跳过确认 |
| `--{component}` | | 指定操作的组件 |
| `--{component}_option [N]` | | 指定组件的版本选项 |
| `--all` | | 操作所有组件 |

---

# Part B: AI 编程完整提示词

> 以下提示词可直接复制给 AI 编程工具（如 Cursor/Windsurf/Copilot），让其为指定的开源软件生成完整运维代码。

---

## 提示词全文

```markdown
# 角色

你是一位资深的 Linux 运维自动化工程师，精通 Bash Shell 编程和 systemd 服务管理。
你的任务是为开源软件 **{SOFTWARE_NAME}** 编写一套完整的运维自动化脚本。

# 输入参数

在开始编码前，我会提供以下信息（用 {占位符} 表示）：
- **{SOFTWARE_NAME}**: 软件名称（如 Nginx、MySQL、Redis、Apache Doris 等）
- **{SOFTWARE_VERSION}**: 默认安装版本号
- **{INSTALL_DIR}**: 默认安装路径（如 /opt/{software}）
- **{DATA_DIR}**: 数据存放路径（如 /data/{software}）
- **{RUN_USER}**: 运行用户（如 www、mysql、redis）
- **{DEFAULT_PORT}**: 默认服务端口
- **{DOWNLOAD_URL}**: 安装包下载地址模板
- **{INSTALL_METHOD}**: 安装方式（binary 二进制/source 源码编译/package 包管理器）
- **{HEALTH_CHECK_URL}**: 健康检查地址（如 http://127.0.0.1:{port}/status）

# 输出要求

请生成以下文件，每个文件的代码必须完整、可直接运行：

## 文件清单

### 1. `options.conf.template` — 中央配置模板
**功能**: 配置模板（git 跟踪），运行时由 `ensure_options_conf.sh` 据此生成 `options.conf`
**要求**:
- 顶部必须包含 `conf_version=N` 版本号字段，模板内容变更时递增
- 安装路径、数据目录、运行用户、密码、备份参数等
- 密码字段默认留空，由安装脚本自动生成
- 备份相关字段：backup_dir, expired_days, backup_destination, backup_content
- 使用 `key=value` 格式，用注释分组
- 配套 `.gitignore` 忽略 `options.conf` 及备份文件（`options.conf.bak*`、`options.conf.[0-9]*`）

### 2. `versions.txt` — 版本号清单
**功能**: 管理所有依赖软件的版本号
**要求**:
- 与 options.conf 分离，便于独立更新
- 命名格式：`{component}_ver=x.x.x`

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
- 多源容错：主 URL → 镜像 URL → 备用 URL
- 检测下载失败（文件 <1KB 且含 HTML 标签则视为错误页）
- 支持断点续传 (wget -c)
- 失败时提示用户手动下载路径

### 6. `include/ensure_options_conf.sh` — options.conf 模板化引导
**功能**: 运行时根据 `options.conf.template` 与 `conf_version` 自动创建/备份/升级 `options.conf`
**要求**:
- 提供 `Ensure_Options_Conf <module_dir>` 函数
- 三态判定：不存在→从模板创建；版本一致→沿用；不一致→备份旧配置后从模板重建
- 旧版无 `conf_version` 字段时备份为 `options.conf.bak`
- 旧版有版本号时备份为 `options.conf.<旧版本>`（重名追加序号）
- 所有入口脚本在 `. options.conf` 之前必须先 source 本文件并调用 `Ensure_Options_Conf`

### 7. `include/{software}.sh` — 安装/卸载模块
**功能**: 软件的安装和卸载逻辑
**要求**:
- `Install_{Software}()` 函数，完整安装流程：
  1. 检测是否已安装（幂等）
  2. 安装系统依赖 ($PM -y install ...)
  3. 下载安装包
  4. 解压、编译（或释放二进制）
  5. 生成配置文件（基于模板 sed 替换）
  6. 创建系统用户（useradd -M -s /sbin/nologin）
  7. 设置目录权限
  8. 复制并注册 systemd service
  9. 启动服务
  10. 验证安装结果
  11. 安装失败时清理并退出
- `Uninstall_{Software}()` 函数

### 8. `include/upgrade_{software}.sh` — 升级模块
**功能**: 软件的版本升级逻辑
**要求**:
- `Upgrade_{Software}()` 函数：
  1. 检测当前已安装版本
  2. 获取最新可用版本（curl 官方 API 或页面）
  3. 提示用户输入目标版本（有默认值）
  4. 校验版本号（新旧不能相同、主版本须一致）
  5. 下载新版本
  6. 升级前备份（旧二进制重命名 + 数据库 dump）
  7. 停服务 → 替换文件 → 启服务
  8. 验证升级结果

### 9. `include/monitor_{software}.sh` — 监控模块
**功能**: 健康检查与状态监控
**要求**:
- `Check_Process()` — 检查进程是否存活，不存在则尝试自动重启
- `Check_Port()` — 检查端口是否监听
- `Check_HTTP()` — HTTP 健康检查（可选，适用于 Web 服务）
- `Check_Disk()` — 检查磁盘空间
- `Check_Connection()` — 检查服务连接数/负载（可选）
- `Send_Alert()` — 告警通知（邮件 + Webhook）
- `Monitor_Status()` — 输出状态报告（版本、运行时间、资源占用）

### 10. `install.sh` — 安装主入口
**功能**: 安装主控脚本
**要求**:
- 文件头：root 检查、source 配置和公共库
- source 顺序：先 `ensure_options_conf.sh` 并调用 `Ensure_Options_Conf`，再 `options.conf`，最后其他 include
- getopt 参数解析，支持 --help, --version, --quiet, --{component}_option
- 无参数时显示交互式菜单
- 有参数时静默执行
- 密码随机生成并写入 options.conf
- 安装完成后显示摘要信息（版本、路径、端口、密码）

### 11. `uninstall.sh` — 卸载主入口
**功能**: 卸载主控脚本
**要求**:
- getopt 参数解析，支持 --quiet, --all, --{component}
- 卸载前显示将删除的文件列表（Print_XXX 函数）
- 用户确认后执行（--quiet 跳过确认）
- 数据目录重命名备份而非直接删除
- 清理 /etc/profile 中的 PATH
- 清理 options.conf 中的密码

### 12. `upgrade.sh` — 升级主入口
**功能**: 升级主控脚本
**要求**:
- getopt 参数解析，--{component} [version]
- 无参数时显示菜单
- source 对应的 upgrade 模块并调用

### 13. `backup.sh` — 备份执行脚本
**功能**: 由 cron 调用的备份执行器
**要求**:
- 从 options.conf 读取备份配置
- 支持多种备份目标：local, remote, oss, s3
- 支持备份内容：db（数据库 dump）、files（数据目录 tar）
- 过期清理：按 expired_days 删除旧备份
- 文件命名格式：`{type}_{name}_{date}_{time}.tgz`

### 14. `backup_setup.sh` — 备份配置向导
**功能**: 交互式配置备份策略
**要求**:
- 交互式选择备份目标（本地/远程/云存储）
- 交互式选择备份内容
- 配置云存储凭证并测试连通性
- 将配置写入 options.conf
- 设置 cron 定时任务

### 15. `monitor.sh` — 监控主入口
**功能**: 监控主控脚本
**要求**:
- 可由 cron 定时调用或手动执行
- 自动检测已安装的组件并执行对应检查
- 支持 --status（显示状态报告）和 --check（执行健康检查）
- 输出到日志文件 + 终端
- 异常时触发告警

### 16. `init.d/{software}.service` — systemd 服务文件
**功能**: systemd unit 定义
**要求**:
- Type=forking (守护进程模式) 或 Type=simple (前台模式)
- 配置 PIDFile, User, Group
- ExecStart/ExecStop/ExecReload
- Restart=always
- LimitNOFILE/LimitNPROC/LimitCORE=1000000
- WantedBy=multi-user.target

# 代码规范约束

1. **Shell 版本**: #!/bin/bash，兼容 Bash 4.0+
2. **缩进**: 2 空格
3. **变量命名**: 小写 + 下划线（如 `install_dir`），常量大写（如 `THREAD`）
4. **函数命名**: 大驼峰（如 `Install_Redis`, `Upgrade_Nginx`）
5. **幂等性**: 所有安装操作必须支持重复执行（已安装则跳过）
6. **错误处理**: 关键操作失败时 `kill -9 $$; exit 1`，数据操作前必须备份
7. **日志输出**: 使用 color.sh 的颜色变量（CSUCCESS/CFAILURE/CWARNING/CMSG）
8. **PATH 设置**: 脚本开头固定 `export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin`
9. **root 检查**: `[ $(id -u) != "0" ] && { echo "Error: must be root"; exit 1; }`
10. **工作目录**: 使用 `pushd/popd` 管理目录切换
11. **临时文件**: 操作完成后及时清理（rm -rf {software}-${ver}）
12. **配置分离**: 所有可变参数放 `options.conf.template`（git 跟踪，含 `conf_version`），运行时生成 `options.conf`（.gitignore 忽略）；版本号放 versions.txt，代码中只引用变量
13. **配置模板化**: 所有入口脚本 source `options.conf` 前必须先调用 `Ensure_Options_Conf` 确保文件存在且为最新版本；模板变更时递增 `conf_version`
14. **安全**: 密码用 `/dev/urandom` 生成，不硬编码；service 使用非 root 用户运行
15. **兼容性**: 支持 x86_64 和 aarch64 架构，支持 RHEL/Debian/Ubuntu 系列

# 示例：使用本模板为 Redis 生成运维代码

输入参数：
- SOFTWARE_NAME: Redis
- SOFTWARE_VERSION: 8.4.0
- INSTALL_DIR: /opt/redis
- DATA_DIR: /opt/redis/var
- RUN_USER: redis
- DEFAULT_PORT: 6379
- DOWNLOAD_URL: https://download.redis.io/releases/redis-{version}.tar.gz
- INSTALL_METHOD: source
- HEALTH_CHECK_URL: (使用 redis-cli ping)

请基于以上规范，生成 {SOFTWARE_NAME} 的完整运维代码。每个文件独立输出，包含完整可运行的代码。
```

---

## 提示词使用说明

### 如何使用

1. **复制上述提示词**（从 `# 角色` 到最后）
2. **替换 {占位符}** 为你的目标软件信息
3. **粘贴到 AI 编程工具**（Cursor / Windsurf / ChatGPT 等）
4. AI 将生成一套完整的运维脚本

### 示例场景

| 软件 | SOFTWARE_NAME | INSTALL_METHOD | DEFAULT_PORT |
|------|--------------|----------------|-------------|
| Nginx | Nginx | source | 80 |
| MySQL | MySQL | binary | 3306 |
| Redis | Redis | source | 6379 |
| PostgreSQL | PostgreSQL | source | 5432 |
| MongoDB | MongoDB | binary | 27017 |
| Apache Doris FE | Doris-FE | binary | 8030 |
| Apache Doris BE | Doris-BE | binary | 8040 |
| Elasticsearch | Elasticsearch | binary | 9200 |
| MinIO | MinIO | binary | 9000 |
| ClickHouse | ClickHouse | binary | 8123 |

### 进阶用法

如果需要同时管理多个组件（类似 oneinstack），可以追加以下指令：

```markdown
# 附加要求：多组件统一管理

请同时为以下组件生成运维代码，并在 install.sh/uninstall.sh/upgrade.sh 中
统一管理它们：

- 组件1: {name1} (端口: {port1}, 安装方式: {method1})
- 组件2: {name2} (端口: {port2}, 安装方式: {method2})
- ...

install.sh 应提供交互菜单让用户选择安装哪些组件。
uninstall.sh 应支持 --all 和 --{component} 参数。
upgrade.sh 应支持逐个组件升级。
backup.sh 应支持分别备份不同组件的数据。
monitor.sh 应自动检测已安装组件并逐一检查。
```

---

# 附录：oneinstack 模式速查表

| 模式 | oneinstack 实现 | 通用化描述 |
|------|----------------|-----------|
| 主入口分发 | `install.sh` → `source include/{x}.sh` → `Install_X()` | 主脚本只做参数解析和流程编排，具体逻辑在模块中 |
| 交互/静默双模式 | `ARG_NUM=$#`; 0 则菜单，否则 getopt | 所有主入口脚本统一支持两种模式 |
| 幂等安装 | `[ -e "${install_dir}/bin/x" ] && exit` | 安装前检测，已存在则跳过 |
| 卸载预览确认 | `Print_X()` 显示 → `Uninstall_status()` 确认 → `Uninstall_X()` 执行 | 三步式安全卸载 |
| 数据保护性删除 | `/bin/mv ${dir}{,$(date +%Y%m%d%H)}` | 重命名而非 rm，防止误删 |
| 升级版本校验 | `主版本必须一致` + `新旧不能相同` | 防止跨大版本升级和无意义升级 |
| 升级前自动备份 | `mysqldump > backup.sql` 或 `mv bin{,_date}` | 升级前必须备份 |
| 备份策略模式 | `for DEST in local,oss,s3...` → `DB_{DEST}_BK()` | 一份备份逻辑，按目标分发 |
| 过期清理 | `date --date="${expired_days} days ago"` | 备份和清理使用统一的过期天数 |
| 多源下载 | `urls=(mirror1 mirror2 official)` → 逐一尝试 | 下载可靠性保证 |
| 环境变量管理 | 安装时 `sed` 追加 PATH，卸载时 `sed` 删除 | PATH 的正反向管理 |
| 配置持久化 | `sed -i "s@^key=.*@key=value@" options.conf` | 运行时修改持久化到配置文件 |
| 配置模板化 | `options.conf.template`(git 跟踪) + `Ensure_Options_Conf` 引导 + `options.conf`(.gitignore) | 避免 git pull 覆盖用户配置，按 `conf_version` 自动备份升级 |
