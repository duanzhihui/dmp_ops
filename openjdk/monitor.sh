#!/bin/bash
# OpenJDK 监控主入口
# 项目: dmp_ops/openjdk
# 用法: ./monitor.sh [--status | --check | --jvm PID]
# 可由 cron 定时调用: */5 * * * * /path/to/monitor.sh --check >> /var/log/openjdk/monitor.log 2>&1

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

openjdk_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
src_dir="${openjdk_dir}/src"

. "${openjdk_dir}/options.conf"
. "${openjdk_dir}/versions.txt"
. "${openjdk_dir}/include/color.sh"
. "${openjdk_dir}/include/check_os.sh"
. "${openjdk_dir}/include/check_env.sh"
. "${openjdk_dir}/include/jdk_env.sh"
. "${openjdk_dir}/include/monitor_jdk.sh"

action=""
jvm_pid=""

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

OpenJDK / JVM Monitoring Script

Options:
  -h, --help        Show this help message
  --status          Show status report (default JDK, installed JDKs, JVM processes)
  --check           Run health check (JDK env, heap, GC, threads, disk)
  --jvm PID         Show detail of a specific JVM process

Examples:
  $0 --status
  $0 --check
  $0 --jvm 12345

EOF
}

TEMP=$(getopt -o h --long help,status,check,jvm: -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help) Show_Help; exit 0 ;;
    --status)  action=status; shift ;;
    --check)   action=check; shift ;;
    --jvm)     action=jvm; jvm_pid=$2; shift 2 ;;
    --) shift; break ;;
    *)  break ;;
  esac
done

main() {
  Check_OS > /dev/null
  mkdir -p "${log_dir}"

  case "${action}" in
    status) Monitor_Status ;;
    check)  Monitor_Check ;;
    jvm)
      [ -z "${jvm_pid}" ] && { echo "${CFAILURE}--jvm requires a PID${CEND}"; exit 1; }
      Check_JVM_Detail "${jvm_pid}"
      ;;
    *)      Monitor_Status ;;
  esac
  exit $?
}

main
