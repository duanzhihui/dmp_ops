#!/bin/bash
# ZooKeeper 监控主入口
# 项目: oneinstack/zookeeper
# 用法: ./monitor.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本目录
script_dir=$(cd "$(dirname "$0")" && pwd)

# 加载配置和公共库
. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}"
. "${script_dir}/options.conf"
. "${script_dir}/versions.txt"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/monitor_zk.sh"
. "${script_dir}/include/cluster.sh"

# 显示帮助
Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

ZooKeeper Monitoring Script

Options:
  -h, --help        Show this help message
  --status          Show status report
  --check           Run health checks
  --metrics         Show metrics (mntr)
  --connections     Show client connections
  --cluster         Check cluster status
  --watch           Continuous monitoring (every 5s)

Examples:
  $0 --status       # Show current status
  $0 --check        # Run all health checks
  $0 --cluster      # Check cluster status
  $0 --watch        # Continuous monitoring

EOF
}

# 持续监控
Watch_Mode() {
  local interval=${1:-5}
  
  echo "${CMSG}Continuous monitoring (Ctrl+C to stop)${CEND}"
  echo "Refresh interval: ${interval}s"
  echo ""
  
  while true; do
    clear
    Monitor_ZooKeeper
    sleep ${interval}
  done
}

# 解析参数
action="status"

TEMP=$(getopt -o h --long help,status,check,metrics,connections,cluster,watch -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }

eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    --status)
      action="status"
      shift
      ;;
    --check)
      action="check"
      shift
      ;;
    --metrics)
      action="metrics"
      shift
      ;;
    --connections)
      action="connections"
      shift
      ;;
    --cluster)
      action="cluster"
      shift
      ;;
    --watch)
      action="watch"
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
  case "${action}" in
    status)
      Monitor_Status
      ;;
    check)
      Monitor_ZooKeeper
      ;;
    metrics)
      Check_ZK_Metrics
      ;;
    connections)
      Check_ZK_Connections
      ;;
    cluster)
      Check_Cluster_Status
      ;;
    watch)
      Watch_Mode 5
      ;;
  esac
  
  exit $?
}

main
