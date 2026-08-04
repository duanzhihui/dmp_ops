#!/bin/bash
# MySQL 密码重置工具
# Author: DMP OPS
#
# 说明: 重置 MySQL root 密码，支持正常重置和强制重置（忘记密码）

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear

printf "
#######################################################################
#                  MySQL Password Reset Tool                          #
#                         DMP OPS Project                             #
#######################################################################
"

# 获取脚本所在目录
mysql_dir=$(dirname "$(readlink -f $0)")
pushd ${mysql_dir} > /dev/null

# Root 检查
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# 加载配置和公共库
. ./options.conf
. ./include/color.sh
. ./include/check_dir.sh

# 检测 MySQL 是否安装
if [ ! -d "${db_install_dir}/support-files" ]; then
  echo "${CFAILURE}MySQL is not installed on this system.${CEND}"
  exit 1
fi

# 显示帮助
Show_Help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help              Show this help message"
  echo "  -q, --quiet             Quiet mode"
  echo "  -f, --force             Force reset (when password is lost)"
  echo "  -p, --password [pass]   New password"
  echo ""
  echo "Examples:"
  echo "  $0                      Interactive password reset"
  echo "  $0 -f                   Force reset (lost password)"
  echo "  $0 -p newpass123        Set specific password"
}

# 生成随机密码
Generate_Password() {
  < /dev/urandom tr -dc A-Za-z0-9 | head -c8
}

# 输入新密码
Input_New_Password() {
  while :; do
    echo ""
    read -e -p "Please input the new root password: " New_dbrootpwd
    
    # 检查特殊字符
    if [ -n "$(echo ${New_dbrootpwd} | grep '[+|&]')" ]; then
      echo "${CWARNING}Password cannot contain + or &${CEND}"
      continue
    fi
    
    # 检查长度
    if (( ${#New_dbrootpwd} < 5 )); then
      echo "${CWARNING}Password must be at least 5 characters!${CEND}"
      continue
    fi
    
    break
  done
}

# 正常重置密码（知道当前密码）
Reset_Interaction_dbrootpwd() {
  echo "${CMSG}Resetting MySQL root password...${CEND}"
  
  ${db_install_dir}/bin/mysqladmin -uroot -p"${dbrootpwd}" password "${New_dbrootpwd}" -h localhost > /dev/null 2>&1
  status_Localhost=$?
  
  ${db_install_dir}/bin/mysqladmin -uroot -p"${dbrootpwd}" password "${New_dbrootpwd}" -h 127.0.0.1 > /dev/null 2>&1
  status_127=$?
  
  if [ ${status_Localhost} -eq 0 ] && [ ${status_127} -eq 0 ]; then
    sed -i "s+^dbrootpwd.*+dbrootpwd='${New_dbrootpwd}'+" ./options.conf
    echo ""
    echo "${CSUCCESS}Password reset successfully!${CEND}"
    echo "New password: ${CMSG}${New_dbrootpwd}${CEND}"
    echo ""
    return 0
  else
    echo "${CFAILURE}Password reset failed!${CEND}"
    echo "Please check if the current password is correct."
    return 1
  fi
}

# 强制重置密码（忘记密码）
Reset_force_dbrootpwd() {
  echo ""
  echo "${CWARNING}WARNING: This will stop MySQL service temporarily!${CEND}"
  echo ""
  
  # 获取 MySQL 版本
  DB_Ver=$(${db_install_dir}/bin/mysql_config --version 2>/dev/null || echo "8.0")
  
  # 停止 MySQL
  echo "${CMSG}Stopping MySQL service...${CEND}"
  service mysqld stop > /dev/null 2>&1
  
  # 等待进程完全停止
  local count=0
  while [ -n "$(pgrep mysqld)" ] && [ ${count} -lt 30 ]; do
    sleep 1
    ((count++))
  done
  
  # 强制杀死残留进程
  if [ -n "$(pgrep mysqld)" ]; then
    pkill -9 mysqld
    sleep 2
  fi
  
  echo "${CSUCCESS}MySQL service stopped${CEND}"
  
  # 启用 skip-grant-tables 模式
  echo "${CMSG}Starting MySQL in skip-grant-tables mode...${CEND}"
  sed -i '/\[mysqld\]/a\skip-grant-tables' /etc/my.cnf
  
  service mysqld start > /dev/null 2>&1
  
  # 立即移除 skip-grant-tables（下次重启就不会有了）
  sed -i '/^skip-grant-tables/d' /etc/my.cnf
  
  # 等待 MySQL 启动
  count=0
  while [ -z "$(pgrep mysqld)" ] && [ ${count} -lt 30 ]; do
    sleep 1
    ((count++))
  done
  sleep 2
  
  if [ -z "$(pgrep mysqld)" ]; then
    echo "${CFAILURE}Failed to start MySQL!${CEND}"
    return 1
  fi
  
  echo "${CSUCCESS}MySQL started in skip-grant-tables mode${CEND}"
  
  # 根据版本执行不同的密码重置命令
  echo "${CMSG}Resetting root password...${CEND}"
  
  if echo "${DB_Ver}" | grep -qE '^8\.|^5\.7\.'; then
    # MySQL 5.7+ / 8.0+
    ${db_install_dir}/bin/mysql -uroot -hlocalhost << EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${New_dbrootpwd}';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${New_dbrootpwd}';
FLUSH PRIVILEGES;
EOF
  else
    # MySQL 5.6 及更早版本
    ${db_install_dir}/bin/mysql -uroot -hlocalhost << EOF
UPDATE mysql.user SET password = PASSWORD('${New_dbrootpwd}') WHERE User = 'root';
FLUSH PRIVILEGES;
EOF
  fi
  
  if [ $? -eq 0 ]; then
    echo "${CMSG}Restarting MySQL service...${CEND}"
    
    # 停止 MySQL
    killall mysqld 2>/dev/null
    count=0
    while [ -n "$(pgrep mysqld)" ] && [ ${count} -lt 30 ]; do
      sleep 1
      ((count++))
    done
    
    if [ -n "$(pgrep mysqld)" ]; then
      pkill -9 mysqld
      sleep 2
    fi
    
    # 正常启动 MySQL
    service mysqld start > /dev/null 2>&1
    sleep 3
    
    # 更新配置文件
    sed -i "s+^dbrootpwd.*+dbrootpwd='${New_dbrootpwd}'+" ./options.conf
    
    # 更新 ReadMe 文件
    [ -e ~/MySQL_ReadMe ] && sed -i "s+^Root Password:.*+Root Password: ${New_dbrootpwd}+" ~/MySQL_ReadMe
    
    echo ""
    echo "${CSUCCESS}========================================${CEND}"
    echo "${CSUCCESS}Password reset successfully!${CEND}"
    echo "${CSUCCESS}========================================${CEND}"
    echo ""
    echo "New password: ${CMSG}${New_dbrootpwd}${CEND}"
    echo ""
    return 0
  else
    echo "${CFAILURE}Password reset failed!${CEND}"
    service mysqld start > /dev/null 2>&1
    return 1
  fi
}

# 解析命令行参数
TEMP=$(getopt -o hqfp: --long help,quiet,force,password: -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "${CWARNING}ERROR: Invalid arguments!${CEND}"; Show_Help; exit 1; }
eval set -- "${TEMP}"

quiet_flag=n
force_flag=n
New_dbrootpwd=$(Generate_Password)

while :; do
  [ -z "$1" ] && break
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    -f|--force)
      force_flag=y; shift 1
      ;;
    -p|--password)
      New_dbrootpwd=$2; shift 2
      ;;
    --)
      shift; break
      ;;
    *)
      echo "${CWARNING}ERROR: Unknown argument: $1${CEND}"; Show_Help; exit 1
      ;;
  esac
done

# 如果指定了密码，自动启用静默模式
[ -n "${New_dbrootpwd}" ] && [ "${quiet_flag}" != "y" ] && quiet_flag=y

# 交互式输入密码
if [ "${quiet_flag}" != "y" ]; then
  Input_New_Password
fi

# 执行密码重置
if [ "${force_flag}" == "y" ]; then
  # 强制重置（忘记密码）
  Reset_force_dbrootpwd
else
  # 正常重置（需要当前密码）
  if [ -z "${dbrootpwd}" ]; then
    echo "${CWARNING}Current password not found in options.conf${CEND}"
    echo "Use -f/--force option to force reset password."
    exit 1
  fi
  
  # 验证当前密码
  ${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "quit" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${CWARNING}Current password is incorrect.${CEND}"
    echo "Use -f/--force option to force reset password."
    exit 1
  fi
  
  Reset_Interaction_dbrootpwd
fi

popd > /dev/null
