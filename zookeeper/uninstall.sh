#!/bin/bash
# ZooKeeper 卸载主入口
# 项目: oneinstack/zookeeper
# 用法: ./uninstall.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本目录
script_dir=$(cd "$(dirname "$0")" && pwd)

# Root 检查
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# 加载配置和公共库
. "${script_dir}/options.conf"
. "${script_dir}/versions.txt"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/zookeeper.sh"

# 显示帮助
Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

ZooKeeper Uninstallation Script

Options:
  -h, --help        Show this help message
  -q, --quiet       Quiet mode, skip confirmations
  --keep-data       Keep data directory (backup only)

Examples:
  $0                    # Interactive uninstall
  $0 --quiet            # Uninstall without confirmation
  $0 --keep-data        # Uninstall but keep data

EOF
}

# 解析参数
quiet_mode=0
keep_data=0

TEMP=$(getopt -o hq --long help,quiet,keep-data -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }

eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    -q|--quiet)
      quiet_mode=1
      shift
      ;;
    --keep-data)
      keep_data=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

# 主逻辑
main() {
  # 检查是否已安装
  if [ ! -e "${zk_install_dir}/bin/zkServer.sh" ]; then
    echo "${CWARNING}ZooKeeper is not installed${CEND}"
    exit 0
  fi
  
  # 显示将删除的内容
  Print_ZooKeeper
  echo ""
  
  # 确认
  if [ "${quiet_mode}" -eq 0 ]; then
    read -e -p "Do you want to uninstall ZooKeeper? [y/n]: " confirm
    [ "${confirm}" != "y" ] && exit 0
  fi
  
  # 执行卸载
  if [ "${keep_data}" -eq 1 ]; then
    echo "${CMSG}Keeping data directory...${CEND}"
    # 只停止服务和删除安装目录
    systemctl stop zookeeper 2>/dev/null
    systemctl disable zookeeper 2>/dev/null
    rm -f /lib/systemd/system/zookeeper.service
    systemctl daemon-reload
    rm -rf "${zk_install_dir}"
    echo "${CSUCCESS}ZooKeeper uninstalled (data preserved)${CEND}"
  else
    Uninstall_ZooKeeper
  fi
  
  exit $?
}

main
