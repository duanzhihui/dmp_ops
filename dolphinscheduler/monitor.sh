#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Monitoring script
#
# Supports: Health check, Status report, Auto-recovery

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

ds_dir=$(dirname "$(readlink -f $0)")
pushd ${ds_dir} > /dev/null
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${ds_dir}"
. ./options.conf
. ./include/color.sh
. ./include/check_env.sh
. ./include/monitor_dolphinscheduler.sh
. ./include/cluster.sh

Show_Help() {
  echo
  echo "Usage: $0 command ...[parameters]....
  --help, -h                  Show this help message
  --status                    Show service status
  --check                     Run health check
  --loop [interval]           Continuous monitoring (default: 60s)
  --recovery                  Enable auto-recovery on failure

  In cluster mode, run this script on the control node (the one configured
  with 'ips' in options.conf). It will SSH into every node and report the
  health of the whole cluster from one place.
  "
}

ARG_NUM=$#
TEMP=$(getopt -o h --long help,status,check,loop:,recovery -- "$@" 2>/dev/null)
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"

status_flag=n
check_flag=n
loop_flag=n
loop_interval=60
recovery_flag=n

while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    --status)
      status_flag=y; shift 1
      ;;
    --check)
      check_flag=y; shift 1
      ;;
    --loop)
      loop_flag=y; loop_interval=$2; shift 2
      ;;
    --recovery)
      recovery_flag=y; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

# Show status
Show_Status() {
  echo ""
  echo "${CMSG}========== DolphinScheduler Service Status ==========${CEND}"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # Check standalone-server
  if [ -f "/lib/systemd/system/dolphinscheduler-standalone.service" ]; then
    local status=$(systemctl is-active dolphinscheduler-standalone 2>/dev/null)
    if [ "${status}" == "active" ]; then
      echo "${CSUCCESS}[RUNNING]${CEND} Standalone Server"
      echo "  Web UI: http://localhost:${web_port}/dolphinscheduler/ui"
    else
      echo "${CFAILURE}[STOPPED]${CEND} Standalone Server"
    fi
  fi

  # Check master-server
  if [ -f "/lib/systemd/system/dolphinscheduler-master.service" ]; then
    local status=$(systemctl is-active dolphinscheduler-master 2>/dev/null)
    if [ "${status}" == "active" ]; then
      echo "${CSUCCESS}[RUNNING]${CEND} Master Server"
    else
      echo "${CFAILURE}[STOPPED]${CEND} Master Server"
    fi
  fi

  # Check worker-server
  if [ -f "/lib/systemd/system/dolphinscheduler-worker.service" ]; then
    local status=$(systemctl is-active dolphinscheduler-worker 2>/dev/null)
    if [ "${status}" == "active" ]; then
      echo "${CSUCCESS}[RUNNING]${CEND} Worker Server"
    else
      echo "${CFAILURE}[STOPPED]${CEND} Worker Server"
    fi
  fi

  # Check api-server
  if [ -f "/lib/systemd/system/dolphinscheduler-api.service" ]; then
    local status=$(systemctl is-active dolphinscheduler-api 2>/dev/null)
    if [ "${status}" == "active" ]; then
      echo "${CSUCCESS}[RUNNING]${CEND} API Server"
      echo "  Web UI: http://localhost:${api_port}/dolphinscheduler/ui"
    else
      echo "${CFAILURE}[STOPPED]${CEND} API Server"
    fi
  fi

  # Check alert-server
  if [ -f "/lib/systemd/system/dolphinscheduler-alert.service" ]; then
    local status=$(systemctl is-active dolphinscheduler-alert 2>/dev/null)
    if [ "${status}" == "active" ]; then
      echo "${CSUCCESS}[RUNNING]${CEND} Alert Server"
    else
      echo "${CFAILURE}[STOPPED]${CEND} Alert Server"
    fi
  fi

  echo ""
}

# Run health check with optional auto-recovery
Run_Health_Check() {
  local has_error=0

  Monitor_DolphinScheduler_Status
  has_error=$?

  if [ ${has_error} -ne 0 ] && [ "${recovery_flag}" == "y" ]; then
    echo ""
    echo "${CMSG}Attempting auto-recovery...${CEND}"

    # Check and recover each service
    for service in standalone master worker api alert; do
      if [ -f "/lib/systemd/system/dolphinscheduler-${service}.service" ]; then
        if ! systemctl is-active --quiet dolphinscheduler-${service}; then
          Auto_Recovery "${service}"
        fi
      fi
    done
  fi

  return ${has_error}
}

# Main logic
Main() {
  # Initialize local_ip (used by Is_Local_Node in cluster mode)
  Detect_Network > /dev/null

  local is_cluster=n
  [ "${deploy_mode}" == "cluster" ] && is_cluster=y

  if [ "${status_flag}" == "y" ]; then
    if [ "${is_cluster}" == "y" ]; then
      Show_Cluster_Status_Monitor
    else
      Show_Status
    fi
    exit 0
  fi

  if [ "${loop_flag}" == "y" ]; then
    if [ "${is_cluster}" == "y" ]; then
      Monitor_Cluster_Loop ${loop_interval}
    else
      Monitor_Loop ${loop_interval}
    fi
    exit 0
  fi

  if [ "${check_flag}" == "y" ]; then
    if [ "${is_cluster}" == "y" ]; then
      Run_Cluster_Health_Check
    else
      Run_Health_Check
    fi
    exit $?
  fi

  # Default: show status
  if [ "${is_cluster}" == "y" ]; then
    Show_Cluster_Status_Monitor
  else
    Show_Status
  fi
}

Main
popd > /dev/null
