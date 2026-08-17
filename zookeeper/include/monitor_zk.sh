#!/bin/bash
# ZooKeeper 监控模块
# 项目: oneinstack/zookeeper

# 基础健康检查（ruok）
Check_ZK_Health() {
  local host=${1:-127.0.0.1}
  local port=${2:-${zk_client_port}}
  
  local response=$(echo "ruok" | nc -w 2 ${host} ${port} 2>/dev/null)
  
  if [ "${response}" == "imok" ]; then
    echo "${CSUCCESS}[OK] ZooKeeper is healthy (${host}:${port})${CEND}"
    return 0
  else
    echo "${CFAILURE}[CRITICAL] ZooKeeper health check failed (${host}:${port})${CEND}"
    Send_Alert "ZooKeeper health check failed on ${host}:${port}"
    return 1
  fi
}

# 获取服务器状态（srvr）
Check_ZK_Status() {
  local host=${1:-127.0.0.1}
  local port=${2:-${zk_client_port}}
  
  local status=$(echo "srvr" | nc -w 2 ${host} ${port} 2>/dev/null)
  
  if [ -n "${status}" ]; then
    local version=$(echo "${status}" | grep "Zookeeper version:" | cut -d':' -f2 | xargs)
    local mode=$(echo "${status}" | grep "Mode:" | awk '{print $2}')
    local connections=$(echo "${status}" | grep "Connections:" | awk '{print $2}')
    local outstanding=$(echo "${status}" | grep "Outstanding:" | awk '{print $2}')
    local znode_count=$(echo "${status}" | grep "Node count:" | awk '{print $3}')
    
    echo "${CMSG}=== ZooKeeper Status (${host}:${port}) ===${CEND}"
    echo "  Version: ${version}"
    echo "  Mode: ${mode}"
    echo "  Connections: ${connections}"
    echo "  Outstanding: ${outstanding}"
    echo "  ZNode Count: ${znode_count}"
    
    # 角色标识
    case "${mode}" in
      leader)
        echo "  ${CSUCCESS}★ This node is LEADER${CEND}"
        ;;
      follower)
        echo "  ${CMSG}This node is FOLLOWER${CEND}"
        ;;
      standalone)
        echo "  ${CMSG}Running in STANDALONE mode${CEND}"
        ;;
      observer)
        echo "  ${CMSG}This node is OBSERVER${CEND}"
        ;;
    esac
    
    return 0
  else
    echo "${CFAILURE}[ERROR] Cannot get ZooKeeper status (${host}:${port})${CEND}"
    return 1
  fi
}

# 获取监控指标（mntr）
Check_ZK_Metrics() {
  local host=${1:-127.0.0.1}
  local port=${2:-${zk_client_port}}
  
  local metrics=$(echo "mntr" | nc -w 2 ${host} ${port} 2>/dev/null)
  
  if [ -n "${metrics}" ]; then
    local avg_latency=$(echo "${metrics}" | grep "zk_avg_latency" | awk '{print $2}')
    local max_latency=$(echo "${metrics}" | grep "zk_max_latency" | awk '{print $2}')
    local min_latency=$(echo "${metrics}" | grep "zk_min_latency" | awk '{print $2}')
    local outstanding=$(echo "${metrics}" | grep "zk_outstanding_requests" | awk '{print $2}')
    local watch_count=$(echo "${metrics}" | grep "zk_watch_count" | awk '{print $2}')
    local ephemerals=$(echo "${metrics}" | grep "zk_ephemerals_count" | awk '{print $2}')
    local packets_received=$(echo "${metrics}" | grep "zk_packets_received" | awk '{print $2}')
    local packets_sent=$(echo "${metrics}" | grep "zk_packets_sent" | awk '{print $2}')
    
    echo "${CMSG}=== ZooKeeper Metrics ===${CEND}"
    echo "  Avg Latency: ${avg_latency:-0}ms"
    echo "  Min Latency: ${min_latency:-0}ms"
    echo "  Max Latency: ${max_latency:-0}ms"
    echo "  Outstanding Requests: ${outstanding:-0}"
    echo "  Watch Count: ${watch_count:-0}"
    echo "  Ephemeral Nodes: ${ephemerals:-0}"
    echo "  Packets Received: ${packets_received:-0}"
    echo "  Packets Sent: ${packets_sent:-0}"
    
    # 延迟告警
    if [ -n "${avg_latency}" ] && [ "${avg_latency}" -gt 100 ]; then
      echo "${CWARNING}[WARNING] High average latency: ${avg_latency}ms${CEND}"
      Send_Alert "ZooKeeper high latency: ${avg_latency}ms on ${host}:${port}"
    fi
    
    # 未处理请求告警
    if [ -n "${outstanding}" ] && [ "${outstanding}" -gt 10 ]; then
      echo "${CWARNING}[WARNING] High outstanding requests: ${outstanding}${CEND}"
      Send_Alert "ZooKeeper high outstanding requests: ${outstanding} on ${host}:${port}"
    fi
    
    return 0
  else
    echo "${CWARNING}[WARNING] Cannot get metrics (mntr command may be disabled)${CEND}"
    return 1
  fi
}

# 检查客户端连接数
Check_ZK_Connections() {
  local host=${1:-127.0.0.1}
  local port=${2:-${zk_client_port}}
  local max_connections=${3:-1000}
  
  local cons=$(echo "cons" | nc -w 2 ${host} ${port} 2>/dev/null)
  local conn_count=$(echo "${cons}" | grep -c "^/")
  
  echo "${CMSG}=== ZooKeeper Connections ===${CEND}"
  echo "  Active Connections: ${conn_count}"
  
  if [ "${conn_count}" -gt "${max_connections}" ]; then
    echo "${CWARNING}[WARNING] Too many connections: ${conn_count}/${max_connections}${CEND}"
    Send_Alert "ZooKeeper connections exceeded: ${conn_count}/${max_connections} on ${host}:${port}"
    return 1
  fi
  
  return 0
}

# 检查配置信息
Check_ZK_Config() {
  local host=${1:-127.0.0.1}
  local port=${2:-${zk_client_port}}
  
  local conf=$(echo "conf" | nc -w 2 ${host} ${port} 2>/dev/null)
  
  if [ -n "${conf}" ]; then
    echo "${CMSG}=== ZooKeeper Configuration ===${CEND}"
    echo "${conf}" | head -20
    return 0
  fi
  return 1
}

# 检查磁盘空间
Check_Disk() {
  local threshold=${1:-85}
  local alert_sent=0
  
  echo "${CMSG}=== Disk Usage ===${CEND}"
  
  # 检查数据目录
  if [ -d "${zk_data_dir}" ]; then
    local data_usage=$(df -h "${zk_data_dir}" | awk 'NR==2{print $5}' | tr -d '%')
    local data_mount=$(df -h "${zk_data_dir}" | awk 'NR==2{print $6}')
    echo "  Data Dir (${data_mount}): ${data_usage}%"
    
    if [ "${data_usage}" -gt "${threshold}" ]; then
      echo "${CWARNING}[WARNING] Data directory disk usage high: ${data_usage}%${CEND}"
      Send_Alert "ZooKeeper data directory disk usage: ${data_usage}%"
      alert_sent=1
    fi
  fi
  
  # 检查日志目录
  if [ -d "${zk_log_dir}" ]; then
    local log_usage=$(df -h "${zk_log_dir}" | awk 'NR==2{print $5}' | tr -d '%')
    local log_mount=$(df -h "${zk_log_dir}" | awk 'NR==2{print $6}')
    echo "  Log Dir (${log_mount}): ${log_usage}%"
    
    if [ "${log_usage}" -gt "${threshold}" ]; then
      echo "${CWARNING}[WARNING] Log directory disk usage high: ${log_usage}%${CEND}"
      Send_Alert "ZooKeeper log directory disk usage: ${log_usage}%"
      alert_sent=1
    fi
  fi
  
  return ${alert_sent}
}

# 告警通知
Send_Alert() {
  local message=$1
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local hostname=$(hostname)
  
  # 记录到日志
  local log_file="${zk_log_dir}/monitor.log"
  mkdir -p "$(dirname ${log_file})"
  echo "[${timestamp}] ALERT: ${message}" >> "${log_file}"
  
  # 邮件通知
  if [ -n "${alert_email}" ]; then
    echo "${message}" | mail -s "[ZooKeeper Alert] ${hostname}" "${alert_email}" 2>/dev/null
  fi
  
  # Webhook 通知
  if [ -n "${webhook_url}" ]; then
    local payload="{\"text\": \"[ZooKeeper] [${hostname}] ${timestamp} ${message}\"}"
    curl -s -X POST "${webhook_url}" \
      -H 'Content-Type: application/json' \
      -d "${payload}" 2>/dev/null
  fi
}

# 主监控函数
Monitor_ZooKeeper() {
  local host=${1:-127.0.0.1}
  local port=${2:-${zk_client_port}}
  
  echo "========== ZooKeeper Monitor: $(date) =========="
  echo ""
  
  Check_ZK_Health "${host}" "${port}" || return 1
  echo ""
  
  Check_ZK_Status "${host}" "${port}"
  echo ""
  
  Check_ZK_Metrics "${host}" "${port}"
  echo ""
  
  Check_ZK_Connections "${host}" "${port}"
  echo ""
  
  Check_Disk
  echo ""
  
  # 集群模式检查
  if [ "${deploy_mode}" == "cluster" ] && [ -n "${cluster_nodes}" ]; then
    echo ""
    Check_Cluster_Status
  fi
  
  echo "========== Monitor Complete =========="
}

# 输出状态报告
Monitor_Status() {
  echo "${CMSG}=== ZooKeeper Status Report ===${CEND}"
  echo "Time: $(date)"
  echo ""
  
  # 服务状态
  if systemctl is-active zookeeper &>/dev/null; then
    echo "Service: ${CSUCCESS}RUNNING${CEND}"
  else
    echo "Service: ${CFAILURE}STOPPED${CEND}"
    return 1
  fi
  
  # 进程信息
  local pid=$(pgrep -f "zookeeper" | head -1)
  if [ -n "${pid}" ]; then
    local uptime=$(ps -o etime= -p ${pid} | xargs)
    local mem=$(ps -o rss= -p ${pid} | awk '{printf "%.1f MB", $1/1024}')
    local cpu=$(ps -o %cpu= -p ${pid} | xargs)
    
    echo "PID: ${pid}"
    echo "Uptime: ${uptime}"
    echo "Memory: ${mem}"
    echo "CPU: ${cpu}%"
  fi
  
  echo ""
  Check_ZK_Status
}
