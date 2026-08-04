#!/bin/bash
# MySQL 卸载主入口
# Author: DMP OPS
#
# 说明: MySQL 卸载主控脚本，安全删除 MySQL 并备份数据

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear

printf "
#######################################################################
#                     MySQL Uninstall Script                          #
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

# 显示帮助
Show_Help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help      Show this help message"
  echo "  -q, --quiet     Quiet mode (skip confirmations)"
  echo "  --mysql         Uninstall MySQL"
  echo "  --keep-data     Keep data directory (only remove binaries)"
  echo ""
  echo "Examples:"
  echo "  $0              Interactive uninstall"
  echo "  $0 -q --mysql   Quiet uninstall MySQL"
}

# 解析命令行参数
TEMP=$(getopt -o hq --long help,quiet,mysql,keep-data -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "${CWARNING}ERROR: Invalid arguments!${CEND}"; Show_Help; exit 1; }
eval set -- "${TEMP}"

quiet_flag=n
mysql_flag=n
keep_data=n
while :; do
  [ -z "$1" ] && break
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    --mysql)
      mysql_flag=y; shift 1
      ;;
    --keep-data)
      keep_data=y; shift 1
      ;;
    --)
      shift; break
      ;;
    *)
      echo "${CWARNING}ERROR: Unknown argument: $1${CEND}"; Show_Help; exit 1
      ;;
  esac
done

# 预览将删除的内容
Print_MySQL() {
  echo ""
  echo "${CWARNING}The following will be removed:${CEND}"
  echo ""
  [ -d "${db_install_dir}" ] && echo "  [DIR]  ${db_install_dir}"
  [ -e "/etc/init.d/mysqld" ] && echo "  [FILE] /etc/init.d/mysqld"
  [ -e "/etc/my.cnf" ] && echo "  [FILE] /etc/my.cnf"
  [ -e "/etc/my.cnf.d" ] && echo "  [DIR]  /etc/my.cnf.d"
  [ -e "/etc/ld.so.conf.d/z-mysql.conf" ] && echo "  [FILE] /etc/ld.so.conf.d/z-mysql.conf"
  
  if [ "${keep_data}" != "y" ]; then
    [ -d "${db_data_dir}" ] && echo "  [DIR]  ${db_data_dir} (will be renamed for backup)"
  else
    echo ""
    echo "  ${CMSG}Data directory will be kept: ${db_data_dir}${CEND}"
  fi
  echo ""
}

# 执行卸载
Uninstall_MySQL() {
  if [ -d "${db_install_dir}/support-files" ]; then
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
      echo "${CWARNING}Force killing MySQL processes...${CEND}"
      pkill -9 mysqld
      sleep 2
    fi
    
    echo "${CMSG}Removing MySQL files...${CEND}"
    
    # 删除安装目录
    rm -rf ${db_install_dir}
    
    # 删除服务脚本
    rm -f /etc/init.d/mysqld
    
    # 删除配置文件
    rm -f /etc/my.cnf*
    rm -rf /etc/my.cnf.d
    
    # 删除动态链接库配置
    rm -f /etc/ld.so.conf.d/*mysql*.conf
    ldconfig
    
    # 处理数据目录
    if [ "${keep_data}" != "y" ]; then
      if [ -d "${db_data_dir}" ]; then
        local backup_name="${db_data_dir}_backup_$(date +%Y%m%d%H%M%S)"
        echo "${CMSG}Backing up data directory to: ${backup_name}${CEND}"
        /bin/mv ${db_data_dir} ${backup_name}
      fi
    fi
    
    # 删除 mysql 用户
    if id -u mysql >/dev/null 2>&1; then
      echo "${CMSG}Removing mysql user...${CEND}"
      userdel mysql 2>/dev/null
    fi
    
    # 清理 options.conf 中的密码
    sed -i 's@^dbrootpwd=.*@dbrootpwd=@' ./options.conf
    
    # 清理环境变量
    if [ -n "$(grep ${db_install_dir} /etc/profile)" ]; then
      sed -i "s@${db_install_dir}/bin:@@g" /etc/profile
      sed -i "s@:${db_install_dir}/bin@@g" /etc/profile
    fi
    
    # 移除开机启动
    if [ "${PM}" == 'yum' ] || [ "${PM}" == 'dnf' ]; then
      chkconfig --del mysqld 2>/dev/null
    elif [ "${PM}" == 'apt-get' ]; then
      update-rc.d -f mysqld remove 2>/dev/null
    fi
    
    echo ""
    echo "${CSUCCESS}========================================${CEND}"
    echo "${CSUCCESS}MySQL uninstall completed!${CEND}"
    echo "${CSUCCESS}========================================${CEND}"
    
    if [ "${keep_data}" != "y" ] && [ -d "${backup_name}" ]; then
      echo ""
      echo "Data backup location: ${backup_name}"
      echo "You can delete it manually if no longer needed."
    fi
    echo ""
  else
    echo "${CWARNING}MySQL is not installed or already removed.${CEND}"
  fi
}

# 检测是否安装了 MySQL
if [ ! -d "${db_install_dir}/support-files" ]; then
  echo "${CWARNING}MySQL is not installed on this system.${CEND}"
  exit 0
fi

# 显示将删除的内容
Print_MySQL

# 确认卸载
if [ "${quiet_flag}" != "y" ]; then
  echo "${CFAILURE}WARNING: This operation cannot be undone!${CEND}"
  echo ""
  while :; do
    read -e -p "Do you want to continue? [y/n]: " confirm
    case "${confirm}" in
      y|Y)
        break
        ;;
      n|N)
        echo "Uninstall cancelled."
        exit 0
        ;;
      *)
        echo "Please enter y or n"
        ;;
    esac
  done
fi

# 执行卸载
Uninstall_MySQL

popd > /dev/null
