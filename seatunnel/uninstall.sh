#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Uninstall Script
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

# Source configuration and modules
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${seatunnel_dir}"
. ./options.conf
. ./versions.txt
. ./include/color.sh
. ./include/check_os.sh
. ./include/seatunnel.sh

# Help message
Show_Help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -h, --help       Show this help message"
  echo "  -q, --quiet      Quiet mode, skip confirmations"
  echo "  --keep_data      Keep data directory (backup instead of delete)"
  echo
  echo "Examples:"
  echo "  $0                  # Interactive uninstall"
  echo "  $0 -q               # Quiet uninstall"
  echo "  $0 --keep_data      # Uninstall but keep data"
  echo
}

# Parse arguments
TEMP=$(getopt -o hq --long help,quiet,keep_data -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "Invalid options"; Show_Help; exit 1; }
eval set -- "${TEMP}"

quiet_mode=false
keep_data=false

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    -q|--quiet)
      quiet_mode=true
      shift
      ;;
    --keep_data)
      keep_data=true
      shift
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
  exit 0
fi

# Show what will be removed
Print_SeaTunnel

# Confirm uninstall
if [ "${quiet_mode}" != "true" ]; then
  while true; do
    read -e -p "Do you want to uninstall SeaTunnel? [y/n]: " uninstall_flag
    if [[ "${uninstall_flag}" =~ ^[Yy]$ ]]; then
      break
    elif [[ "${uninstall_flag}" =~ ^[Nn]$ ]]; then
      echo "${CMSG}Uninstall cancelled.${CEND}"
      exit 0
    else
      echo "${CWARNING}Please enter y or n${CEND}"
    fi
  done
fi

# Perform uninstall
Uninstall_SeaTunnel

popd > /dev/null
