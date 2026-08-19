#!/bin/bash
# Chrony 监控主入口
# 项目: dmp_ops/chrony
# 用法: ./monitor.sh [--check|--status|--sources|--clients]
# cron 示例: */5 * * * * /opt/dmp_ops/chrony/monitor.sh --check >> /var/log/chrony/monitor.log 2>&1

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

script_dir=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}" || exit 1
. "${script_dir}/options.conf"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/check_os.sh"
. "${script_dir}/include/chrony_config.sh"
. "${script_dir}/include/monitor_chrony.sh"

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

Chrony 监控脚本

Options:
  -h, --help        显示帮助
  --check           执行健康检查（异常时退出码非 0，适合 cron / Zabbix）
  --status          显示完整状态报告（默认行为）
  --sources         只显示时间源列表
  --clients         只显示客户端列表（server 角色）

EOF
}

action=status

TEMP=$(getopt -o h --long help,check,status,sources,clients -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)   Show_Help; exit 0 ;;
    --check)     action=check; shift ;;
    --status)    action=status; shift ;;
    --sources)   action=sources; shift ;;
    --clients)   action=clients; shift ;;
    --)          shift; break ;;
    *)           break ;;
  esac
done

main() {
  # 静默检测 OS（避免污染 cron 日志）
  Check_OS > /dev/null 2>&1
  # 配置中已有探测结果则直接使用，否则重新探测
  [ -z "${chrony_service}" ] && Detect_Chrony_Path

  if ! command -v chronyd > /dev/null 2>&1; then
    echo "${CFAILURE}Chrony 未安装${CEND}"
    exit 2
  fi

  case "${action}" in
    check)
      Monitor_All
      exit $?
      ;;
    status)
      Monitor_Status
      exit 0
      ;;
    sources)
      chronyc sources -v
      echo ""
      chronyc sourcestats
      exit 0
      ;;
    clients)
      if [ "${chrony_role}" != 'server' ]; then
        echo "${CWARNING}当前节点角色为 ${chrony_role}，非 NTP Server${CEND}"
      fi
      chronyc clients
      exit 0
      ;;
  esac
}

main
