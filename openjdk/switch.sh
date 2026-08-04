#!/bin/bash
# 默认 JDK 版本切换(OpenJDK 专属)
# 项目: dmp_ops/openjdk
# 用法: ./switch.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

openjdk_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
src_dir="${openjdk_dir}/src"

# Root 检查(--help/--list 除外)
if [[ ! "$1" =~ ^-h$|^--help$|^-l$|^--list$ ]]; then
  [ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }
fi

. "${openjdk_dir}/options.conf"
. "${openjdk_dir}/versions.txt"
. "${openjdk_dir}/include/color.sh"
. "${openjdk_dir}/include/check_os.sh"
. "${openjdk_dir}/include/check_env.sh"
. "${openjdk_dir}/include/jdk_env.sh"

jdk_option=""
list_flag=n

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

Switch the default OpenJDK version (symlink ${jdk_link} + alternatives)

Options:
  -h, --help              Show this help message
  -l, --list              List installed JDKs
  --jdk_option [1-5]      1=OpenJDK8 2=OpenJDK11 3=OpenJDK17 4=OpenJDK18 5=OpenJDK21

Examples:
  $0 --list
  $0 --jdk_option 2

EOF
}

ARG_NUM=$#
TEMP=$(getopt -o hl --long help,list,jdk_option: -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help) Show_Help; exit 0 ;;
    -l|--list) list_flag=y; shift ;;
    --jdk_option)
      jdk_option=$2; shift 2
      if [[ ! "${jdk_option}" =~ ^[1-5]$ ]]; then
        echo "${CWARNING}jdk_option input error! Please only input number 1~5${CEND}"
        exit 1
      fi
      ;;
    --) shift; break ;;
    *)  break ;;
  esac
done

main() {
  Check_OS > /dev/null

  if [ "${list_flag}" == 'y' ]; then
    Print_JDK_Table
    exit $?
  fi

  if [ ${ARG_NUM} -eq 0 ]; then
    echo ""
    echo "${CMSG}Installed JDKs:${CEND}"
    Print_JDK_Table || exit 1
    echo ""
    echo "${CMSG}Please select the JDK version to set as default:${CEND}"
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
  fi

  local ver=$(Option_To_Ver ${jdk_option})
  [ -z "${ver}" ] && { echo "${CFAILURE}Invalid jdk_option: ${jdk_option}${CEND}"; exit 1; }

  Switch_JDK ${ver}
  exit $?
}

main
