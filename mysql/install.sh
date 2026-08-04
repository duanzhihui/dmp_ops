#!/bin/bash
# MySQL 安装主入口
# Author: DMP OPS
#
# 说明: MySQL 安装主控脚本，支持交互式和静默模式

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear

printf "
#######################################################################
#                     MySQL Installation Script                       #
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
. ./include/get_char.sh
. ./include/mysql-8.4.sh
. ./include/mysql-8.0.sh

# 创建 src 目录
[ ! -d "${mysql_dir}/src" ] && mkdir -p ${mysql_dir}/src

# 显示帮助
Show_Help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help              Show this help message"
  echo "  -v, --version           Show version"
  echo "  -q, --quiet             Quiet mode (skip confirmations)"
  echo "  --mysql_option [N]      MySQL version option:"
  echo "                            0 = MySQL 8.4 (default)"
  echo "                            1 = MySQL 8.0"
  echo "  --dbinstallmethod [N]   Install method:"
  echo "                            1 = Binary (default)"
  echo "                            2 = Source compile"
  echo "  -p, --password [pass]   Set root password"
  echo ""
  echo "Examples:"
  echo "  $0                      Interactive installation"
  echo "  $0 --mysql_option 0     Install MySQL 8.4 (binary)"
  echo "  $0 --mysql_option 1 --dbinstallmethod 2   Install MySQL 8.0 from source"
}

# 显示版本
Show_Version() {
  echo "MySQL Installation Script v1.0"
  echo "Available versions:"
  echo "  MySQL 8.4: ${mysql84_ver}"
  echo "  MySQL 8.0: ${mysql80_ver}"
  echo "  MySQL 5.7: ${mysql57_ver}"
}

# 解析命令行参数
TEMP=$(getopt -o hvqp: --long help,version,quiet,mysql_option:,dbinstallmethod:,password: -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "${CWARNING}ERROR: Invalid arguments!${CEND}"; Show_Help; exit 1; }
eval set -- "${TEMP}"

quiet_flag=n
mysql_option=""
while :; do
  [ -z "$1" ] && break
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -v|--version)
      Show_Version; exit 0
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    --mysql_option)
      mysql_option=$2; shift 2
      ;;
    --dbinstallmethod)
      dbinstallmethod=$2; shift 2
      ;;
    -p|--password)
      dbrootpwd=$2; shift 2
      ;;
    --)
      shift; break
      ;;
    *)
      echo "${CWARNING}ERROR: Unknown argument: $1${CEND}"; Show_Help; exit 1
      ;;
  esac
done

# 检测是否已安装
if [ -d "${mysql_install_dir}/support-files" ]; then
  echo "${CWARNING}MySQL is already installed at ${mysql_install_dir}${CEND}"
  echo "If you want to reinstall, please run uninstall.sh first."
  exit 0
fi

# 交互式菜单（无参数时）
if [ -z "${mysql_option}" ]; then
  echo ""
  echo "Please select MySQL version to install:"
  echo ""
  echo "  ${CMSG}0${CEND}. MySQL ${mysql84_ver} (LTS, recommended)"
  echo "  ${CMSG}1${CEND}. MySQL ${mysql80_ver}"
  echo "  ${CMSG}2${CEND}. MySQL ${mysql57_ver}"
  echo "  ${CMSG}q${CEND}. Quit"
  echo ""
  
  while :; do
    read -e -p "Enter your choice [0-2]: " mysql_option
    case "${mysql_option}" in
      0|1|2)
        break
        ;;
      q|Q)
        exit 0
        ;;
      *)
        echo "${CWARNING}Invalid option, please enter 0-2${CEND}"
        ;;
    esac
  done
  
  echo ""
  echo "Please select installation method:"
  echo ""
  echo "  ${CMSG}1${CEND}. Binary installation (fast, recommended)"
  echo "  ${CMSG}2${CEND}. Source compilation (slow, customizable)"
  echo ""
  
  while :; do
    read -e -p "Enter your choice [1-2]: " dbinstallmethod
    case "${dbinstallmethod}" in
      1|2)
        break
        ;;
      *)
        echo "${CWARNING}Invalid option, please enter 1 or 2${CEND}"
        ;;
    esac
  done
fi

# 设置默认值
[ -z "${dbinstallmethod}" ] && dbinstallmethod=1

# 生成随机密码（如果未指定）
if [ -z "${dbrootpwd}" ]; then
  dbrootpwd=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c8)
fi

# 显示安装信息
echo ""
echo "=========================================="
echo "Installation Summary:"
echo "=========================================="
case "${mysql_option}" in
  0) echo "  MySQL Version:    ${mysql84_ver}" ;;
  1) echo "  MySQL Version:    ${mysql80_ver}" ;;
  2) echo "  MySQL Version:    ${mysql57_ver}" ;;
esac
echo "  Install Method:   $([ "${dbinstallmethod}" == "1" ] && echo "Binary" || echo "Source")"
echo "  Install Dir:      ${mysql_install_dir}"
echo "  Data Dir:         ${mysql_data_dir}"
echo "  Root Password:    ${dbrootpwd}"
echo "=========================================="
echo ""

# 确认安装
if [ "${quiet_flag}" != "y" ]; then
  while :; do
    read -e -p "Do you want to continue? [y/n]: " confirm
    case "${confirm}" in
      y|Y)
        break
        ;;
      n|N)
        echo "Installation cancelled."
        exit 0
        ;;
      *)
        echo "Please enter y or n"
        ;;
    esac
  done
fi

# 显示系统信息
echo ""
echo "${CMSG}System Information:${CEND}"
Show_OS_Info

# 安装依赖
echo ""
echo "${CMSG}Installing dependencies...${CEND}"
if [ "${PM}" == "yum" ] || [ "${PM}" == "dnf" ]; then
  ${PM} -y install wget tar xz gcc gcc-c++ make cmake ncurses-devel openssl-devel libaio-devel
elif [ "${PM}" == "apt-get" ]; then
  ${PM} update
  ${PM} -y install wget tar xz-utils build-essential cmake libncurses5-dev libssl-dev libaio-dev
fi

# 执行安装
echo ""
echo "${CMSG}Starting MySQL installation...${CEND}"
echo ""

case "${mysql_option}" in
  0)
    Install_MySQL84
    installed_ver=${mysql84_ver}
    ;;
  1)
    Install_MySQL80
    installed_ver=${mysql80_ver}
    ;;
  2)
    # MySQL 5.7 安装（简化版，复用 8.0 逻辑）
    mysql80_ver=${mysql57_ver}
    boost_mysql80_ver=${boost_mysql57_ver}
    Install_MySQL80
    installed_ver=${mysql57_ver}
    ;;
esac

# 启动服务
echo ""
echo "${CMSG}Starting MySQL service...${CEND}"
service mysqld start
sleep 2

# 验证安装
if ${mysql_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "SELECT 1" >/dev/null 2>&1; then
  echo ""
  echo "${CSUCCESS}========================================${CEND}"
  echo "${CSUCCESS}MySQL installation completed!${CEND}"
  echo "${CSUCCESS}========================================${CEND}"
  echo ""
  echo "  Version:      MySQL ${installed_ver}"
  echo "  Install Dir:  ${mysql_install_dir}"
  echo "  Data Dir:     ${mysql_data_dir}"
  echo "  Socket:       /tmp/mysql.sock"
  echo "  Port:         3306"
  echo "  Root Password: ${CMSG}${dbrootpwd}${CEND}"
  echo ""
  echo "  Connect:      mysql -uroot -p${dbrootpwd}"
  echo ""
  
  # 保存信息到 ReadMe
  cat > ~/MySQL_ReadMe << EOF
MySQL Installation Information
==============================
Version:       MySQL ${installed_ver}
Install Dir:   ${mysql_install_dir}
Data Dir:      ${mysql_data_dir}
Socket:        /tmp/mysql.sock
Port:          3306
Root Password: ${dbrootpwd}

Connect: mysql -uroot -p${dbrootpwd}
EOF
  echo "  Info saved to: ~/MySQL_ReadMe"
  echo ""
else
  echo "${CFAILURE}MySQL installation verification failed!${CEND}"
  exit 1
fi

popd > /dev/null
