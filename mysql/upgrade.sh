#!/bin/bash
# MySQL 升级主入口
# Author: DMP OPS
#
# 说明: MySQL 版本升级主控脚本

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear

printf "
#######################################################################
#                      MySQL Upgrade Script                           #
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
. ./versions.txt
. ./include/color.sh
. ./include/check_os.sh
. ./include/check_dir.sh
. ./include/download.sh
. ./include/upgrade_db.sh

# 创建 src 目录
[ ! -d "${mysql_dir}/src" ] && mkdir -p ${mysql_dir}/src

# 显示帮助
Show_Help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help      Show this help message"
  echo "  -v, --version   Show current MySQL version"
  echo "  --mysql [ver]   Upgrade MySQL to specified version"
  echo ""
  echo "Examples:"
  echo "  $0              Interactive upgrade"
  echo "  $0 --mysql 8.0.39   Upgrade to MySQL 8.0.39"
  echo ""
  echo "Notes:"
  echo "  - Only minor version upgrades are supported"
  echo "  - A full backup will be created before upgrade"
}

# 解析命令行参数
TEMP=$(getopt -o hv --long help,version,mysql: -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "${CWARNING}ERROR: Invalid arguments!${CEND}"; Show_Help; exit 1; }
eval set -- "${TEMP}"

while :; do
  [ -z "$1" ] && break
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -v|--version)
      if [ -x "${db_install_dir}/bin/mysql" ]; then
        current_ver=$(${db_install_dir}/bin/mysql -V 2>/dev/null | awk '{print $3}' | awk -F',' '{print $1}')
        echo "Current MySQL version: ${current_ver}"
      else
        echo "MySQL is not installed."
      fi
      exit 0
      ;;
    --mysql)
      target_version=$2; shift 2
      ;;
    --)
      shift; break
      ;;
    *)
      echo "${CWARNING}ERROR: Unknown argument: $1${CEND}"; Show_Help; exit 1
      ;;
  esac
done

# 检测是否安装了 MySQL
if [ ! -d "${db_install_dir}/support-files" ]; then
  echo "${CFAILURE}MySQL is not installed on this system.${CEND}"
  echo "Please run install.sh first."
  exit 1
fi

# 显示当前版本
current_ver=$(${db_install_dir}/bin/mysql -V 2>/dev/null | awk '{print $3}' | awk -F',' '{print $1}')
echo ""
echo "Current MySQL version: ${CMSG}${current_ver}${CEND}"
echo ""

# 执行升级
Upgrade_DB

popd > /dev/null
