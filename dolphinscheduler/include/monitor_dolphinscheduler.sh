#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Monitoring and health check functions

# Check DolphinScheduler process
Check_DolphinScheduler_Process() {
  local service_name=$1
  local process_pattern=$2

  if pgrep -f "${process_pattern}" > /dev/null 2>&1; then
    echo "${CSUCCESS}[OK]${CEND} ${service_name} process is running"
    return 0
  else
    echo "${CFAILURE}[FAIL]${CEND} ${service_name} process is NOT running"
    return 1
  fi
}

# Check DolphinScheduler port
Check_DolphinScheduler_Port() {
  local service_name=$1
  local port=$2

  if ss -tlnp | grep -q ":${port} "; then
    echo "${CSUCCESS}[OK]${CEND} ${service_name} port ${port} is listening"
    return 0
  else
    echo "${CFAILURE}[FAIL]${CEND} ${service_name} port ${port} is NOT listening"
    return 1
  fi
}

# Check database connection
Check_DolphinScheduler_DB() {
  echo "${CMSG}Checking database connection...${CEND}"

  if [ "${db_type}" == "mysql" ]; then
    if command -v mysql > /dev/null 2>&1; then
      if mysql -h${db_host} -P${db_port} -u${db_user} -p"${db_password}" -e "SELECT 1 FROM ${db_name}.t_ds_version LIMIT 1" > /dev/null 2>&1; then
        echo "${CSUCCESS}[OK]${CEND} MySQL database connection successful"
        return 0
      else
        echo "${CFAILURE}[FAIL]${CEND} MySQL database connection failed"
        return 1
      fi
    else
      echo "${CWARNING}[SKIP]${CEND} MySQL client not installed"
      return 0
    fi
  elif [ "${db_type}" == "postgresql" ]; then
    if command -v psql > /dev/null 2>&1; then
      if PGPASSWORD="${db_password}" psql -h ${db_host} -p ${db_port} -U ${db_user} -d ${db_name} -c "SELECT 1 FROM t_ds_version LIMIT 1" > /dev/null 2>&1; then
        echo "${CSUCCESS}[OK]${CEND} PostgreSQL database connection successful"
        return 0
      else
        echo "${CFAILURE}[FAIL]${CEND} PostgreSQL database connection failed"
        return 1
      fi
    else
      echo "${CWARNING}[SKIP]${CEND} PostgreSQL client not installed"
      return 0
    fi
  fi
}

# Check ZooKeeper connection
Check_DolphinScheduler_ZK() {
  local zk_host=${zk_hosts%%:*}
  local zk_port=${zk_hosts##*:}

  echo "${CMSG}Checking ZooKeeper connection (${zk_hosts})...${CEND}"

  if command -v nc > /dev/null 2>&1; then
    if echo "ruok" | nc -w 2 ${zk_host} ${zk_port} 2>/dev/null | grep -q "imok"; then
      echo "${CSUCCESS}[OK]${CEND} ZooKeeper connection successful"
      return 0
    fi
  fi

  if (echo > /dev/tcp/${zk_host}/${zk_port}) 2>/dev/null; then
    echo "${CSUCCESS}[OK]${CEND} ZooKeeper port ${zk_port} is reachable"
    return 0
  fi

  echo "${CFAILURE}[FAIL]${CEND} ZooKeeper connection failed"
  return 1
}

# Check HTTP health
Check_DolphinScheduler_HTTP() {
  local url=$1
  local expected_code=${2:-200}

  echo "${CMSG}Checking HTTP health: ${url}${CEND}"

  local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "${url}" 2>/dev/null)

  if [ "${http_code}" == "${expected_code}" ]; then
    echo "${CSUCCESS}[OK]${CEND} HTTP check passed (${http_code})"
    return 0
  else
    echo "${CFAILURE}[FAIL]${CEND} HTTP check failed (${http_code})"
    return 1
  fi
}

# Check disk space
Check_Disk_Space() {
  local threshold=${1:-85}
  local has_warning=0

  echo "${CMSG}Checking disk space (threshold: ${threshold}%)...${CEND}"

  while read line; do
    local usage=$(echo ${line} | awk '{print $5}' | tr -d '%')
    local mount=$(echo ${line} | awk '{print $6}')

    if [ ${usage} -ge ${threshold} ]; then
      echo "${CWARNING}[WARN]${CEND} Disk usage high: ${mount} (${usage}%)"
      has_warning=1
    fi
  done < <(df -h | awk 'NR>1 && $5 ~ /%/')

  if [ ${has_warning} -eq 0 ]; then
    echo "${CSUCCESS}[OK]${CEND} Disk space is sufficient"
  fi

  return ${has_warning}
}

# Monitor DolphinScheduler status
Monitor_DolphinScheduler_Status() {
  echo ""
  echo "${CMSG}========== DolphinScheduler Health Check ==========${CEND}"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  local has_error=0

  # Check standalone mode
  if [ -f "/lib/systemd/system/dolphinscheduler-standalone.service" ]; then
    echo "${CMSG}--- Standalone Mode ---${CEND}"
    Check_DolphinScheduler_Process "Standalone Server" "StandaloneServer" || has_error=1
    Check_DolphinScheduler_Port "Web UI" ${web_port} || has_error=1
    Check_DolphinScheduler_HTTP "http://localhost:${web_port}/dolphinscheduler/ui" || has_error=1
  fi

  # Check pseudo-cluster/cluster mode: only the roles installed on this node
  local cluster_units=$(ls /lib/systemd/system/dolphinscheduler-*.service 2>/dev/null | grep -v 'standalone')
  if [ -n "${cluster_units}" ]; then
    echo "${CMSG}--- Cluster Mode ---${CEND}"

    # Master Server
    if [ -f "/lib/systemd/system/dolphinscheduler-master.service" ]; then
      Check_DolphinScheduler_Process "Master Server" "MasterServer" || has_error=1
      Check_DolphinScheduler_Port "Master Server" ${master_rpc_port} || has_error=1
    fi

    # Worker Server
    if [ -f "/lib/systemd/system/dolphinscheduler-worker.service" ]; then
      Check_DolphinScheduler_Process "Worker Server" "WorkerServer" || has_error=1
      Check_DolphinScheduler_Port "Worker Server" ${worker_rpc_port} || has_error=1
    fi

    # API Server
    if [ -f "/lib/systemd/system/dolphinscheduler-api.service" ]; then
      Check_DolphinScheduler_Process "API Server" "ApiApplicationServer" || has_error=1
      Check_DolphinScheduler_Port "API Server" ${api_port} || has_error=1
      Check_DolphinScheduler_HTTP "http://localhost:${api_port}/dolphinscheduler/ui" || has_error=1
    fi

    # Alert Server
    if [ -f "/lib/systemd/system/dolphinscheduler-alert.service" ]; then
      Check_DolphinScheduler_Process "Alert Server" "AlertServer" || has_error=1
      Check_DolphinScheduler_Port "Alert Server" ${alert_rpc_port} || has_error=1
    fi

    # ZooKeeper
    Check_DolphinScheduler_ZK || has_error=1

    # Database
    Check_DolphinScheduler_DB || has_error=1
  fi

  echo ""
  echo "${CMSG}--- System Resources ---${CEND}"
  Check_Disk_Space 85

  echo ""
  if [ ${has_error} -eq 0 ]; then
    echo "${CSUCCESS}========== All checks passed! ==========${CEND}"
  else
    echo "${CFAILURE}========== Some checks failed! ==========${CEND}"
  fi
  echo ""

  return ${has_error}
}

# Send alert notification
Send_Alert() {
  local message=$1
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local hostname=$(hostname)

  # Log to file
  local log_file="${dolphinscheduler_log_dir:-/var/log}/monitor.log"
  echo "[${timestamp}] ALERT: ${message}" >> ${log_file}

  # Email notification
  if [ -n "${alert_email}" ]; then
    echo "${message}" | mail -s "[DolphinScheduler Alert] ${hostname}" ${alert_email}
  fi

  # Webhook notification (DingTalk/Feishu/Slack/etc.)
  if [ -n "${webhook_url}" ]; then
    curl -s -X POST "${webhook_url}" \
      -H 'Content-Type: application/json' \
      -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"[${hostname}] ${timestamp} ${message}\"}}" \
      > /dev/null 2>&1
  fi
}

# Auto-recovery function
Auto_Recovery() {
  local service_name=$1

  echo "${CMSG}Attempting auto-recovery for ${service_name}...${CEND}"

  case "${service_name}" in
    standalone)
      systemctl restart dolphinscheduler-standalone
      ;;
    master)
      systemctl restart dolphinscheduler-master
      ;;
    worker)
      systemctl restart dolphinscheduler-worker
      ;;
    api)
      systemctl restart dolphinscheduler-api
      ;;
    alert)
      systemctl restart dolphinscheduler-alert
      ;;
  esac

  sleep 5

  if systemctl is-active --quiet dolphinscheduler-${service_name}; then
    echo "${CSUCCESS}${service_name} recovered successfully!${CEND}"
    Send_Alert "${service_name} was down, auto-recovered"
    return 0
  else
    echo "${CFAILURE}${service_name} recovery failed!${CEND}"
    Send_Alert "${service_name} is DOWN and auto-recovery FAILED"
    return 1
  fi
}

# Continuous monitoring loop
Monitor_Loop() {
  local interval=${1:-60}

  echo "${CMSG}Starting continuous monitoring (interval: ${interval}s)...${CEND}"
  echo "Press Ctrl+C to stop."

  while true; do
    Monitor_DolphinScheduler_Status
    local rc=$?
    if [ ${rc} -ne 0 ]; then
      Send_Alert "single-node health check failed (rc=${rc})"
      if [ "${recovery_flag:-n}" == "y" ]; then
        for service in standalone master worker api alert; do
          if [ -f "/lib/systemd/system/dolphinscheduler-${service}.service" ]; then
            if ! systemctl is-active --quiet dolphinscheduler-${service}; then
              Auto_Recovery "${service}"
            fi
          fi
        done
      fi
    fi
    sleep ${interval}
  done
}

#########################################################################
# Cluster-level monitoring functions
#
# These run on the control node and SSH into every node listed in 'ips' to
# check the health of the whole cluster from one place. They rely on the
# helpers in include/cluster.sh (Build_SSH_Opts, Remote_Target, Remote_Cmd,
# Is_Local_Node, Get_Node_Roles, Systemctl_On_Node).
#########################################################################

# Map a role to the pgrep process pattern used by DolphinScheduler
_Role_Process_Pattern() {
  case "$1" in
    master) echo "MasterServer" ;;
    worker) echo "WorkerServer" ;;
    api)    echo "ApiApplicationServer" ;;
    alert)  echo "AlertServer" ;;
    standalone) echo "StandaloneServer" ;;
  esac
}

# Map a role to its RPC port (used for the port-listening check)
_Role_Rpc_Port() {
  case "$1" in
    master) echo "${master_rpc_port}" ;;
    worker) echo "${worker_rpc_port}" ;;
    api)    echo "${api_port}" ;;
    alert)  echo "${alert_rpc_port}" ;;
    standalone) echo "${web_port}" ;;
  esac
}

# Check a single role on a single node.
# $1 = ip, $2 = role
# Returns 0 if healthy, non-zero if any check fails.
#
# NOTE: the remote check relies on an inline heredoc sent over SSH. This works
# when ssh_user is root (the default and the only user that can bootstrap a
# node, per AGENTS.md). For non-root ssh_user, Remote_Cmd wraps the command in
# `sudo -n bash -c '...'` whose single quotes would clash with the quotes
# inside the heredoc; if you need non-root monitoring, file an issue.
Check_Node_Health_Remote() {
  local ip=$1
  local role=$2
  local pattern=$(_Role_Process_Pattern "${role}")
  local port=$(_Role_Rpc_Port "${role}")
  local node_err=0

  echo "${CMSG}  [${role}] on ${ip}${CEND}"

  if Is_Local_Node "${ip}"; then
    # Local node: reuse the existing single-node checkers.
    Check_DolphinScheduler_Process "${role}-server (${ip})" "${pattern}" || node_err=1
    Check_DolphinScheduler_Port "${role}-server (${ip})" "${port}" || node_err=1
    if [ "${role}" == "api" ]; then
      Check_DolphinScheduler_HTTP "http://localhost:${api_port}/dolphinscheduler/ui" || node_err=1
    elif [ "${role}" == "standalone" ]; then
      Check_DolphinScheduler_HTTP "http://localhost:${web_port}/dolphinscheduler/ui" || node_err=1
    fi
    return ${node_err}
  fi

  # Remote node: run an inline script over SSH and parse its output.
  Build_SSH_Opts
  local target=$(Remote_Target "${ip}")

  # The inline script prints one tagged line per check so the control node
  # can render coloured output consistently. Disk usage is reported inline.
  local remote_script
  remote_script=$(cat <<REMOTE_EOF
proc=FAIL; pgrep -f '${pattern}' >/dev/null 2>&1 && proc=OK
port=FAIL; ss -tlnp 2>/dev/null | grep -q ':${port} ' && port=OK
http=SKIP
if [ '${role}' = 'api' ] || [ '${role}' = 'standalone' ]; then
  hp=\$([ '${role}' = 'api' ] && echo '${api_port}' || echo '${web_port}')
  code=\$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "http://localhost:\${hp}/dolphinscheduler/ui" 2>/dev/null)
  [ "\${code}" = "200" ] && http=OK || http=FAIL
fi
disk=""
while read line; do
  u=\$(echo \$line | awk '{print \$5}' | tr -d '%')
  m=\$(echo \$line | awk '{print \$6}')
  [ \${u:-0} -ge 85 ] && disk="\${disk} \${m}(\${u}%)"
done < <(df -h 2>/dev/null | awk 'NR>1 && \$5 ~ /%/')
echo "PROC=\$proc"
echo "PORT=\$port"
echo "HTTP=\$http"
echo "DISK=\${disk}"
REMOTE_EOF
)

  local out
  out=$(ssh -o BatchMode=yes ${ssh_opts} "${target}" "$(Remote_Cmd "${remote_script}")" 2>/dev/null)
  local ssh_rc=$?

  if [ ${ssh_rc} -ne 0 ] || [ -z "${out}" ]; then
    echo "${CFAILURE}    [FAIL]${CEND} node ${ip} unreachable via SSH"
    return 1
  fi

  local proc_status port_status http_status disk_info
  proc_status=$(echo "${out}" | awk -F= '/^PROC=/{print $2}')
  port_status=$(echo "${out}" | awk -F= '/^PORT=/{print $2}')
  http_status=$(echo "${out}" | awk -F= '/^HTTP=/{print $2}')
  disk_info=$(echo "${out}" | awk -F= '/^DISK=/{print $2}')

  if [ "${proc_status}" == "OK" ]; then
    echo "${CSUCCESS}    [OK]${CEND} process running"
  else
    echo "${CFAILURE}    [FAIL]${CEND} process NOT running"
    node_err=1
  fi

  if [ "${port_status}" == "OK" ]; then
    echo "${CSUCCESS}    [OK]${CEND} port ${port} listening"
  else
    echo "${CFAILURE}    [FAIL]${CEND} port ${port} NOT listening"
    node_err=1
  fi

  if [ "${http_status}" == "OK" ]; then
    echo "${CSUCCESS}    [OK]${CEND} HTTP health passed"
  elif [ "${http_status}" == "FAIL" ]; then
    echo "${CFAILURE}    [FAIL]${CEND} HTTP health failed"
    node_err=1
  fi

  if [ -n "${disk_info}" ]; then
    echo "${CWARNING}    [WARN]${CEND} disk high:${disk_info}"
  fi

  return ${node_err}
}

# Cluster-wide status overview (used by --status).
# Reuses the per-role active/inactive logic from Show_Cluster_Status_Full
# but adds a summary line.
Show_Cluster_Status_Monitor() {
  echo ""
  echo "${CMSG}========== DolphinScheduler Cluster Status ==========${CEND}"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  Build_SSH_Opts

  local ips_array=(${ips//,/ })
  local ip roles role status
  local total=0 running=0 failed=0 unknown=0

  for ip in "${ips_array[@]}"; do
    roles=$(Get_Node_Roles "${ip}")
    echo "${CMSG}Node: ${ip} (${roles:-no role})${CEND}"

    for role in ${roles//,/ }; do
      total=$((total + 1))
      if Is_Local_Node "${ip}"; then
        status=$(systemctl is-active dolphinscheduler-${role} 2>/dev/null)
      else
        status=$(ssh -o BatchMode=yes ${ssh_opts} "$(Remote_Target ${ip})" \
          "systemctl is-active dolphinscheduler-${role}" 2>/dev/null)
      fi

      if [ "${status}" == "active" ]; then
        echo "  ${CSUCCESS}[RUNNING]${CEND} ${role}-server"
        running=$((running + 1))
      elif [ -z "${status}" ]; then
        echo "  ${CWARNING}[UNKNOWN]${CEND} ${role}-server (node unreachable)"
        unknown=$((unknown + 1))
      else
        echo "  ${CFAILURE}[${status}]${CEND} ${role}-server"
        failed=$((failed + 1))
      fi
    done
    echo ""
  done

  echo "${CMSG}Summary: ${total} role-instance(s) — ${CSUCCESS}${running} running${CEND}, ${CFAILURE}${failed} failed${CEND}, ${CWARNING}${unknown} unknown${CEND}"
  echo ""
}

# Cluster-wide health check (used by --check).
# Returns non-zero if any check fails.
Monitor_Cluster_Status() {
  echo ""
  echo "${CMSG}========== DolphinScheduler Cluster Health Check ==========${CEND}"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  local has_error=0
  local ips_array=(${ips//,/ })
  local ip roles role

  for ip in "${ips_array[@]}"; do
    roles=$(Get_Node_Roles "${ip}")
    if [ -z "${roles}" ]; then
      echo "${CWARNING}Node ${ip} has no role assigned, skipping.${CEND}"
      continue
    fi
    echo "${CMSG}--- Node ${ip} (roles: ${roles}) ---${CEND}"
    for role in ${roles//,/ }; do
      Check_Node_Health_Remote "${ip}" "${role}" || has_error=1
    done
    echo ""
  done

  # Shared components: check once from the control node.
  echo "${CMSG}--- Shared Components ---${CEND}"
  Check_DolphinScheduler_ZK || has_error=1
  Check_DolphinScheduler_DB || has_error=1

  # Control node disk (remote node disks are checked per-node above).
  echo ""
  echo "${CMSG}--- Control Node Resources ---${CEND}"
  Check_Disk_Space 85 || true

  echo ""
  if [ ${has_error} -eq 0 ]; then
    echo "${CSUCCESS}========== All cluster checks passed! ==========${CEND}"
  else
    echo "${CFAILURE}========== Some cluster checks failed! ==========${CEND}"
  fi
  echo ""

  return ${has_error}
}

# Cluster health check entry point with optional auto-recovery.
Run_Cluster_Health_Check() {
  Monitor_Cluster_Status
  local has_error=$?

  if [ ${has_error} -ne 0 ] && [ "${recovery_flag}" == "y" ]; then
    echo ""
    echo "${CMSG}Attempting cluster auto-recovery...${CEND}"
    Auto_Recovery_Cluster
    has_error=$?
  fi

  return ${has_error}
}

# Cluster-level auto-recovery: restart any inactive role service on every node.
# Returns 0 if all services ended up active, non-zero otherwise.
Auto_Recovery_Cluster() {
  local ips_array=(${ips//,/ })
  local ip roles role status rc has_error=0

  for ip in "${ips_array[@]}"; do
    roles=$(Get_Node_Roles "${ip}")
    [ -z "${roles}" ] && continue

    for role in ${roles//,/ }; do
      if Is_Local_Node "${ip}"; then
        status=$(systemctl is-active dolphinscheduler-${role} 2>/dev/null)
      else
        Build_SSH_Opts
        status=$(ssh -o BatchMode=yes ${ssh_opts} "$(Remote_Target ${ip})" \
          "systemctl is-active dolphinscheduler-${role}" 2>/dev/null)
      fi

      if [ "${status}" != "active" ]; then
        echo "${CMSG}Restarting ${role}-server on ${ip}...${CEND}"
        Systemctl_On_Node "${ip}" "${role}" restart
        sleep 5

        if Is_Local_Node "${ip}"; then
          status=$(systemctl is-active dolphinscheduler-${role} 2>/dev/null)
        else
          status=$(ssh -o BatchMode=yes ${ssh_opts} "$(Remote_Target ${ip})" \
            "systemctl is-active dolphinscheduler-${role}" 2>/dev/null)
        fi

        if [ "${status}" == "active" ]; then
          echo "${CSUCCESS}${role}-server on ${ip} recovered${CEND}"
          Send_Alert "${role}-server on ${ip} was down, auto-recovered"
        else
          echo "${CFAILURE}${role}-server on ${ip} recovery FAILED${CEND}"
          Send_Alert "${role}-server on ${ip} is DOWN and auto-recovery FAILED"
          has_error=1
        fi
      fi
    done
  done

  return ${has_error}
}

# Cluster continuous monitoring loop (used by --loop in cluster mode).
# Logs every detected failure via Send_Alert (write-only when no
# alert_email / webhook_url is configured).
Monitor_Cluster_Loop() {
  local interval=${1:-60}

  echo "${CMSG}Starting cluster continuous monitoring (interval: ${interval}s)...${CEND}"
  echo "Press Ctrl+C to stop."

  while true; do
    Monitor_Cluster_Status
    local rc=$?
    if [ ${rc} -ne 0 ]; then
      Send_Alert "cluster health check failed (rc=${rc})"
      if [ "${recovery_flag:-n}" == "y" ]; then
        Auto_Recovery_Cluster
      fi
    fi
    sleep ${interval}
  done
}
