#!/bin/bash
# Chrony 升级主入口
# 项目: dmp_ops/chrony
# 用法: ./upgrade.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

script_dir=$(cd "$(dirname "$0")" && pwd)
src_dir="${script_dir}/src"

[ "$(id -u)" != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}" || exit 1
. "${script_dir}/options.conf"
. "${script_dir}/versions.txt"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/check_os.sh"
. "${script_dir}/include/check_env.sh"
. "${script_dir}/include/download.sh"
. "${script_dir}/include/get_char.sh"
. "${script_dir}/include/chrony_config.sh"
. "${script_dir}/include/chrony.sh"
. "${script_dir}/include/upgrade_chrony.sh"

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

Chrony 升级脚本

Options:
  -h, --help              显示帮助
  -q, --quiet             静默模式，跳过确认
  --version VERSION       目标版本（仅 install_method=source 生效，默认: ${chrony_ver}）

说明:
  install_method=package 时通过包管理器升级到仓库中的最新版本
  升级前自动备份 chrony.conf / chrony.keys / drift 到 /tmp/chrony_upgrade_<时间戳>

EOF
}

quiet_mode=0
target_ver=""

TEMP=$(getopt -o hq --long help,quiet,version: -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)      Show_Help; exit 0 ;;
    -q|--quiet)     quiet_mode=1; shift ;;
    --version)      target_ver="$2"; shift 2 ;;
    --)             shift; break ;;
    *)              break ;;
  esac
done

main() {
  Check_OS
  Detect_Chrony_Path

  local cur
  cur=$(Get_Chrony_Version)
  [ -z "${cur}" ] && { echo "${CWARNING}Chrony 未安装，请先执行 ./install.sh${CEND}"; exit 1; }

  echo ""
  echo "${CMSG}=== 升级信息 ===${CEND}"
  echo "  当前版本  : ${cur}"
  echo "  升级方式  : ${install_method}"
  [ "${install_method}" == 'source' ] && echo "  目标版本  : ${target_ver:-${chrony_ver}}"
  echo "  配置文件  : ${chrony_conf}"
  echo ""
  echo "${CWARNING}升级过程中 chronyd 会短暂停止，时间同步会中断数秒${CEND}"
  echo ""

  if [ ${quiet_mode} -eq 0 ]; then
    Confirm "确认执行升级?" || { echo "已取消"; exit 0; }
  fi

  Upgrade_Chrony
  exit $?
}

main
