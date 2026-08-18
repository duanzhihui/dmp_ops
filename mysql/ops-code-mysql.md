# MySQL 运维代码模板 — 架构规范与 AI 编程提示词

> 本文档基于 oneinstack 项目的 MySQL 代码提炼，提供 **MySQL 数据库**的完整运维自动化脚本模板。
> 包含两部分：**Part A 架构规范**（代码应该长什么样）和 **Part B AI 编程提示词**（直接交给 AI 生成代码）。

---

# Part A: 架构规范

## 1. 目录结构规范

```
mysql/
├── install.sh              # 主安装入口（交互/静默双模式）
├── uninstall.sh            # 主卸载入口
├── upgrade.sh              # 主升级入口
├── backup.sh               # 备份执行脚本（由 cron 调用）
├── backup_setup.sh         # 备份策略配置向导
├── monitor.sh              # 健康检查与状态监控
├── reset_password.sh       # 重置 root 密码工具
├── mgr_setup.sh            # MGR 双活配置主入口（bootstrap/join/remove/status）
├── options.conf            # 中央配置文件（路径、密码、备份参数、MGR 配置）
├── versions.txt            # 版本号清单
├── include/                # 功能模块库
│   ├── color.sh            #   终端颜色定义
│   ├── check_os.sh         #   操作系统检测与适配
│   ├── check_dir.sh        #   安装目录检测
│   ├── download.sh         #   下载函数（多源容错）
│   ├── get_char.sh         #   交互输入辅助函数
│   ├── mysql-8.4.sh        #   MySQL 8.4 安装模块
│   ├── mysql-8.0.sh        #   MySQL 8.0 安装模块
│   ├── upgrade_db.sh       #   MySQL 升级模块
│   ├── monitor_mysql.sh    #   MySQL 监控检查模块
│   └── mgr_setup.sh        #   MGR 操作模块库
├── config/                 # 配置文件模板
│   └── my.cnf              #   MySQL 配置模板
├── tools/                  # 辅助工具脚本
│   └── db_bk.sh            #   数据库单库备份脚本
└── src/                    # 源码包存放目录
```

## 2. 核心代码模式（从 oneinstack 提炼）

### 2.1 安装模块 (mysql-8.4.sh)

```bash
Install_MySQL84() {
  pushd ${oneinstack_dir}/src > /dev/null
  
  # 1. 创建 mysql 用户（幂等）
  id -u mysql >/dev/null 2>&1
  [ $? -ne 0 ] && useradd -M -s /sbin/nologin mysql

  # 2. 创建安装目录和数据目录
  [ ! -d "${mysql_install_dir}" ] && mkdir -p ${mysql_install_dir}
  mkdir -p ${mysql_data_dir}
  chown mysql:mysql -R ${mysql_data_dir}

  # 3. 安装方式分支：二进制 vs 源码编译
  if [ "${dbinstallmethod}" == "1" ]; then
    # 二进制安装
    tar xJf mysql-${mysql84_ver}-linux-glibc2.17-x86_64.tar.xz
    mv mysql-${mysql84_ver}-linux-glibc2.17-x86_64/* ${mysql_install_dir}
    sed -i "s@/usr/local/mysql@${mysql_install_dir}@g" ${mysql_install_dir}/bin/mysqld_safe
  elif [ "${dbinstallmethod}" == "2" ]; then
    # 源码编译
    tar xzf boost_${boostVersion2}.tar.gz
    tar xzf mysql-${mysql84_ver}.tar.gz
    pushd mysql-${mysql84_ver}
    cmake . -DCMAKE_INSTALL_PREFIX=${mysql_install_dir} \
      -DMYSQL_DATADIR=${mysql_data_dir} \
      -DWITH_BOOST=../boost_${boostVersion2} \
      -DDEFAULT_CHARSET=utf8mb4
    make -j ${THREAD} && make install
    popd
  fi

  # 4. 安装后验证
  if [ -d "${mysql_install_dir}/support-files" ]; then
    sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${mysql_install_dir}/bin/mysqld_safe
    sed -i "s+^dbrootpwd.*+dbrootpwd='${dbrootpwd}'+" ../options.conf
    echo "${CSUCCESS}MySQL installed successfully! ${CEND}"
    rm -rf mysql-${mysql84_ver}-*
  else
    rm -rf ${mysql_install_dir}
    echo "${CFAILURE}MySQL install failed! ${CEND}"
    kill -9 $$; exit 1;
  fi

  # 5. 注册服务脚本
  /bin/cp ${mysql_install_dir}/support-files/mysql.server /etc/init.d/mysqld
  sed -i "s@^basedir=.*@basedir=${mysql_install_dir}@" /etc/init.d/mysqld
  sed -i "s@^datadir=.*@datadir=${mysql_data_dir}@" /etc/init.d/mysqld
  chmod +x /etc/init.d/mysqld
  [ "${PM}" == 'yum' ] && { chkconfig --add mysqld; chkconfig mysqld on; }
  [ "${PM}" == 'apt-get' ] && update-rc.d mysqld defaults

  # 6. 生成 my.cnf
  cat > /etc/my.cnf << EOF
[client]
port = 3306
socket = /tmp/mysql.sock
default-character-set = utf8mb4

[mysqld]
port = 3306
socket = /tmp/mysql.sock
basedir = ${mysql_install_dir}
datadir = ${mysql_data_dir}
pid-file = ${mysql_data_dir}/mysql.pid
user = mysql
bind-address = 0.0.0.0
server-id = 1
character-set-server = utf8mb4
collation-server = utf8mb4_0900_ai_ci
skip-name-resolve
max_connections = 1000
innodb_buffer_pool_size = 64M
log_bin = mysql-bin
binlog_format = mixed
log_error = ${mysql_data_dir}/mysql-error.log
slow_query_log = 1
slow_query_log_file = ${mysql_data_dir}/mysql-slow.log
EOF

  # 7. 根据内存调整配置
  sed -i "s@max_connections.*@max_connections = $((${Mem}/3))@" /etc/my.cnf
  [ ${Mem} -gt 3500 ] && sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 1024M@' /etc/my.cnf

  # 8. 初始化数据目录
  ${mysql_install_dir}/bin/mysqld --initialize-insecure --user=mysql --basedir=${mysql_install_dir} --datadir=${mysql_data_dir}
  chown mysql:mysql -R ${mysql_data_dir}
  service mysqld start

  # 9. 设置 PATH
  [ -z "$(grep ^'export PATH=' /etc/profile)" ] && echo "export PATH=${mysql_install_dir}/bin:\$PATH" >> /etc/profile
  . /etc/profile

  # 10. 设置 root 密码
  ${mysql_install_dir}/bin/mysql -uroot -hlocalhost -e "create user root@'127.0.0.1' identified by \"${dbrootpwd}\";"
  ${mysql_install_dir}/bin/mysql -uroot -hlocalhost -e "grant all privileges on *.* to root@'127.0.0.1' with grant option;"
  ${mysql_install_dir}/bin/mysql -uroot -hlocalhost -e "alter user root@'localhost' identified by \"${dbrootpwd}\";"

  # 11. 配置动态链接库
  echo "${mysql_install_dir}/lib" > /etc/ld.so.conf.d/z-mysql.conf
  ldconfig
  service mysqld stop
  popd
}
```

### 2.2 卸载模块

```bash
Print_MySQL() {
  [ -e "${db_install_dir}" ] && echo ${db_install_dir}
  [ -e "/etc/init.d/mysqld" ] && echo /etc/init.d/mysqld
  [ -e "/etc/my.cnf" ] && echo /etc/my.cnf
}

Uninstall_MySQL() {
  if [ -d "${db_install_dir}/support-files" ]; then
    service mysqld stop > /dev/null 2>&1
    rm -rf ${db_install_dir} /etc/init.d/mysqld /etc/my.cnf* /etc/ld.so.conf.d/*mysql*.conf
    id -u mysql >/dev/null 2>&1 ; [ $? -eq 0 ] && userdel mysql
    [ -e "${db_data_dir}" ] && /bin/mv ${db_data_dir}{,$(date +%Y%m%d%H)}
    sed -i 's@^dbrootpwd=.*@dbrootpwd=@' ./options.conf
    sed -i "s@${db_install_dir}/bin:@@" /etc/profile
    echo "${CMSG}MySQL uninstall completed! ${CEND}"
  fi
}
```

### 2.3 升级模块 (upgrade_db.sh)

```bash
Upgrade_DB() {
  pushd ${oneinstack_dir}/src > /dev/null
  [ ! -e "${db_install_dir}/bin/mysql" ] && { echo "${CWARNING}MySQL is not installed!${CEND}"; exit 1; }

  # 验证密码
  while :; do
    ${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "quit" > /dev/null 2>&1
    if [ $? -eq 0 ]; then break
    else
      read -e -p "Please input the root password: " NEW_dbrootpwd
      ${db_install_dir}/bin/mysql -uroot -p${NEW_dbrootpwd} -e "quit" >/dev/null 2>&1
      [ $? -eq 0 ] && { dbrootpwd=${NEW_dbrootpwd}; sed -i "s+^dbrootpwd.*+dbrootpwd='$dbrootpwd'+" ../options.conf; break; }
    fi
  done

  OLD_db_ver=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e 'select version()\G;' | grep version | awk '{print $2}')

  # 升级前备份
  echo "${CSUCCESS}Starting MySQL backup${CEND}......"
  ${db_install_dir}/bin/mysqldump -uroot -p${dbrootpwd} --opt --all-databases > DB_all_backup_$(date +"%Y%m%d").sql

  # 版本校验（主版本必须一致）
  echo "Current Version: ${CMSG}${OLD_db_ver}${CEND}"
  while :; do
    read -e -p "Please input upgrade version: " NEW_db_ver
    if [ $(echo ${NEW_db_ver} | awk -F. '{print $1"."$2}') == $(echo ${OLD_db_ver} | awk -F. '{print $1"."$2}') ]; then
      break
    else
      echo "${CWARNING}Major version must match!${CEND}"
    fi
  done

  # 下载并升级
  DB_filename=mysql-${NEW_db_ver}-linux-glibc2.12-x86_64
  wget -c ${DOWN_ADDR_MYSQL}/${DB_filename}.tar.xz
  tar xJf ${DB_filename}.tar.xz
  service mysqld stop
  mv ${mysql_install_dir}{,_old_$(date +"%Y%m%d_%H%M%S")}
  mv ${mysql_data_dir}{,_old_$(date +"%Y%m%d_%H%M%S")}
  mkdir -p ${mysql_install_dir} ${mysql_data_dir}
  chown mysql:mysql -R ${mysql_data_dir}
  mv ${DB_filename}/* ${mysql_install_dir}/
  ${mysql_install_dir}/bin/mysqld --initialize-insecure --user=mysql --basedir=${mysql_install_dir} --datadir=${mysql_data_dir}
  service mysqld start
  ${mysql_install_dir}/bin/mysql < DB_all_backup_$(date +"%Y%m%d").sql
  service mysqld restart
  ${mysql_install_dir}/bin/mysql_upgrade -uroot -p${dbrootpwd} >/dev/null 2>&1
  [ $? -eq 0 ] && echo "Successfully upgrade from ${OLD_db_ver} to ${NEW_db_ver}"
}
```

### 2.4 备份模块 (db_bk.sh)

```bash
. ../options.conf
. ../include/check_dir.sh

DBname=$1
LogFile=${backup_dir}/db.log
DumpFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H%M%S).sql
NewFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H%M%S).tgz
OldFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d --date="${expired_days} days ago")*.tgz

[ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}

# 检查数据库是否存在
DB_tmp=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "show databases\G" | grep ${DBname})
[ -z "${DB_tmp}" ] && { echo "[${DBname}] not exist" >> ${LogFile}; exit 1; }

# 删除过期备份
[ -n "$(ls ${OldFile} 2>/dev/null)" ] && rm -f ${OldFile}

# 执行备份
${db_install_dir}/bin/mysqldump -uroot -p${dbrootpwd} --databases ${DBname} > ${DumpFile}
pushd ${backup_dir} > /dev/null
tar czf ${NewFile} ${DumpFile##*/}
echo "[${NewFile}] Backup success" >> ${LogFile}
rm -f ${DumpFile}
popd > /dev/null
```

### 2.5 监控模块 (monitor_mysql.sh)

```bash
Check_MySQL_Process() {
  if ! pgrep -x "mysqld" > /dev/null 2>&1; then
    echo "${CFAILURE}[CRITICAL] MySQL process is NOT running!${CEND}"
    service mysqld start
    pgrep -x "mysqld" > /dev/null 2>&1 && Send_Alert "MySQL was down, auto-recovered" || Send_Alert "MySQL is DOWN"
  fi
}

Check_MySQL_Port() {
  local port=${1:-3306}
  ss -tlnp | grep -q ":${port} " || { echo "${CFAILURE}MySQL port ${port} NOT listening!${CEND}"; Send_Alert "MySQL port ${port} not listening"; }
}

Check_MySQL_Connections() {
  local threshold=${1:-80}
  local max_conn=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '/max_connections/{print $2}')
  local cur_conn=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '/Threads_connected/{print $2}')
  [ -n "${max_conn}" ] && [ -n "${cur_conn}" ] && {
    local usage=$((cur_conn * 100 / max_conn))
    [ ${usage} -gt ${threshold} ] && { echo "${CWARNING}Connections usage: ${usage}%${CEND}"; Send_Alert "MySQL connections high: ${usage}%"; }
  }
}

Check_MySQL_Replication() {
  local slave_status=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "SHOW SLAVE STATUS\G" 2>/dev/null)
  [ -n "${slave_status}" ] && {
    local io_running=$(echo "${slave_status}" | awk '/Slave_IO_Running:/{print $2}')
    local sql_running=$(echo "${slave_status}" | awk '/Slave_SQL_Running:/{print $2}')
    [ "${io_running}" != "Yes" ] || [ "${sql_running}" != "Yes" ] && Send_Alert "MySQL replication broken"
  }
}

Send_Alert() {
  local message=$1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: ${message}" >> ${log_dir}/monitor.log
  [ -n "${alert_email}" ] && echo "${message}" | mail -s "[MySQL Alert] $(hostname)" ${alert_email}
  [ -n "${webhook_url}" ] && curl -s -X POST "${webhook_url}" -H 'Content-Type: application/json' -d "{\"text\": \"${message}\"}"
}

Monitor_MySQL_All() {
  echo "========== MySQL Monitor: $(date) =========="
  Check_MySQL_Process
  Check_MySQL_Port 3306
  Check_MySQL_Connections 80
  Check_MySQL_Replication
}
```

### 2.6 密码重置 (reset_password.sh)

```bash
Reset_force_dbrootpwd() {
  echo "${CMSG}Stopping MySQL...${CEND}"
  service mysqld stop > /dev/null 2>&1
  while [ -n "$(pgrep mysqld)" ]; do sleep 1; done
  
  # 启用 skip-grant-tables
  sed -i '/\[mysqld\]/a\skip-grant-tables' /etc/my.cnf
  service mysqld start > /dev/null 2>&1
  sed -i '/^skip-grant-tables/d' /etc/my.cnf
  while [ -z "$(pgrep mysqld)" ]; do sleep 1; done
  
  ${db_install_dir}/bin/mysql -uroot -hlocalhost << EOF
update mysql.user set authentication_string=password("${New_dbrootpwd}") where user="root";
flush privileges;
EOF
  
  [ $? -eq 0 ] && {
    killall mysqld; while [ -n "$(pgrep mysqld)" ]; do sleep 1; done
    service mysqld start > /dev/null 2>&1
    sed -i "s+^dbrootpwd.*+dbrootpwd='${New_dbrootpwd}'+" ./options.conf
    echo "Password reset successfully! New password: ${CMSG}${New_dbrootpwd}${CEND}"
  }
}
```

### 2.7 MGR 双活模块 (mgr_setup.sh)

MGR 单主模式（single-primary）：一写多读 + 主挂自动选新主，并非"双写双活"。

```bash
# 前置条件检查（不执行变更）
MGR_Check_Prerequisites() {
  [ "${mgr_enable}" != "1" ] && { echo "mgr_enable != 1"; return 1; }
  [ -z "${mgr_group_name}" ] && { echo "mgr_group_name empty"; return 1; }
  [ -z "${mgr_local_address}" ] && { echo "mgr_local_address empty"; return 1; }
  [ -z "${mgr_group_seeds}" ] && { echo "mgr_group_seeds empty"; return 1; }
  # 检查运行时参数
  local gtid=$(MGR_Mysql -N -e "SELECT @@global.gtid_mode;")
  local bfmt=$(MGR_Mysql -N -e "SELECT @@global.binlog_format;")
  [ "${gtid}" != "ON" ] && return 1
  [ "${bfmt}" != "ROW" ] && return 1
}

# 引导启动新 group（仅首个节点）
MGR_Bootstrap() {
  MGR_Check_Prerequisites || return 1
  MGR_Install_Plugin
  MGR_Create_Recovery_User
  MGR_Mysql -e "SET GLOBAL group_replication_bootstrap_group=ON; \
    START GROUP_REPLICATION; \
    SET GLOBAL group_replication_bootstrap_group=OFF;"
  # 轮询等待 ONLINE
  local i=0 state=""
  while [ ${i} -lt 30 ]; do
    state=$(MGR_Mysql -N -e "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=@@hostname;")
    [ "${state}" == "ONLINE" ] && break
    sleep 1; i=$((i + 1))
  done
  [ "${state}" == "ONLINE" ] && sed -i 's/^mgr_bootstrap=1/mgr_bootstrap=0/' ${mysql_dir}/options.conf
}

# 加入现有 group（8.0 用 CHANGE MASTER TO，8.4 用 CHANGE REPLICATION SOURCE TO）
MGR_Join() {
  MGR_Check_Prerequisites || return 1
  MGR_Install_Plugin
  MGR_Create_Recovery_User
  local ver=$(MGR_Version_Adapt)
  if [ "${ver}" == "8.4" ]; then
    MGR_Mysql -e "CHANGE REPLICATION SOURCE TO SOURCE_USER='${mgr_recovery_user}', SOURCE_PASSWORD='${mgr_recovery_pwd}' FOR CHANNEL 'group_replication_recovery';"
  else
    MGR_Mysql -e "CHANGE MASTER TO MASTER_USER='${mgr_recovery_user}', MASTER_PASSWORD='${mgr_recovery_pwd}' FOR CHANNEL 'group_replication_recovery';"
  fi
  MGR_Mysql -e "START GROUP_REPLICATION;"
}

# 强制切换主（单主模式）
MGR_Set_Primary() {
  local target_id=$1
  MGR_Mysql -e "SELECT group_replication_set_as_primary('${target_id}');"
}
```

## 3. 公共库函数

### 3.1 颜色输出 (color.sh)

```bash
CSI=$'\033['
CEND="${CSI}0m"
CSUCCESS="${CSI}32m"
CFAILURE="${CSI}1;31m"
CWARNING="${CSI}1;33m"
CMSG="${CSI}1;36m"
```

### 3.2 OS 检测 (check_os.sh)

```bash
. /etc/os-release
Platform=${ID,,}
VERSION_MAIN_ID=${VERSION_ID%%.*}
ARCH=$(arch)
if [[ "${Platform}" =~ ^centos$|^rhel$|^almalinux$|^rocky$ ]]; then
  PM=yum; Family=rhel
elif [[ "${Platform}" =~ ^debian$ ]]; then
  PM=apt-get; Family=debian
elif [[ "${Platform}" =~ ^ubuntu$ ]]; then
  PM=apt-get; Family=ubuntu
fi
THREAD=$(grep 'processor' /proc/cpuinfo | wc -l)
Mem=$(free -m | awk '/Mem:/{print $2}')
```

### 3.3 下载函数 (download.sh)

```bash
Download_src() {
  local filename="${src_url##*/}"
  [ -s "${filename}" ] && { echo "[${CMSG}${filename}${CEND}] found"; return 0; }
  
  local urls=("https://mirrors.oneinstack.com/oneinstack/src/${filename}" "${src_url}")
  for url in "${urls[@]}"; do
    wget --tries=3 -c --no-check-certificate "${url}"
    [ -s "${filename}" ] && return 0
  done
  echo "${CFAILURE}Download failed! Please manually download ${src_url}${CEND}"
  kill -9 $$; exit 1;
}
```

## 4. 配置文件规范

### 4.1 options.conf

```bash
# 镜像源
mirror_link=https://mirrors.oneinstack.com

# 安装路径
mysql_install_dir=/usr/local/mysql
mysql_data_dir=/data/mysql

# 自动生成
dbrootpwd=

# 备份配置
backup_dir=/data/backup
expired_days=5
backup_destination=
db_name=
```

### 4.2 versions.txt

```bash
mysql84_ver=8.4.0
mysql80_ver=8.0.39
mysql57_ver=5.7.44
boost_mysql84_ver=1.84.0
jemalloc_ver=5.3.0
```

---

# Part B: AI 编程提示词

```markdown
# 角色
你是一位资深的 Linux 运维自动化工程师，精通 Bash Shell 编程和 MySQL 数据库管理。
你的任务是为 **MySQL** 数据库编写一套完整的运维自动化脚本。

# 输入参数
- SOFTWARE_NAME: MySQL
- SOFTWARE_VERSION: 8.4.0 (默认)
- INSTALL_DIR: /usr/local/mysql
- DATA_DIR: /data/mysql
- RUN_USER: mysql
- DEFAULT_PORT: 3306
- INSTALL_METHOD: binary

# 输出文件清单
1. options.conf — 中央配置文件
2. versions.txt — 版本号清单
3. include/color.sh — 颜色定义
4. include/check_os.sh — OS 检测
5. include/check_dir.sh — 目录检测
6. include/download.sh — 下载函数
7. include/mysql-8.4.sh — MySQL 8.4 安装模块
8. include/upgrade_db.sh — 升级模块
9. include/monitor_mysql.sh — 监控模块
10. install.sh — 安装主入口
11. uninstall.sh — 卸载主入口
12. upgrade.sh — 升级主入口
13. backup.sh — 备份执行脚本
14. monitor.sh — 监控主入口
15. reset_password.sh — 密码重置工具
16. tools/db_bk.sh — 单库备份脚本
17. config/my.cnf — MySQL 配置模板
18. mgr_setup.sh — MGR 双活配置主入口
19. include/mgr_setup.sh — MGR 操作模块库

# 代码规范
1. Shell 版本: #!/bin/bash
2. 缩进: 2 空格
3. 变量命名: 小写+下划线
4. 函数命名: 大驼峰
5. 幂等性: 已安装则跳过
6. 错误处理: 失败时 kill -9 $$; exit 1
7. 日志输出: 使用颜色变量
8. root 检查: [ $(id -u) != "0" ] && exit 1
9. 数据保护: 删除前重命名备份
10. 密码生成: /dev/urandom

# MySQL 特定要求
1. 版本支持: 8.4, 8.0, 5.7
2. 初始化: mysqld --initialize-insecure
3. jemalloc: 配置 LD_PRELOAD
4. 字符集: utf8mb4
5. 监控项: 进程、端口、连接数、复制状态、慢查询、磁盘
```

---

# 附录：oneinstack MySQL 模式速查表

| 模式 | 实现 | 说明 |
|------|------|------|
| 幂等安装 | `[ -d "${mysql_install_dir}/support-files" ] && exit` | 已安装则跳过 |
| 数据保护 | `/bin/mv ${db_data_dir}{,$(date +%Y%m%d%H)}` | 重命名而非删除 |
| 升级校验 | 主版本必须一致 | 防止跨大版本升级 |
| 升级备份 | `mysqldump --all-databases` | 升级前必须备份 |
| 密码生成 | `< /dev/urandom tr -dc A-Za-z0-9 | head -c8` | 随机密码 |
| 密码重置 | `skip-grant-tables` | 忘记密码时使用 |
| 内存调优 | 根据 Mem 变量调整 innodb_buffer_pool_size | 自动适配 |
| 多源下载 | mirrors.oneinstack.com → 官方源 | 下载可靠性 |
| 服务管理 | init.d/mysqld + chkconfig/update-rc.d | 兼容 RHEL/Debian |
| MGR 引导幂等 | `SELECT MEMBER_STATE ... WHERE MEMBER_HOST=@@hostname` | 已 ONLINE 则跳过 |
| MGR 引导复位 | `sed -i 's/^mgr_bootstrap=1/mgr_bootstrap=0/'` | 引导成功后自动改回 0 |
| MGR 版本适配 | 8.0 用 `CHANGE MASTER TO`，8.4 用 `CHANGE REPLICATION SOURCE TO` | 语法差异 |
| MGR server-id | `mgr_server_id` 留空时按 IP 末段生成 | 全组唯一 |
| MGR 参数差异 | 8.0 需 `transaction_write_set_extraction=XXHASH64`，8.4 已废弃 | 按版本渲染 |
| MGR 条件渲染 | `mgr_enable=1` 时追加 GTID/ROW/group_replication 块 | 单机不受影响 |
