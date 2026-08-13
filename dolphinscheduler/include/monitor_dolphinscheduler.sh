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
    sleep ${interval}
  done
}
