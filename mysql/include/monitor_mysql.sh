#!/bin/bash
# MySQL 监控模块
# Author: DMP OPS
#
# 说明: MySQL 健康检查与状态监控，包含进程、端口、连接数、复制状态等检查

# 检查 MySQL 进程
Check_MySQL_Process() {
  if ! pgrep -x "mysqld" > /dev/null 2>&1; then
    echo "${CFAILURE}[CRITICAL] MySQL process is NOT running!${CEND}"
    
    # 尝试自动恢复
    echo "${CMSG}Attempting to restart MySQL...${CEND}"
    service mysqld start
    sleep 3
    
    if pgrep -x "mysqld" > /dev/null 2>&1; then
      echo "${CSUCCESS}[RECOVERED] MySQL restarted successfully${CEND}"
      Send_Alert "MySQL was down, auto-recovered on $(hostname)"
      return 0
    else
      Send_Alert "CRITICAL: MySQL is DOWN on $(hostname) and auto-recovery FAILED"
      return 1
    fi
  fi
  echo "${CSUCCESS}[OK] MySQL process is running${CEND}"
  return 0
}

# 检查 MySQL 端口
Check_MySQL_Port() {
  local port=${1:-3306}
  
  if ! ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    echo "${CFAILURE}[CRITICAL] MySQL port ${port} is NOT listening!${CEND}"
    Send_Alert "CRITICAL: MySQL port ${port} not listening on $(hostname)"
    return 1
  fi
  echo "${CSUCCESS}[OK] MySQL port ${port} is listening${CEND}"
  return 0
}

# 检查连接数
Check_MySQL_Connections() {
  local threshold=${1:-${conn_threshold:-80}}
  
  local max_conn=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}')
  local cur_conn=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{print $2}')
  
  if [ -n "${max_conn}" ] && [ -n "${cur_conn}" ] && [ "${max_conn}" -gt 0 ]; then
    local usage=$((cur_conn * 100 / max_conn))
    
    if [ ${usage} -gt ${threshold} ]; then
      echo "${CWARNING}[WARNING] MySQL connections usage: ${usage}% (${cur_conn}/${max_conn})${CEND}"
      Send_Alert "WARNING: MySQL connections high: ${usage}% on $(hostname)"
      return 1
    fi
    echo "${CSUCCESS}[OK] MySQL connections: ${usage}% (${cur_conn}/${max_conn})${CEND}"
  else
    echo "${CWARNING}[WARNING] Cannot get connection info${CEND}"
  fi
  return 0
}

# 检查复制状态（从库）
Check_MySQL_Replication() {
  local slave_status=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "SHOW SLAVE STATUS\G" 2>/dev/null)
  
  if [ -z "${slave_status}" ]; then
    echo "${CMSG}[INFO] This is not a slave server (no replication configured)${CEND}"
    return 0
  fi
  
  local io_running=$(echo "${slave_status}" | grep "Slave_IO_Running:" | awk '{print $2}')
  local sql_running=$(echo "${slave_status}" | grep "Slave_SQL_Running:" | awk '{print $2}')
  local seconds_behind=$(echo "${slave_status}" | grep "Seconds_Behind_Master:" | awk '{print $2}')
  local last_error=$(echo "${slave_status}" | grep "Last_Error:" | cut -d':' -f2-)
  
  # 检查 IO 线程
  if [ "${io_running}" != "Yes" ]; then
    echo "${CFAILURE}[CRITICAL] Slave IO thread is NOT running!${CEND}"
    Send_Alert "CRITICAL: MySQL replication IO thread stopped on $(hostname)"
    return 1
  fi
  
  # 检查 SQL 线程
  if [ "${sql_running}" != "Yes" ]; then
    echo "${CFAILURE}[CRITICAL] Slave SQL thread is NOT running!${CEND}"
    [ -n "${last_error}" ] && echo "Last Error: ${last_error}"
    Send_Alert "CRITICAL: MySQL replication SQL thread stopped on $(hostname)"
    return 1
  fi
  
  # 检查复制延迟
  local lag_threshold=${repl_lag_threshold:-60}
  if [ "${seconds_behind}" != "NULL" ] && [ "${seconds_behind}" -gt ${lag_threshold} ]; then
    echo "${CWARNING}[WARNING] MySQL replication lag: ${seconds_behind}s${CEND}"
    Send_Alert "WARNING: MySQL replication lag ${seconds_behind}s on $(hostname)"
    return 1
  fi
  
  echo "${CSUCCESS}[OK] MySQL replication is healthy (lag: ${seconds_behind}s)${CEND}"
  return 0
}

# 检查慢查询
Check_MySQL_SlowQueries() {
  local threshold=${1:-${slow_query_threshold:-100}}
  
  local slow_queries=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';" 2>/dev/null | awk '{print $2}')
  
  if [ -n "${slow_queries}" ] && [ ${slow_queries} -gt ${threshold} ]; then
    echo "${CWARNING}[WARNING] MySQL slow queries: ${slow_queries}${CEND}"
    return 1
  fi
  echo "${CSUCCESS}[OK] MySQL slow queries: ${slow_queries:-0}${CEND}"
  return 0
}

# 检查磁盘空间
Check_MySQL_Disk() {
  local threshold=${1:-${disk_threshold:-85}}
  
  if [ ! -d "${db_data_dir}" ]; then
    echo "${CWARNING}[WARNING] Data directory not found: ${db_data_dir}${CEND}"
    return 1
  fi
  
  local data_dir_usage=$(df -h "${db_data_dir}" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
  
  if [ -n "${data_dir_usage}" ] && [ ${data_dir_usage} -gt ${threshold} ]; then
    echo "${CWARNING}[WARNING] MySQL data directory disk usage: ${data_dir_usage}%${CEND}"
    Send_Alert "WARNING: MySQL data disk usage ${data_dir_usage}% on $(hostname)"
    return 1
  fi
  echo "${CSUCCESS}[OK] MySQL data directory disk usage: ${data_dir_usage}%${CEND}"
  return 0
}

# 检查 InnoDB 状态
Check_MySQL_InnoDB() {
  local buffer_pool_usage=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "
    SELECT ROUND(
      (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_pages_data') /
      (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_pages_total') * 100
    );" 2>/dev/null)
  
  if [ -n "${buffer_pool_usage}" ]; then
    echo "${CSUCCESS}[OK] InnoDB buffer pool usage: ${buffer_pool_usage}%${CEND}"
  fi
}

# 发送告警
Send_Alert() {
  local message=$1
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  # 确保日志目录存在
  [ ! -d "${log_dir}" ] && mkdir -p ${log_dir}
  
  # 记录到日志
  echo "[${timestamp}] ALERT: ${message}" >> ${log_dir}/monitor.log

  # 邮件通知
  if [ -n "${alert_email}" ]; then
    echo "${message}" | mail -s "[MySQL Alert] $(hostname)" ${alert_email} 2>/dev/null
  fi

  # Webhook 通知（支持钉钉/企业微信/Slack）
  if [ -n "${webhook_url}" ]; then
    curl -s -X POST "${webhook_url}" \
      -H 'Content-Type: application/json' \
      -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"[$(hostname)] ${timestamp}\n${message}\"}}" 2>/dev/null
  fi
}

# 状态报告
Monitor_MySQL_Status() {
  echo ""
  echo "========== MySQL Status Report: $(date) =========="
  echo ""
  
  # 版本信息
  local version=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SELECT VERSION();" 2>/dev/null)
  echo "MySQL Version:     ${version}"
  
  # 运行时间
  local uptime=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW STATUS LIKE 'Uptime';" 2>/dev/null | awk '{print $2}')
  if [ -n "${uptime}" ]; then
    local days=$((uptime/86400))
    local hours=$((uptime%86400/3600))
    local mins=$((uptime%3600/60))
    echo "Uptime:            ${days}d ${hours}h ${mins}m"
  fi
  
  # 连接数
  local threads=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{print $2}')
  local max_conn=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}')
  echo "Connections:       ${threads}/${max_conn}"
  
  # QPS
  local questions=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW STATUS LIKE 'Questions';" 2>/dev/null | awk '{print $2}')
  if [ -n "${uptime}" ] && [ "${uptime}" -gt 0 ]; then
    local qps=$((questions/uptime))
    echo "QPS (avg):         ${qps}"
  fi
  
  # 慢查询
  local slow=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW STATUS LIKE 'Slow_queries';" 2>/dev/null | awk '{print $2}')
  echo "Slow Queries:      ${slow}"
  
  # InnoDB Buffer Pool
  local bp_size=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null | awk '{print $2}')
  if [ -n "${bp_size}" ]; then
    local bp_mb=$((bp_size/1024/1024))
    echo "Buffer Pool Size:  ${bp_mb}M"
  fi
  
  echo ""
  echo "===================================================="
}

# 执行所有检查
Monitor_MySQL_All() {
  echo ""
  echo "========== MySQL Health Check: $(date) =========="
  echo ""
  
  Check_MySQL_Process
  Check_MySQL_Port 3306
  Check_MySQL_Connections
  Check_MySQL_Replication
  Check_MySQL_SlowQueries
  Check_MySQL_Disk
  
  echo ""
  echo "===================================================="
}
