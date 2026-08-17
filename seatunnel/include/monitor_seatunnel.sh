#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Monitor Module
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

Check_Process() {
  local service_name=${1:-seatunnel}
  local process_pattern="seatunnel"

  if pgrep -f "${process_pattern}" > /dev/null 2>&1; then
    echo "${CSUCCESS}[OK] ${service_name} process is running${CEND}"
    return 0
  else
    echo "${CFAILURE}[CRITICAL] ${service_name} process is NOT running!${CEND}"
    
    # Try to auto-recover
    if [ "${auto_recover}" == "true" ]; then
      echo "${CMSG}Attempting auto-recovery...${CEND}"
      if [ "${deploy_mode}" == "hybrid" ]; then
        systemctl restart seatunnel
      elif [ "${deploy_mode}" == "separated" ]; then
        if [ "${node_role}" == "master" ]; then
          systemctl restart seatunnel-master
        else
          systemctl restart seatunnel-worker
        fi
      fi
      
      sleep 5
      
      if pgrep -f "${process_pattern}" > /dev/null 2>&1; then
        echo "${CSUCCESS}[RECOVERED] ${service_name} restarted successfully${CEND}"
        Send_Alert "${service_name} was down, auto-recovered"
        return 0
      else
        Send_Alert "${service_name} is DOWN and auto-recovery FAILED"
        return 1
      fi
    fi
    
    Send_Alert "${service_name} process is not running"
    return 1
  fi
}

Check_Port() {
  local service_name=${1:-seatunnel}
  local port=${2:-${hazelcast_port:-5801}}
  local host=${3:-127.0.0.1}

  if ss -tlnp | grep -q ":${port} "; then
    echo "${CSUCCESS}[OK] ${service_name} port ${port} is listening${CEND}"
    return 0
  else
    echo "${CFAILURE}[CRITICAL] ${service_name} port ${port} is NOT listening!${CEND}"
    Send_Alert "${service_name} port ${port} not listening"
    return 1
  fi
}

Check_REST_API() {
  local host=${1:-127.0.0.1}
  local port=${2:-${hazelcast_port:-5801}}

  echo "${CMSG}Checking REST API...${CEND}"

  # Check cluster status
  local cluster_response=$(curl -s --connect-timeout 5 --max-time 10 "http://${host}:${port}/hazelcast/rest/cluster" 2>/dev/null)
  
  if [ -n "${cluster_response}" ]; then
    echo "${CSUCCESS}[OK] REST API is responding${CEND}"
    
    # Parse cluster info
    local member_count=$(echo "${cluster_response}" | grep -oP 'members.*?\[.*?\]' | grep -oP '\d+\.\d+\.\d+\.\d+' | wc -l)
    echo "  Cluster members: ${member_count}"
    
    return 0
  else
    echo "${CFAILURE}[WARNING] REST API is not responding${CEND}"
    return 1
  fi
}

Check_Running_Jobs() {
  local host=${1:-127.0.0.1}
  local port=${2:-${hazelcast_port:-5801}}

  echo "${CMSG}Checking running jobs...${CEND}"

  local jobs_response=$(curl -s --connect-timeout 5 --max-time 10 "http://${host}:${port}/hazelcast/rest/maps/running-jobs" 2>/dev/null)
  
  if [ -n "${jobs_response}" ]; then
    local job_count=$(echo "${jobs_response}" | grep -oP '"jobId"' | wc -l)
    echo "  Running jobs: ${job_count}"
    
    if [ ${job_count} -gt 0 ]; then
      echo "${jobs_response}" | python3 -m json.tool 2>/dev/null || echo "${jobs_response}"
    fi
    
    return 0
  else
    echo "  Unable to retrieve job information"
    return 1
  fi
}

Check_Java_Process() {
  local pid=$(pgrep -f "seatunnel" | head -1)
  
  if [ -z "${pid}" ]; then
    echo "${CWARNING}No SeaTunnel Java process found${CEND}"
    return 1
  fi

  echo "${CMSG}Java Process Status (PID: ${pid})${CEND}"

  # Memory usage
  local mem_info=$(ps -p ${pid} -o %mem,rss,vsz --no-headers 2>/dev/null)
  if [ -n "${mem_info}" ]; then
    local mem_percent=$(echo "${mem_info}" | awk '{print $1}')
    local rss_kb=$(echo "${mem_info}" | awk '{print $2}')
    local rss_mb=$((rss_kb / 1024))
    echo "  Memory: ${mem_percent}% (${rss_mb} MB RSS)"
  fi

  # CPU usage
  local cpu_info=$(ps -p ${pid} -o %cpu --no-headers 2>/dev/null)
  if [ -n "${cpu_info}" ]; then
    echo "  CPU: ${cpu_info}%"
  fi

  # Uptime
  local start_time=$(ps -p ${pid} -o lstart --no-headers 2>/dev/null)
  if [ -n "${start_time}" ]; then
    echo "  Started: ${start_time}"
  fi

  # Thread count
  local thread_count=$(ps -p ${pid} -o nlwp --no-headers 2>/dev/null)
  if [ -n "${thread_count}" ]; then
    echo "  Threads: ${thread_count}"
  fi

  return 0
}

Check_Disk() {
  local threshold=${1:-85}
  local alert_sent=0

  echo "${CMSG}Checking disk usage...${CEND}"

  # Check install directory
  local install_usage=$(df -h ${seatunnel_install_dir} 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
  if [ -n "${install_usage}" ] && [ ${install_usage} -gt ${threshold} ]; then
    echo "${CWARNING}[WARNING] Install directory disk usage: ${install_usage}%${CEND}"
    Send_Alert "Disk usage warning: ${seatunnel_install_dir} at ${install_usage}%"
    alert_sent=1
  else
    echo "  Install directory: ${install_usage:-N/A}%"
  fi

  # Check log directory
  local log_usage=$(df -h ${seatunnel_install_dir}/logs 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
  if [ -n "${log_usage}" ] && [ ${log_usage} -gt ${threshold} ]; then
    echo "${CWARNING}[WARNING] Log directory disk usage: ${log_usage}%${CEND}"
    Send_Alert "Disk usage warning: logs at ${log_usage}%"
    alert_sent=1
  fi

  # Check checkpoint directory
  if [ -d "${seatunnel_checkpoint_dir}" ]; then
    local checkpoint_usage=$(df -h ${seatunnel_checkpoint_dir} 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    if [ -n "${checkpoint_usage}" ] && [ ${checkpoint_usage} -gt ${threshold} ]; then
      echo "${CWARNING}[WARNING] Checkpoint directory disk usage: ${checkpoint_usage}%${CEND}"
      Send_Alert "Disk usage warning: checkpoint at ${checkpoint_usage}%"
      alert_sent=1
    else
      echo "  Checkpoint directory: ${checkpoint_usage:-N/A}%"
    fi
  fi

  return ${alert_sent}
}

Check_Cluster_Health() {
  local host=${1:-127.0.0.1}
  local port=${2:-${hazelcast_port:-5801}}

  echo "${CMSG}Checking cluster health...${CEND}"

  # Get cluster members
  local cluster_response=$(curl -s --connect-timeout 5 --max-time 10 "http://${host}:${port}/hazelcast/rest/cluster" 2>/dev/null)
  
  if [ -z "${cluster_response}" ]; then
    echo "${CFAILURE}[CRITICAL] Cannot connect to cluster${CEND}"
    return 1
  fi

  # Parse and display cluster info
  echo "  Cluster response received"
  
  # Check if all expected members are present
  local expected_members=$(echo "${cluster_members}" | tr ',' '\n' | wc -l)
  local actual_members=$(echo "${cluster_response}" | grep -oP '\d+\.\d+\.\d+\.\d+' | sort -u | wc -l)
  
  if [ ${actual_members} -lt ${expected_members} ]; then
    echo "${CWARNING}[WARNING] Expected ${expected_members} members, found ${actual_members}${CEND}"
    Send_Alert "Cluster member count mismatch: expected ${expected_members}, found ${actual_members}"
    return 1
  else
    echo "${CSUCCESS}[OK] All ${actual_members} cluster members are present${CEND}"
    return 0
  fi
}

Send_Alert() {
  local message=$1
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local hostname=$(hostname)
  local log_file=${seatunnel_install_dir}/logs/monitor.log

  # Log to file
  mkdir -p $(dirname ${log_file})
  echo "[${timestamp}] ALERT: ${message}" >> ${log_file}

  # Email notification
  if [ -n "${alert_email}" ]; then
    echo "${message}" | mail -s "[SeaTunnel Alert] ${hostname}" ${alert_email} 2>/dev/null
  fi

  # Webhook notification (DingTalk/Feishu/Slack)
  if [ -n "${webhook_url}" ]; then
    curl -s -X POST "${webhook_url}" \
      -H 'Content-Type: application/json' \
      -d "{\"text\": \"[${hostname}] ${timestamp} ${message}\"}" > /dev/null 2>&1
  fi
}

Monitor_Status() {
  echo
  echo "=========================================="
  echo "${CMSG}SeaTunnel Status Report${CEND}"
  echo "=========================================="
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Host: $(hostname)"
  echo

  # Version info
  local version=$(ls ${seatunnel_install_dir}/lib/seatunnel-*.jar 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)
  echo "Version: ${version:-Unknown}"
  echo "Deploy Mode: ${deploy_mode}"
  echo "Cluster Name: ${cluster_name}"
  echo

  # Service status
  echo "--- Service Status ---"
  if [ "${deploy_mode}" == "hybrid" ]; then
    systemctl is-active seatunnel > /dev/null 2>&1 && echo "seatunnel: ${CSUCCESS}active${CEND}" || echo "seatunnel: ${CFAILURE}inactive${CEND}"
  elif [ "${deploy_mode}" == "separated" ]; then
    systemctl is-active seatunnel-master > /dev/null 2>&1 && echo "seatunnel-master: ${CSUCCESS}active${CEND}" || echo "seatunnel-master: ${CFAILURE}inactive${CEND}"
    systemctl is-active seatunnel-worker > /dev/null 2>&1 && echo "seatunnel-worker: ${CSUCCESS}active${CEND}" || echo "seatunnel-worker: ${CFAILURE}inactive${CEND}"
  fi
  echo

  # Process info
  echo "--- Process Info ---"
  Check_Java_Process
  echo

  # Port status
  echo "--- Port Status ---"
  Check_Port "Hazelcast" ${hazelcast_port:-5801}
  echo

  # Disk usage
  echo "--- Disk Usage ---"
  Check_Disk
  echo

  # REST API status
  echo "--- REST API ---"
  Check_REST_API
  echo

  # Running jobs
  echo "--- Running Jobs ---"
  Check_Running_Jobs
  echo

  echo "=========================================="
}

Monitor_Check() {
  local exit_code=0

  echo "${CMSG}Running health checks...${CEND}"
  echo

  Check_Process || exit_code=1
  Check_Port "Hazelcast" ${hazelcast_port:-5801} || exit_code=1
  Check_REST_API || exit_code=1
  Check_Disk || exit_code=1

  if [ "${deploy_mode}" != "local" ]; then
    Check_Cluster_Health || exit_code=1
  fi

  echo
  if [ ${exit_code} -eq 0 ]; then
    echo "${CSUCCESS}All health checks passed!${CEND}"
  else
    echo "${CFAILURE}Some health checks failed!${CEND}"
  fi

  return ${exit_code}
}
