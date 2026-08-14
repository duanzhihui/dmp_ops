#!/bin/bash
# OpenJDK 升级主入口
# 项目: dmp_ops/openjdk
# 用法: ./upgrade.sh [OPTIONS]
# 说明: 只支持同 feature 版本内的补丁升级，跨大版本请用 install.sh + switch.sh

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
. "${openjdk_dir}/include/upgrade_jdk.sh"

quiet_mode=0
jdk_option=""
target_patch_ver=""

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

OpenJDK Upgrade Script (patch-level upgrade within the same feature version)

Options:
  -h, --help                Show this help message
  -q, --quiet               Quiet mode, use latest GA without asking
  --jdk_option [1-5]        1=OpenJDK8 2=OpenJDK11 3=OpenJDK17 4=OpenJDK18 5=OpenJDK21
  --jdk_patch_ver VERSION   Target patch version (e.g. 17.0.15+6)

Examples:
  $0 --jdk_option 3
  $0 -q --jdk_option 5

EOF
}

Show_Menu() {
  echo ""
  echo "${CMSG}#######################################################################${CEND}"
  echo "${CMSG}#                     OpenJDK Upgrade Script                          #${CEND}"
  echo "${CMSG}#######################################################################${CEND}"
  echo ""
  Print_JDK_Table || exit 1
  echo ""
  echo "${CMSG}Please select the JDK version to upgrade:${CEND}"
  echo -e "\t${CMSG}1${CEND}. OpenJDK 8"
  echo -e "\t${CMSG}2${CEND}. OpenJDK 11"
  echo -e "\t${CMSG}3${CEND}. OpenJDK 17"
  echo -e "\t${CMSG}4${CEND}. OpenJDK 18"
  echo -e "\t${CMSG}5${CEND}. OpenJDK 21"
  while :; do
    read -e -p "Please input a number:(1~5) " jdk_option
    if [[ ! "${jdk_option}" =~ ^[1-5]$ ]]; then
      echo "${CWARNING}input error! Please only input number 1~5${CEND}"
    else
      break
    fi
  done
}

ARG_NUM=$#
TEMP=$(getopt -o hq --long help,quiet,jdk_option:,jdk_patch_ver: -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)  Show_Help; exit 0 ;;
    -q|--quiet) quiet_mode=1; shift ;;
    --jdk_option)
      jdk_option=$2; shift 2
      if [[ ! "${jdk_option}" =~ ^[1-5]$ ]]; then
        echo "${CWARNING}jdk_option input error! Please only input number 1~5${CEND}"
        exit 1
      fi
      ;;
    --jdk_patch_ver) target_patch_ver=$2; shift 2 ;;
    --) shift; break ;;
    *)  break ;;
  esac
done

main() {
  Check_OS > /dev/null

  if [ -z "${jdk_option}" ]; then
    [ ${ARG_NUM} -eq 0 ] && Show_Menu || { echo "${CFAILURE}--jdk_option is required${CEND}"; exit 1; }
  fi

  local ver=$(Option_To_Ver ${jdk_option})
  [ -z "${ver}" ] && { echo "${CFAILURE}Invalid jdk_option: ${jdk_option}${CEND}"; exit 1; }

  Upgrade_OpenJDK ${ver} 2>&1 | tee -a "${openjdk_dir}/upgrade.log"
  exit ${PIPESTATUS[0]}
}

main
