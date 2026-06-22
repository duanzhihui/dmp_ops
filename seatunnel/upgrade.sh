#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Upgrade Script
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear

# Check root
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# Get script directory
seatunnel_dir=$(dirname $(readlink -f $0))
pushd ${seatunnel_dir} > /dev/null

# Create src directory
mkdir -p ${seatunnel_dir}/src

# Source configuration and modules
. ./options.conf
. ./versions.txt
. ./include/color.sh
. ./include/check_os.sh
. ./include/check_java.sh
. ./include/download.sh
. ./include/get_char.sh
. ./include/seatunnel_config.sh
. ./include/upgrade_seatunnel.sh

# Help message
Show_Help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -h, --help              Show this help message"
  echo "  -v, --version VERSION   Upgrade to specific version"
  echo "  --rollback DIR          Rollback from backup directory"
  echo
  echo "Examples:"
  echo "  $0                      # Interactive upgrade"
  echo "  $0 -v 2.3.14            # Upgrade to version 2.3.14"
  echo "  $0 --rollback /tmp/seatunnel_upgrade_backup_xxx"
  echo
}

# Parse arguments
TEMP=$(getopt -o hv: --long help,version:,rollback: -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "Invalid options"; Show_Help; exit 1; }
eval set -- "${TEMP}"

target_version=""
rollback_dir=""

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    -v|--version)
      target_version=$2
      shift 2
      ;;
    --rollback)
      rollback_dir=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1"
      Show_Help
      exit 1
      ;;
  esac
done

# Check if SeaTunnel is installed
if [ ! -e "${seatunnel_install_dir}/bin/seatunnel.sh" ]; then
  echo "${CWARNING}SeaTunnel is not installed!${CEND}"
  exit 1
fi

# Rollback mode
if [ -n "${rollback_dir}" ]; then
  Rollback_SeaTunnel "${rollback_dir}"
  exit $?
fi

# If version specified via command line
if [ -n "${target_version}" ]; then
  # Override the prompt in Upgrade_SeaTunnel
  NEW_ver=${target_version}
fi

# Perform upgrade
Upgrade_SeaTunnel

popd > /dev/null
