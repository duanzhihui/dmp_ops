#!/bin/bash
# OpenJDK 卸载主入口
# 项目: dmp_ops/openjdk
# 用法: ./uninstall.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

openjdk_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
src_dir="${openjdk_dir}/src"

# Root 检查(--help 除外)
if [[ ! "$1" =~ ^-h$|^--help$ ]]; then
  [ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }
fi

. "${openjdk_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${openjdk_dir}"
. "${openjdk_dir}/options.conf"
. "${openjdk_dir}/versions.txt"
. "${openjdk_dir}/include/color.sh"
. "${openjdk_dir}/include/check_os.sh"
. "${openjdk_dir}/include/check_env.sh"
. "${openjdk_dir}/include/download.sh"
. "${openjdk_dir}/include/adoptium_repo.sh"
. "${openjdk_dir}/include/openjdk_package.sh"
. "${openjdk_dir}/include/openjdk_binary.sh"
. "${openjdk_dir}/include/jdk_env.sh"
. "${openjdk_dir}/include/openjdk.sh"

quiet_mode=0
force_flag=n
keep_backup=n
all_flag=n
jdk_option=""

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

OpenJDK Uninstallation Script

Options:
  -h, --help              Show this help message
  -q, --quiet             Quiet mode, skip confirmations
  --jdk_option [1-5]      1=OpenJDK8 2=OpenJDK11 3=OpenJDK17 4=OpenJDK18 5=OpenJDK21
  --all                   Uninstall all OpenJDK versions and clean env
  --force                 Uninstall even if JVM processes are using it
  --keep-backup           Keep directory backup (binary install only)

Examples:
  $0 --jdk_option 4 --keep-backup
  $0 --all -q

EOF
}

Show_Menu() {
  echo ""
  echo "${CMSG}#######################################################################${CEND}"
  echo "${CMSG}#                  OpenJDK Uninstallation Script                      #${CEND}"
  echo "${CMSG}#######################################################################${CEND}"
  echo ""
  Print_JDK_Table || exit 1
  echo ""
  echo "${CMSG}Please select the JDK version to uninstall:${CEND}"
  echo -e "\t${CMSG}1${CEND}. OpenJDK 8"
  echo -e "\t${CMSG}2${CEND}. OpenJDK 11"
  echo -e "\t${CMSG}3${CEND}. OpenJDK 17"
  echo -e "\t${CMSG}4${CEND}. OpenJDK 18"
  echo -e "\t${CMSG}5${CEND}. OpenJDK 21"
  echo -e "\t${CMSG}6${CEND}. All installed versions"
  while :; do
    read -e -p "Please input a number:(1~6) " uninstall_option
    if [[ ! "${uninstall_option}" =~ ^[1-6]$ ]]; then
      echo "${CWARNING}input error! Please only input number 1~6${CEND}"
    else
      break
    fi
  done
  if [ "${uninstall_option}" == '6' ]; then
    all_flag=y
  else
    jdk_option=${uninstall_option}
  fi
}

ARG_NUM=$#
TEMP=$(getopt -o hq --long help,quiet,jdk_option:,all,force,keep-backup -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)      Show_Help; exit 0 ;;
    -q|--quiet)     quiet_mode=1; shift ;;
    --jdk_option)
      jdk_option=$2; shift 2
      if [[ ! "${jdk_option}" =~ ^[1-5]$ ]]; then
        echo "${CWARNING}jdk_option input error! Please only input number 1~5${CEND}"
        exit 1
      fi
      ;;
    --all)          all_flag=y; shift ;;
    --force)        force_flag=y; shift ;;
    --keep-backup)  keep_backup=y; shift ;;
    --)             shift; break ;;
    *)              break ;;
  esac
done

Uninstall_One() {
  local ver=$1
  echo ""
  Print_OpenJDK ${ver} || return 0
  if [ ${quiet_mode} -ne 1 ]; then
    Uninstall_status
    [ "${uninstall_flag}" != 'y' ] && { echo "${CMSG}Skip OpenJDK ${ver}${CEND}"; return 0; }
  fi
  Uninstall_OpenJDK ${ver}
}

main() {
  Check_OS > /dev/null

  if [ ${ARG_NUM} -eq 0 ]; then
    Show_Menu
  fi

  if [ "${all_flag}" == 'y' ]; then
    local installed=$(List_JDK | awk '{print $1}')
    [ -z "${installed}" ] && { echo "${CWARNING}No OpenJDK installed${CEND}"; exit 0; }
    echo "${CMSG}Versions to uninstall: $(echo ${installed} | tr '\n' ' ')${CEND}"
    local v
    for v in ${installed}; do
      Uninstall_One ${v}
    done
    # 全部卸载后彻底清理环境变量
    [ -z "$(List_JDK)" ] && { Unset_JDK_Env; Save_Option jdk_current_ver ""; }
    exit 0
  fi

  local ver=$(Option_To_Ver ${jdk_option})
  [ -z "${ver}" ] && { echo "${CFAILURE}Invalid jdk_option: ${jdk_option}${CEND}"; exit 1; }
  Uninstall_One ${ver}
  exit $?
}

main
