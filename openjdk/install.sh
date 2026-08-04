#!/bin/bash
# OpenJDK 安装主入口
# 项目: dmp_ops/openjdk
# 用法: ./install.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

openjdk_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
src_dir="${openjdk_dir}/src"

# Root 检查(--help/--version 除外)
if [[ ! "$1" =~ ^-h$|^--help$|^-v$|^--version$ ]]; then
  [ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }
fi

# 加载配置与公共库
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

install_log="${openjdk_dir}/install.log"
set_default=y
quiet_mode=0
jdk_option=""

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

OpenJDK Installation Script

Options:
  -h, --help                      Show this help message
  -v, --version                   Show supported versions
  -q, --quiet                     Quiet mode, skip confirmations

  --jdk_option [1-5]              1=OpenJDK8  2=OpenJDK11  3=OpenJDK17
                                  4=OpenJDK18(EOL, not recommended)  5=OpenJDK21
  --install_method [package|binary]
                                  package: distro package manager (default)
                                  binary : Adoptium tar.gz
  --jdk_patch_ver VERSION         Pin patch version for binary mode (e.g. 21.0.7+6)
  --set_default                   Set as default JDK (default behavior)
  --no_default                    Install only, keep current default JDK

Examples:
  # Interactive
  $0

  # Install OpenJDK 17 via package manager, set as default
  $0 -q --jdk_option 3 --install_method package

  # Install OpenJDK 21 from Adoptium tar.gz without changing default
  $0 -q --jdk_option 5 --install_method binary --no_default

EOF
}

Show_Version() {
  echo "OpenJDK Installation Script"
  echo "Supported versions : ${jdk_support_vers}"
  echo "Default version    : ${jdk_default_ver}"
  echo "Install method     : ${install_method}"
}

Show_Menu() {
  clear
  echo ""
  echo "${CMSG}#######################################################################${CEND}"
  echo "${CMSG}#                   OpenJDK Installation Script                       #${CEND}"
  echo "${CMSG}#                      https://adoptium.net                           #${CEND}"
  echo "${CMSG}#######################################################################${CEND}"
  echo ""

  Check_OS
  echo ""

  # 已装版本提示
  if [ -n "$(List_JDK)" ]; then
    echo "${CMSG}Already installed:${CEND}"
    Print_JDK_Table
    echo ""
  fi

  # 版本选择
  echo "${CMSG}Please select JDK version:${CEND}"
  echo -e "\t${CMSG}1${CEND}. Install OpenJDK 8  (LTS)"
  echo -e "\t${CMSG}2${CEND}. Install OpenJDK 11 (LTS)"
  echo -e "\t${CMSG}3${CEND}. Install OpenJDK 17 (LTS)"
  echo -e "\t${CMSG}4${CEND}. Install OpenJDK 18 (non-LTS, EOL, not recommended)"
  echo -e "\t${CMSG}5${CEND}. Install OpenJDK 21 (LTS)"
  local def_option=$(Ver_To_Option ${jdk_default_ver})
  while :; do
    read -e -p "Please input a number:(Default ${def_option} press Enter) " jdk_option
    jdk_option=${jdk_option:-${def_option}}
    if [[ ! "${jdk_option}" =~ ^[1-5]$ ]]; then
      echo "${CWARNING}input error! Please only input number 1~5${CEND}"
    else
      break
    fi
  done

  # 安装方式
  echo ""
  echo "${CMSG}Please select install method:${CEND}"
  echo -e "\t${CMSG}1${CEND}. Package manager (distro repo, fallback to Adoptium)"
  echo -e "\t${CMSG}2${CEND}. Binary tar.gz (Eclipse Temurin from Adoptium)"
  while :; do
    read -e -p "Please input a number:(Default 1 press Enter) " method_option
    method_option=${method_option:-1}
    case "${method_option}" in
      1) install_method=package; break ;;
      2) install_method=binary;  break ;;
      *) echo "${CWARNING}input error! Please only input number 1~2${CEND}" ;;
    esac
  done

  # 是否设为默认
  echo ""
  while :; do
    read -e -p "Set it as the default JDK? [y/n]: (Default y press Enter) " default_flag
    default_flag=${default_flag:-y}
    if [[ ! "${default_flag}" =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      set_default=${default_flag}
      break
    fi
  done

  local ver=$(Option_To_Ver ${jdk_option})
  echo ""
  echo "${CMSG}=== Installation Summary ===${CEND}"
  echo "  JDK Version    : ${ver}"
  echo "  Install Method : ${install_method}"
  echo "  Set as Default : ${set_default}"
  [ "${install_method}" == 'binary' ] && echo "  Install Dir    : ${jdk_base_dir}/jdk-${ver}"
  echo ""
  read -e -p "Continue with installation? [y/n]: " confirm
  [ "${confirm}" != 'y' ] && exit 0
}

# ---------- 参数解析 ----------
ARG_NUM=$#
TEMP=$(getopt -o hvq --long help,version,quiet,jdk_option:,install_method:,jdk_patch_ver:,set_default,no_default -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)
      Show_Help; exit 0 ;;
    -v|--version)
      Show_Version; exit 0 ;;
    -q|--quiet)
      quiet_mode=1; shift ;;
    --jdk_option)
      jdk_option=$2; shift 2
      if [[ ! "${jdk_option}" =~ ^[1-5]$ ]]; then
        echo "${CWARNING}jdk_option input error! Please only input number 1~5${CEND}"
        exit 1
      fi
      ;;
    --install_method)
      install_method=$2; shift 2
      if [[ ! "${install_method}" =~ ^package$|^binary$ ]]; then
        echo "${CWARNING}install_method input error! Please only input 'package' or 'binary'${CEND}"
        exit 1
      fi
      ;;
    --jdk_patch_ver)
      jdk_patch_ver=$2; shift 2 ;;
    --set_default)
      set_default=y; shift ;;
    --no_default)
      set_default=n; shift ;;
    --)
      shift; break ;;
    *)
      break ;;
  esac
done

main() {
  if [ ${ARG_NUM} -eq 0 ]; then
    Show_Menu
  else
    Check_OS
    [ -z "${jdk_option}" ] && jdk_option=$(Ver_To_Option ${jdk_default_ver})
  fi

  local ver=$(Option_To_Ver ${jdk_option})
  [ -z "${ver}" ] && { echo "${CFAILURE}Invalid jdk_option: ${jdk_option}${CEND}"; exit 1; }

  # 配置持久化
  Save_Option install_method "${install_method}"
  [ -n "${jdk_patch_ver}" ] && Save_Option jdk_patch_ver "${jdk_patch_ver}"

  Install_OpenJDK ${ver} 2>&1 | tee -a "${install_log}"
  exit ${PIPESTATUS[0]}
}

main
