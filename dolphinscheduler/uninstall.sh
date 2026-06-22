#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Uninstallation script
#
# Supports uninstalling: Standalone, Master, Worker, API, Alert

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear
printf "
#######################################################################
#    DolphinSchedulerStack - Apache DolphinScheduler Deployment Tool  #
#                     Uninstall DolphinScheduler                      #
#    For more information: https://dolphinscheduler.apache.org        #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

ds_dir=$(dirname "$(readlink -f $0)")
pushd ${ds_dir} > /dev/null
. ./options.conf
. ./include/color.sh
. ./include/check_os.sh
. ./include/dolphinscheduler.sh

Show_Help() {
  echo
  echo "Usage: $0 command ...[parameters]....
  --help, -h                  Show this help message
  --quiet, -q                 Quiet operation (no confirmation)
  --all                       Uninstall all components
  --standalone                Uninstall Standalone server only
  --master                    Uninstall Master server only
  --worker                    Uninstall Worker server only
  --api                       Uninstall API server only
  --alert                     Uninstall Alert server only
  "
}

ARG_NUM=$#
TEMP=$(getopt -o hq --long help,quiet,all,standalone,master,worker,api,alert -- "$@" 2>/dev/null)
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"

quiet_flag=n
all_flag=n
standalone_flag=n
master_flag=n
worker_flag=n
api_flag=n
alert_flag=n

while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    --all)
      all_flag=y; standalone_flag=y; master_flag=y; worker_flag=y; api_flag=y; alert_flag=y; shift 1
      ;;
    --standalone)
      standalone_flag=y; shift 1
      ;;
    --master)
      master_flag=y; shift 1
      ;;
    --worker)
      worker_flag=y; shift 1
      ;;
    --api)
      api_flag=y; shift 1
      ;;
    --alert)
      alert_flag=y; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

Print_Uninstall_Info() {
  echo ""
  echo "${CWARNING}WARNING: This will remove DolphinScheduler installation!${CEND}"
  echo ""

  if [ "${all_flag}" == "y" ] || [ "${standalone_flag}" == "y" ]; then
    if [ -f "/lib/systemd/system/dolphinscheduler-standalone.service" ]; then
      echo "  Will uninstall Standalone Server:"
      echo "    - /lib/systemd/system/dolphinscheduler-standalone.service"
    fi
  fi

  if [ "${all_flag}" == "y" ] || [ "${master_flag}" == "y" ]; then
    if [ -f "/lib/systemd/system/dolphinscheduler-master.service" ]; then
      echo "  Will uninstall Master Server:"
      echo "    - /lib/systemd/system/dolphinscheduler-master.service"
    fi
  fi

  if [ "${all_flag}" == "y" ] || [ "${worker_flag}" == "y" ]; then
    if [ -f "/lib/systemd/system/dolphinscheduler-worker.service" ]; then
      echo "  Will uninstall Worker Server:"
      echo "    - /lib/systemd/system/dolphinscheduler-worker.service"
    fi
  fi

  if [ "${all_flag}" == "y" ] || [ "${api_flag}" == "y" ]; then
    if [ -f "/lib/systemd/system/dolphinscheduler-api.service" ]; then
      echo "  Will uninstall API Server:"
      echo "    - /lib/systemd/system/dolphinscheduler-api.service"
    fi
  fi

  if [ "${all_flag}" == "y" ] || [ "${alert_flag}" == "y" ]; then
    if [ -f "/lib/systemd/system/dolphinscheduler-alert.service" ]; then
      echo "  Will uninstall Alert Server:"
      echo "    - /lib/systemd/system/dolphinscheduler-alert.service"
    fi
  fi

  if [ "${all_flag}" == "y" ]; then
    if [ -d "${dolphinscheduler_install_dir}" ]; then
      echo ""
      echo "  Will remove installation directory:"
      echo "    - ${dolphinscheduler_install_dir}"
    fi
    if [ -d "${dolphinscheduler_data_dir}" ]; then
      echo "  Will backup data directory:"
      echo "    - ${dolphinscheduler_data_dir} (will be renamed with timestamp)"
    fi
  fi
}

Confirm_Uninstall() {
  if [ "${quiet_flag}" != "y" ]; then
    Print_Uninstall_Info

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
      echo "Uninstall cancelled."
      exit 0
    fi
  fi
}

Menu() {
  while :; do
    printf "
What do you want to uninstall?
\t${CMSG}1${CEND}. Uninstall All
\t${CMSG}2${CEND}. Uninstall Standalone Server only
\t${CMSG}3${CEND}. Uninstall Master Server only
\t${CMSG}4${CEND}. Uninstall Worker Server only
\t${CMSG}5${CEND}. Uninstall API Server only
\t${CMSG}6${CEND}. Uninstall Alert Server only
\t${CMSG}q${CEND}. Exit
"
    echo
    read -e -p "Please input the correct option: " Number
    if [[ ! "${Number}" =~ ^[1-6,q]$ ]]; then
      echo "${CWARNING}input error! Please only input 1~6 or q${CEND}"
    else
      case "$Number" in
        1) all_flag=y; standalone_flag=y; master_flag=y; worker_flag=y; api_flag=y; alert_flag=y ;;
        2) standalone_flag=y ;;
        3) master_flag=y ;;
        4) worker_flag=y ;;
        5) api_flag=y ;;
        6) alert_flag=y ;;
        q) exit 0 ;;
      esac
      break
    fi
  done
}

Uninstall_Service() {
  local service_name=$1

  if [ -f "/lib/systemd/system/dolphinscheduler-${service_name}.service" ]; then
    echo "${CMSG}Uninstalling ${service_name} server...${CEND}"
    systemctl stop dolphinscheduler-${service_name} 2>/dev/null
    systemctl disable dolphinscheduler-${service_name} 2>/dev/null
    rm -f /lib/systemd/system/dolphinscheduler-${service_name}.service
    echo "${CSUCCESS}${service_name} server uninstalled.${CEND}"
  fi
}

# Main logic
if [ ${ARG_NUM} -eq 0 ]; then
  Menu
fi

Confirm_Uninstall

# Uninstall services
[ "${standalone_flag}" == "y" ] && Uninstall_Service "standalone"
[ "${master_flag}" == "y" ] && Uninstall_Service "master"
[ "${worker_flag}" == "y" ] && Uninstall_Service "worker"
[ "${api_flag}" == "y" ] && Uninstall_Service "api"
[ "${alert_flag}" == "y" ] && Uninstall_Service "alert"

systemctl daemon-reload

# If all services are uninstalled, remove directories
if [ "${all_flag}" == "y" ]; then
  # Backup data directory
  if [ -d "${dolphinscheduler_data_dir}" ]; then
    local backup_name="${dolphinscheduler_data_dir}_$(date +%Y%m%d%H%M%S)"
    echo "${CMSG}Backing up data directory to ${backup_name}...${CEND}"
    mv ${dolphinscheduler_data_dir} ${backup_name}
  fi

  # Remove installation directory
  if [ -d "${dolphinscheduler_install_dir}" ]; then
    rm -rf ${dolphinscheduler_install_dir}
    echo "${CSUCCESS}Removed ${dolphinscheduler_install_dir}${CEND}"
  fi

  # Remove log directory
  if [ -d "${dolphinscheduler_log_dir}" ]; then
    rm -rf ${dolphinscheduler_log_dir}
    echo "${CSUCCESS}Removed ${dolphinscheduler_log_dir}${CEND}"
  fi

  # Remove user if no services remain
  if ! ls /lib/systemd/system/dolphinscheduler-*.service > /dev/null 2>&1; then
    if id -u ${run_user} > /dev/null 2>&1; then
      userdel ${run_user} 2>/dev/null
      groupdel ${run_group} 2>/dev/null
      echo "${CSUCCESS}User ${run_user} and group ${run_group} removed.${CEND}"
    fi
  fi
fi

echo ""
echo "${CSUCCESS}Uninstall completed!${CEND}"

popd > /dev/null
