#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Upgrade script
#
# Supports upgrading: DolphinScheduler 3.2.x -> 3.3.x -> 3.4.x

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear
printf "
#######################################################################
#    DolphinSchedulerStack - Apache DolphinScheduler Deployment Tool  #
#                     Upgrade DolphinScheduler                        #
#    For more information: https://dolphinscheduler.apache.org        #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

ds_dir=$(dirname "$(readlink -f $0)")
pushd ${ds_dir} > /dev/null
. ./versions.txt
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${ds_dir}"
. ./options.conf
. ./include/color.sh
. ./include/check_os.sh
. ./include/download.sh
. ./include/check_env.sh
. ./include/dolphinscheduler.sh
. ./include/upgrade_dolphinscheduler.sh

Show_Help() {
  echo
  echo "Usage: $0 command ...[parameters]....
  --help, -h                  Show this help message
  --version [ver]             Target version to upgrade to
  --quiet, -q                 Non-interactive mode
  --rollback [backup_dir]     Rollback to a previous backup
  --check                     Check for available updates
  "
}

ARG_NUM=$#
TEMP=$(getopt -o hq --long help,version:,quiet,rollback:,check -- "$@" 2>/dev/null)
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"

quiet_flag=n
target_version=""
rollback_dir=""
check_only=n

while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    --version)
      target_version=$2; shift 2
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    --rollback)
      rollback_dir=$2; shift 2
      ;;
    --check)
      check_only=y; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

# Get current installed version
Get_Current_Version() {
  if [ -f "${dolphinscheduler_install_dir}/VERSION" ]; then
    current_version=$(cat ${dolphinscheduler_install_dir}/VERSION 2>/dev/null)
  elif [ -d "${dolphinscheduler_install_dir}" ]; then
    # Try to detect from package name or directory
    current_version="unknown"
  else
    current_version=""
  fi
}

# Show available versions
Show_Available_Versions() {
  echo ""
  echo "${CMSG}Available DolphinScheduler versions:${CEND}"
  echo -e "\t1. ${dolphinscheduler32_ver}"
  echo -e "\t2. ${dolphinscheduler33_ver}"
  echo -e "\t3. ${dolphinscheduler34_ver} (Latest)"
  echo ""
}

# Select target version
Select_Target_Version() {
  if [ -n "${target_version}" ]; then
    # Validate version
    case "${target_version}" in
      ${dolphinscheduler32_ver}|${dolphinscheduler33_ver}|${dolphinscheduler34_ver})
        ;;
      1) target_version=${dolphinscheduler32_ver} ;;
      2) target_version=${dolphinscheduler33_ver} ;;
      3) target_version=${dolphinscheduler34_ver} ;;
      *)
        echo "${CFAILURE}Invalid version: ${target_version}${CEND}"
        Show_Available_Versions
        exit 1
        ;;
    esac
    return
  fi

  Show_Available_Versions

  while :; do
    read -e -p "Please select target version (1-3): " ver_option
    case "${ver_option}" in
      1) target_version=${dolphinscheduler32_ver}; break ;;
      2) target_version=${dolphinscheduler33_ver}; break ;;
      3) target_version=${dolphinscheduler34_ver}; break ;;
      *)
        echo "${CWARNING}input error! Please only input 1~3${CEND}"
        ;;
    esac
  done
}

# Main logic
Main() {
  # Check if DolphinScheduler is installed
  if [ ! -d "${dolphinscheduler_install_dir}" ]; then
    echo "${CFAILURE}DolphinScheduler is not installed!${CEND}"
    echo "${CFAILURE}Please run install.sh first.${CEND}"
    exit 1
  fi

  Get_Current_Version

  echo ""
  echo "${CMSG}Current installation:${CEND}"
  echo "  Path:    ${dolphinscheduler_install_dir}"
  echo "  Version: ${current_version:-unknown}"
  echo ""

  # Handle rollback
  if [ -n "${rollback_dir}" ]; then
    Rollback_Upgrade "${rollback_dir}"
    exit $?
  fi

  # Check only mode
  if [ "${check_only}" == "y" ]; then
    echo "${CMSG}Checking for available updates...${CEND}"
    Get_Latest_Version
    exit 0
  fi

  # Select target version
  Select_Target_Version

  echo "${CMSG}Target version: ${target_version}${CEND}"

  # Confirm upgrade
  if [ "${quiet_flag}" != "y" ]; then
    echo ""
    echo "${CWARNING}WARNING: This will upgrade DolphinScheduler from ${current_version:-unknown} to ${target_version}${CEND}"
    echo "${CWARNING}A backup will be created before upgrade.${CEND}"
    echo ""
    while :; do
      read -e -p "Do you want to continue? [y/n]: " confirm
      if [[ ! ${confirm} =~ ^[y,n]$ ]]; then
        echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
      else
        break
      fi
    done

    if [ "${confirm}" != "y" ]; then
      echo "Upgrade cancelled."
      exit 0
    fi
  fi

  # Perform upgrade
  Upgrade_DolphinScheduler "${target_version}"
}

Main
popd > /dev/null
