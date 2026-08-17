#!/bin/bash
# ZooKeeper 升级主入口
# 项目: oneinstack/zookeeper
# 用法: ./upgrade.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本目录
script_dir=$(cd "$(dirname "$0")" && pwd)
src_dir="${script_dir}/src"

# Root 检查
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# 加载配置和公共库
. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}"
. "${script_dir}/options.conf"
. "${script_dir}/versions.txt"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/check_os.sh"
. "${script_dir}/include/check_env.sh"
. "${script_dir}/include/download.sh"
. "${script_dir}/include/zookeeper.sh"
. "${script_dir}/include/upgrade_zk.sh"
. "${script_dir}/include/cluster.sh"

# 显示帮助
Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

ZooKeeper Upgrade Script

Options:
  -h, --help        Show this help message
  --zk_ver VERSION  Specify target version
  --rolling         Rolling upgrade (for cluster mode)

Available versions:
  ${zk39_ver} (requires JDK 11+)
  ${zk38_ver} (requires JDK 8+)
  ${zk37_ver} (requires JDK 8+)

Examples:
  $0                        # Interactive upgrade
  $0 --zk_ver 3.9.5         # Upgrade to specific version
  $0 --rolling --zk_ver 3.9.5  # Rolling upgrade for cluster

EOF
}

# 解析参数
new_ver=""
rolling_mode=0

TEMP=$(getopt -o h --long help,zk_ver:,rolling -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }

eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    --zk_ver)
      new_ver="$2"
      shift 2
      ;;
    --rolling)
      rolling_mode=1
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
  # 检测操作系统
  Check_OS
  
  # 执行升级
  if [ "${rolling_mode}" -eq 1 ]; then
    Rolling_Upgrade "${new_ver}"
  else
    Upgrade_ZooKeeper "${new_ver}"
  fi
  
  exit $?
}

main
