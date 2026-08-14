#!/bin/bash
# MySQL 监控主入口
# Author: DMP OPS
#
# 说明: MySQL 监控主控脚本，可由 cron 定时调用或手动执行

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本所在目录
mysql_dir=$(dirname "$(readlink -f $0)")
pushd ${mysql_dir} > /dev/null

# 加载配置和公共库
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${mysql_dir}"
. ./options.conf
. ./include/color.sh
. ./include/check_dir.sh
. ./include/monitor_mysql.sh

# 确保日志目录存在
[ ! -d "${log_dir}" ] && mkdir -p ${log_dir}

# 显示帮助
Show_Help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help      Show this help message"
  echo "  -s, --status    Show MySQL status report"
  echo "  -c, --check     Run health checks"
  echo "  -a, --all       Run all checks and show status"
  echo "  -q, --quiet     Quiet mode (only output on errors)"
  echo ""
  echo "Examples:"
  echo "  $0              Interactive mode"
  echo "  $0 --check      Run health checks"
  echo "  $0 --status     Show status report"
}

# 解析命令行参数
TEMP=$(getopt -o hscaq --long help,status,check,all,quiet -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "${CWARNING}ERROR: Invalid arguments!${CEND}"; Show_Help; exit 1; }
eval set -- "${TEMP}"

action=""
quiet_flag=n
while :; do
  [ -z "$1" ] && break
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -s|--status)
      action="status"; shift 1
      ;;
    -c|--check)
      action="check"; shift 1
      ;;
    -a|--all)
      action="all"; shift 1
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
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
  exit 1
fi

# 执行操作
case "${action}" in
  status)
    Monitor_MySQL_Status
    ;;
  check)
    if [ "${quiet_flag}" == "y" ]; then
      # 静默模式：只在有问题时输出
      result=$(Monitor_MySQL_All 2>&1)
      if echo "${result}" | grep -qE "CRITICAL|WARNING"; then
        echo "${result}"
      fi
    else
      Monitor_MySQL_All
    fi
    ;;
  all)
    Monitor_MySQL_All
    echo ""
    Monitor_MySQL_Status
    ;;
  *)
    # 交互式菜单
    echo ""
    echo "MySQL Monitor"
    echo ""
    echo "  1. Run health checks"
    echo "  2. Show status report"
    echo "  3. Run all checks and show status"
    echo "  q. Quit"
    echo ""
    
    read -e -p "Enter your choice: " choice
    
    case "${choice}" in
      1)
        Monitor_MySQL_All
        ;;
      2)
        Monitor_MySQL_Status
        ;;
      3)
        Monitor_MySQL_All
        echo ""
        Monitor_MySQL_Status
        ;;
      q|Q)
        exit 0
        ;;
      *)
        echo "Invalid choice"
        ;;
    esac
    ;;
esac

popd > /dev/null
