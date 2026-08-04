#!/bin/bash
# 安装目录检测
# Author: DMP OPS
#
# 说明: 检测已安装的 MySQL/MariaDB/Percona 实际路径，设置统一变量

# 检测 MySQL 安装目录
if [ -d "${mysql_install_dir}/support-files" ]; then
  db_install_dir=${mysql_install_dir}
  db_data_dir=${mysql_data_dir}
  db_type="MySQL"
fi

# 检测 MariaDB 安装目录 (如果配置了)
if [ -n "${mariadb_install_dir}" ] && [ -d "${mariadb_install_dir}/support-files" ]; then
  db_install_dir=${mariadb_install_dir}
  db_data_dir=${mariadb_data_dir}
  db_type="MariaDB"
fi

# 检测 Percona 安装目录 (如果配置了)
if [ -n "${percona_install_dir}" ] && [ -d "${percona_install_dir}/support-files" ]; then
  db_install_dir=${percona_install_dir}
  db_data_dir=${percona_data_dir}
  db_type="Percona"
fi

# 检测数据库版本
Get_DB_Version() {
  if [ -x "${db_install_dir}/bin/mysql" ]; then
    db_version=$(${db_install_dir}/bin/mysql -V 2>/dev/null | awk '{print $3}' | awk -F',' '{print $1}')
    db_version_main=$(echo ${db_version} | awk -F. '{print $1"."$2}')
  fi
}

# 检测数据库是否运行
Check_DB_Running() {
  if pgrep -x "mysqld" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# 检测数据库连接
Check_DB_Connection() {
  local password=${1:-${dbrootpwd}}
  if [ -x "${db_install_dir}/bin/mysql" ]; then
    ${db_install_dir}/bin/mysql -uroot -p"${password}" -e "SELECT 1" >/dev/null 2>&1
    return $?
  fi
  return 1
}
