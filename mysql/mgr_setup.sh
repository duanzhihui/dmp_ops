#!/bin/bash
# MySQL MGR (Group Replication) 主入口
# Author: DMP OPS
#
# 说明: MGR 单主模式（single-primary）的引导/加入/退出/状态/切换操作主控脚本。
#       单主模式 = 一写多读 + 主挂自动选新主，并非"双写双活"。
#
# 用法:
#   ./mgr_setup.sh --bootstrap              引导启动新 group（仅首个节点）
#   ./mgr_setup.sh --join                   加入现有 group
#   ./mgr_setup.sh --remove                 退出 group
#   ./mgr_setup.sh --status                 查看 group 成员与状态
#   ./mgr_setup.sh --set-primary <id>       强制切换主
#   ./mgr_setup.sh --check                  前置条件检查（不执行任何变更）
#   ./mgr_setup.sh --install-plugin         仅安装 group_replication 插件
#   ./mgr_setup.sh -h, --help               显示帮助

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear

printf "
#######################################################################
#                  MySQL MGR Setup Script                             #
#                  Group Replication (single-primary)                 #
#                      DMP OPS Project                                #
#######################################################################
"

# 获取脚本所在目录
mysql_dir=$(dirname "$(readlink -f $0)")
pushd ${mysql_dir} > /dev/null

# Root 检查
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# 加载配置和公共库
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${mysql_dir}"
. ./options.conf
. ./include/color.sh
. ./include/check_dir.sh
. ./include/mgr_setup.sh

# 显示帮助
Show_Help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help                Show this help message"
  echo "  --bootstrap               Bootstrap a new MGR group (first node only)"
  echo "  --join                    Join an existing MGR group"
  echo "  --remove                  Leave the MGR group"
  echo "  --status                  Show MGR group members and status"
  echo "  --set-primary <id>        Force switch primary to <member_id>"
  echo "  --check                   Check prerequisites (no changes)"
  echo "  --install-plugin          Install group_replication plugin only"
  echo "  -q, --quiet               Quiet mode"
  echo ""
  echo "Examples:"
  echo "  $0 --bootstrap            First node starts a new group"
  echo "  $0 --join                 Other nodes join the group"
  echo "  $0 --status               Check group status"
  echo "  $0 --set-primary uuid     Force switch primary"
}

# 解析命令行参数
TEMP=$(getopt -o hq --long help,quiet,bootstrap,join,remove,status,set-primary:,check,install-plugin -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "${CWARNING}ERROR: Invalid arguments!${CEND}"; Show_Help; exit 1; }
eval set -- "${TEMP}"

action=""
set_primary_target=""
quiet_flag=n
while :; do
  [ -z "$1" ] && break
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    --bootstrap)
      action="bootstrap"; shift 1
      ;;
    --join)
      action="join"; shift 1
      ;;
    --remove)
      action="remove"; shift 1
      ;;
    --status)
      action="status"; shift 1
      ;;
    --set-primary)
      action="set-primary"; set_primary_target=$2; shift 2
      ;;
    --check)
      action="check"; shift 1
      ;;
    --install-plugin)
      action="install-plugin"; shift 1
      ;;
    --)
      shift; break
      ;;
    *)
      echo "${CWARNING}ERROR: Unknown argument: $1${CEND}"; Show_Help; exit 1
      ;;
  esac
done

# 检测 MySQL 是否安装
if [ ! -d "${db_install_dir}/support-files" ]; then
  echo "${CFAILURE}MySQL is not installed on this system.${CEND}"
  echo "  请先运行 ./install.sh 安装 MySQL"
  exit 1
fi

# 检测 mysqld 是否运行
if ! pgrep -x "mysqld" >/dev/null 2>&1; then
  echo "${CFAILURE}MySQL is not running.${CEND}"
  echo "  请先运行 service mysqld start"
  exit 1
fi

# 无参数时显示交互式菜单
if [ -z "${action}" ]; then
  echo ""
  echo "MySQL MGR Setup (single-primary mode)"
  echo ""
  echo "  ${CMSG}1${CEND}. Bootstrap a new group (first node)"
  echo "  ${CMSG}2${CEND}. Join existing group"
  echo "  ${CMSG}3${CEND}. Leave group"
  echo "  ${CMSG}4${CEND}. Show group status"
  echo "  ${CMSG}5${CEND}. Check prerequisites"
  echo "  ${CMSG}6${CEND}. Install group_replication plugin"
  echo "  ${CMSG}q${CEND}. Quit"
  echo ""

  read -e -p "Enter your choice [1-6]: " choice
  case "${choice}" in
    1) action="bootstrap" ;;
    2) action="join" ;;
    3) action="remove" ;;
    4) action="status" ;;
    5) action="check" ;;
    6) action="install-plugin" ;;
    q|Q) exit 0 ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
fi

# 执行操作
case "${action}" in
  bootstrap)
    MGR_Bootstrap
    ;;
  join)
    MGR_Join
    ;;
  remove)
    MGR_Remove
    ;;
  status)
    MGR_Status
    ;;
  set-primary)
    MGR_Set_Primary "${set_primary_target}"
    ;;
  check)
    MGR_Check_Prerequisites
    ;;
  install-plugin)
    MGR_Install_Plugin
    ;;
esac

popd > /dev/null
