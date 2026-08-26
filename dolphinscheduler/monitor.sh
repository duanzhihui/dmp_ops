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
  --start                     Start all DolphinScheduler services
                              (role order: master -> worker -> api -> alert;
                              a role is only started after every node of the
                              previous role is active)
  --stop                      Stop all DolphinScheduler services
                              (reverse order: alert -> api -> worker -> master)

  In cluster mode, run this script on the control node (the one configured
  with 'ips' in options.conf). It will SSH into every node and report the
  health of the whole cluster from one place.
  "
}

ARG_NUM=$#
TEMP=$(getopt -o h --long help,status,check,loop:,recovery,start,stop -- "$@" 2>/dev/null)
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"

status_flag=n
check_flag=n
loop_flag=n
loop_interval=60
recovery_flag=n
start_flag=n
stop_flag=n

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
    --start)
      start_flag=y; shift 1
      ;;
    --stop)
      stop_flag=y; shift 1
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

# Return the comma separated list of nodes (from ${ips}) that carry ${1} role.
# Workers entries may use the "ip:group" form; only the ip part is compared.
Nodes_With_Role() {
  local role=$1
  local ips_array=(${ips//,/ })
  local ip result=""
  for ip in "${ips_array[@]}"; do
    local roles=$(Get_Node_Roles "${ip}")
    local r
    for r in ${roles//,/ }; do
      [ "${r}" == "${role}" ] && result="${result} ${ip}" && break
    done
  done
  echo "${result# }"
}

# Check that every node listed in ${1} (space separated) has the ${2} role
# service active. Returns 0 only if all are active.
Role_All_Active() {
  local role=$1; shift
  local ip status
  for ip in "$@"; do
    if Is_Local_Node "${ip}"; then
      status=$(systemctl is-active dolphinscheduler-${role} 2>/dev/null)
    else
      Build_SSH_Opts
      status=$(ssh -o BatchMode=yes ${ssh_opts} "$(Remote_Target ${ip})" \
        "systemctl is-active dolphinscheduler-${role}" 2>/dev/null)
    fi
    [ "${status}" != "active" ] && return 1
  done
  return 0
}

# Start a single role on every node that owns it.
# ${1} = role, ${2}.. = nodes (space separated)
Start_Role_On_Nodes() {
  local role=$1; shift
  local nodes="$@"
  [ -z "${nodes}" ] && return 0

  local ip has_error=0
  for ip in ${nodes}; do
    echo "${CMSG}  starting ${role}-server on ${ip}...${CEND}"
    Systemctl_On_Node "${ip}" "${role}" start || has_error=1
  done

  # Give systemd a moment to settle before we probe is-active
  sleep 5

  if Role_All_Active "${role}" ${nodes}; then
    echo "${CSUCCESS}  ${role}-server active on all nodes (${nodes})${CEND}"
    return 0
  fi

  # Report which node failed
  for ip in ${nodes}; do
    if Is_Local_Node "${ip}"; then
      status=$(systemctl is-active dolphinscheduler-${role} 2>/dev/null)
    else
      Build_SSH_Opts
      status=$(ssh -o BatchMode=yes ${ssh_opts} "$(Remote_Target ${ip})" \
        "systemctl is-active dolphinscheduler-${role}" 2>/dev/null)
    fi
    if [ "${status}" != "active" ]; then
      echo "${CFAILURE}  ${role}-server on ${ip} is ${status:-inactive}${CEND}"
      if Is_Local_Node "${ip}"; then
        journalctl -u dolphinscheduler-${role} --no-pager -n 20 2>/dev/null
      else
        ssh -o BatchMode=yes ${ssh_opts} "$(Remote_Target ${ip})" \
          "journalctl -u dolphinscheduler-${role} --no-pager -n 20 2>/dev/null"
      fi
    fi
  done
  return 1
}

# Stop a single role on every node that owns it.
# ${1} = role, ${2}.. = nodes (space separated)
Stop_Role_On_Nodes() {
  local role=$1; shift
  local nodes="$@"
  [ -z "${nodes}" ] && return 0

  local ip
  for ip in ${nodes}; do
    echo "${CMSG}  stopping ${role}-server on ${ip}...${CEND}"
    Systemctl_On_Node "${ip}" "${role}" stop 2>/dev/null
  done
  return 0
}

# Start all DolphinScheduler services respecting role dependencies.
# Order: master -> worker -> api -> alert.
# A role is only started after every node of the previous role is active.
Start_DS() {
  echo ""
  echo "${CMSG}========== Starting DolphinScheduler ==========${CEND}"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # --- Standalone mode: single unit ---
  if [ "${deploy_mode}" == "standalone" ]; then
    if [ ! -f "/lib/systemd/system/dolphinscheduler-standalone.service" ]; then
      echo "${CFAILURE}Standalone service unit not found; is DolphinScheduler installed?${CEND}"
      return 1
    fi
    systemctl start dolphinscheduler-standalone
    sleep 5
    if systemctl is-active --quiet dolphinscheduler-standalone; then
      echo "${CSUCCESS}Standalone Server started${CEND}"
      echo "  Web UI: http://localhost:${web_port}/dolphinscheduler/ui"
      return 0
    fi
    echo "${CFAILURE}Failed to start Standalone Server${CEND}"
    journalctl -u dolphinscheduler-standalone --no-pager -n 20
    return 1
  fi

  # --- Pseudo-cluster / cluster: role-ordered start with dependency check ---
  local masters_nodes  workers_nodes  api_nodes  alert_nodes
  masters_nodes=$(Nodes_With_Role master)
  workers_nodes=$(Nodes_With_Role worker)
  api_nodes=$(Nodes_With_Role api)
  alert_nodes=$(Nodes_With_Role alert)

  if [ -z "${masters_nodes}" ]; then
    echo "${CFAILURE}No master node found in options.conf; cannot start cluster${CEND}"
    return 1
  fi

  echo "${CMSG}Nodes -> master:[${masters_nodes:-none}] worker:[${workers_nodes:-none}] api:[${api_nodes:-none}] alert:[${alert_nodes:-none}]${CEND}"
  echo ""

  # 1) Master
  echo "${CMSG}[1/4] Starting master-server (master is required by all other roles)...${CEND}"
  Start_Role_On_Nodes master ${masters_nodes} || {
    echo "${CFAILURE}master-server did not become active on every node; aborting start to keep cluster consistent${CEND}"
    return 1
  }

  # 2) Worker (depends on master being up)
  echo ""
  echo "${CMSG}[2/4] Starting worker-server (requires master)...${CEND}"
  Start_Role_On_Nodes worker ${workers_nodes} || {
    echo "${CWARNING}worker-server failed on some nodes; continuing with api/alert start${CEND}"
  }

  # 3) API (depends on master)
  echo ""
  echo "${CMSG}[3/4] Starting api-server (requires master)...${CEND}"
  Start_Role_On_Nodes api ${api_nodes} || {
    echo "${CWARNING}api-server failed on some nodes; continuing with alert start${CEND}"
  }

  # 4) Alert (independent, started last)
  echo ""
  echo "${CMSG}[4/4] Starting alert-server...${CEND}"
  Start_Role_On_Nodes alert ${alert_nodes} || {
    echo "${CWARNING}alert-server failed on some nodes${CEND}"
  }

  echo ""
  echo "${CMSG}---------- start summary ----------${CEND}"
  local ok=1
  Role_All_Active master  ${masters_nodes}  || { echo "${CFAILURE}master:  NOT all active${CEND}";  ok=0; }
  [ -n "${workers_nodes}" ] && { Role_All_Active worker ${workers_nodes} || { echo "${CFAILURE}worker:  NOT all active${CEND}"; ok=0; } }
  [ -n "${api_nodes}" ]     && { Role_All_Active api     ${api_nodes}     || { echo "${CFAILURE}api:     NOT all active${CEND}"; ok=0; } }
  [ -n "${alert_nodes}" ]   && { Role_All_Active alert   ${alert_nodes}   || { echo "${CFAILURE}alert:   NOT all active${CEND}"; ok=0; } }
  if [ ${ok} -eq 1 ]; then
    echo "${CSUCCESS}DolphinScheduler cluster started${CEND}"
  else
    echo "${CFAILURE}Some services failed to start; see details above${CEND}"
  fi
  return $((1 - ok))
}

# Stop all DolphinScheduler services in reverse dependency order.
# Order: alert -> api -> worker -> master.
Stop_DS() {
  echo ""
  echo "${CMSG}========== Stopping DolphinScheduler ==========${CEND}"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # --- Standalone mode ---
  if [ "${deploy_mode}" == "standalone" ]; then
    systemctl stop dolphinscheduler-standalone 2>/dev/null
    sleep 2
    if systemctl is-active --quiet dolphinscheduler-standalone; then
      echo "${CFAILURE}Failed to stop Standalone Server${CEND}"
      return 1
    fi
    echo "${CSUCCESS}Standalone Server stopped${CEND}"
    return 0
  fi

  # --- Pseudo-cluster / cluster: reverse role order ---
  local alert_nodes  api_nodes  workers_nodes  masters_nodes
  alert_nodes=$(Nodes_With_Role alert)
  api_nodes=$(Nodes_With_Role api)
  workers_nodes=$(Nodes_With_Role worker)
  masters_nodes=$(Nodes_With_Role master)

  echo "${CMSG}Stopping in reverse dependency order: alert -> api -> worker -> master${CEND}"
  echo ""

  echo "${CMSG}[1/4] Stopping alert-server...${CEND}"
  Stop_Role_On_Nodes alert ${alert_nodes}

  echo ""
  echo "${CMSG}[2/4] Stopping api-server...${CEND}"
  Stop_Role_On_Nodes api ${api_nodes}

  echo ""
  echo "${CMSG}[3/4] Stopping worker-server...${CEND}"
  Stop_Role_On_Nodes worker ${workers_nodes}

  echo ""
  echo "${CMSG}[4/4] Stopping master-server...${CEND}"
  Stop_Role_On_Nodes master ${masters_nodes}

  echo ""
  echo "${CSUCCESS}DolphinScheduler cluster stopped${CEND}"
  return 0
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

  if [ "${start_flag}" == "y" ]; then
    Start_DS
    exit $?
  fi

  if [ "${stop_flag}" == "y" ]; then
    Stop_DS
    exit $?
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
