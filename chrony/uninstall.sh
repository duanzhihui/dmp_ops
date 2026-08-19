#!/bin/bash
# Chrony 卸载主入口
# 项目: dmp_ops/chrony
# 用法: ./uninstall.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

script_dir=$(cd "$(dirname "$0")" && pwd)
src_dir="${script_dir}/src"

[ "$(id -u)" != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}"
. "${script_dir}/options.conf"
. "${script_dir}/versions.txt"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/check_os.sh"
. "${script_dir}/include/check_env.sh"
. "${script_dir}/include/download.sh"
. "${script_dir}/include/get_char.sh"
. "${script_dir}/include/chrony_config.sh"
. "${script_dir}/include/chrony.sh"

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

Chrony 卸载脚本

Options:
  -h, --help          显示帮助
  -q, --quiet         静默模式，跳过确认
  --keep_package      保留 chrony 软件包，仅停止服务并还原配置
  --keep_conf         保留当前配置文件（不备份/不还原）

Examples:
  $0
  $0 --quiet --keep_package

EOF
}

quiet_mode=0
keep_package=n
keep_conf=n

TEMP=$(getopt -o hq --long help,quiet,keep_package,keep_conf -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)        Show_Help; exit 0 ;;
    -q|--quiet)       quiet_mode=1; shift ;;
    --keep_package)   keep_package=y; shift ;;
    --keep_conf)      keep_conf=y; shift ;;
    --)               shift; break ;;
    *)                break ;;
  esac
done

main() {
  Check_OS
  Detect_Chrony_Path

  if ! command -v chronyd > /dev/null 2>&1; then
    echo "${CWARNING}Chrony 未安装，无需卸载${CEND}"
    exit 0
  fi

  echo ""
  Print_Chrony
  echo ""

  if [ ${quiet_mode} -eq 0 ]; then
    Confirm "确认卸载 Chrony?" || { echo "已取消"; exit 0; }
  fi

  Uninstall_Chrony
  exit $?
}

main
