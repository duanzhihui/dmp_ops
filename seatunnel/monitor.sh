#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Monitor Script
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# Get script directory
seatunnel_dir=$(dirname $(readlink -f $0))
pushd ${seatunnel_dir} > /dev/null

# Source configuration and modules
. ./options.conf
. ./versions.txt
. ./include/color.sh
. ./include/check_os.sh
. ./include/monitor_seatunnel.sh

# Help message
Show_Help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -h, --help       Show this help message"
  echo "  --status         Show status report"
  echo "  --check          Run health checks"
  echo "  --jobs           Show running jobs"
  echo "  --cluster        Show cluster status"
  echo "  --auto-recover   Enable auto-recovery on failure"
  echo
  echo "Examples:"
  echo "  $0 --status      # Show full status report"
  echo "  $0 --check       # Run health checks"
  echo "  $0 --jobs        # List running jobs"
  echo
}

# Parse arguments
TEMP=$(getopt -o h --long help,status,check,jobs,cluster,auto-recover -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "Invalid options"; Show_Help; exit 1; }
eval set -- "${TEMP}"

action=""
auto_recover=false

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    --status)
      action="status"
      shift
      ;;
    --check)
      action="check"
      shift
      ;;
    --jobs)
      action="jobs"
      shift
      ;;
    --cluster)
      action="cluster"
      shift
      ;;
    --auto-recover)
      auto_recover=true
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

# Default action
if [ -z "${action}" ]; then
  action="status"
fi

# Check if SeaTunnel is installed
if [ ! -e "${seatunnel_install_dir}/bin/seatunnel.sh" ]; then
  echo "${CWARNING}SeaTunnel is not installed!${CEND}"
  exit 1
fi

# Execute action
case "${action}" in
  status)
    Monitor_Status
    ;;
  check)
    Monitor_Check
    ;;
  jobs)
    echo "${CMSG}Running Jobs:${CEND}"
    Check_Running_Jobs
    ;;
  cluster)
    echo "${CMSG}Cluster Status:${CEND}"
    Check_Cluster_Health
    ;;
esac

popd > /dev/null
