#!/bin/bash
# ZooKeeper 事务日志工具
# 项目: oneinstack/zookeeper
# 用法: ./tools/zk_txnlog.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

script_dir=$(cd "$(dirname "$0")/.." && pwd)
. "${script_dir}/options.conf"
. "${script_dir}/include/color.sh"

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

ZooKeeper Transaction Log Tool

Options:
  -h, --help        Show this help message
  --list            List all transaction logs
  --info FILE       Show transaction log info
  --dump FILE       Dump transaction log content
  --cleanup         Clean up old transaction logs
  --purge DAYS      Purge logs older than DAYS

Examples:
  $0 --list
  $0 --info log.100000001
  $0 --cleanup
  $0 --purge 7

EOF
}

# 列出所有事务日志
List_TxnLogs() {
  echo "${CMSG}=== ZooKeeper Transaction Logs ===${CEND}"
  
  local log_dir="${zk_log_dir:-${zk_data_dir}}/version-2"
  
  if [ ! -d "${log_dir}" ]; then
    echo "No transaction logs found"
    return 1
  fi
  
  ls -lh "${log_dir}/log."* 2>/dev/null | while read line; do
    echo "  ${line}"
  done
  
  echo ""
  echo "Total: $(ls "${log_dir}/log."* 2>/dev/null | wc -l) log(s)"
  
  # 显示总大小
  local total_size=$(du -sh "${log_dir}" 2>/dev/null | awk '{print $1}')
  echo "Total Size: ${total_size}"
}

# 显示事务日志信息
Show_TxnLog_Info() {
  local log_file=$1
  local log_dir="${zk_log_dir:-${zk_data_dir}}/version-2"
  
  if [ ! -f "${log_file}" ]; then
    log_file="${log_dir}/${log_file}"
  fi
  
  if [ ! -f "${log_file}" ]; then
    echo "${CFAILURE}Transaction log not found: ${log_file}${CEND}"
    return 1
  fi
  
  echo "${CMSG}=== Transaction Log Info ===${CEND}"
  echo "File: ${log_file}"
  echo "Size: $(du -h "${log_file}" | awk '{print $1}')"
  echo "Modified: $(stat -c %y "${log_file}")"
  
  # 使用 zkTxnLogToolkit 获取详细信息
  if [ -x "${zk_install_dir}/bin/zkTxnLogToolkit.sh" ]; then
    echo ""
    echo "${CMSG}Log Details:${CEND}"
    ${zk_install_dir}/bin/zkTxnLogToolkit.sh "${log_file}" 2>/dev/null | head -20
  fi
}

# 转储事务日志
Dump_TxnLog() {
  local log_file=$1
  local log_dir="${zk_log_dir:-${zk_data_dir}}/version-2"
  
  if [ ! -f "${log_file}" ]; then
    log_file="${log_dir}/${log_file}"
  fi
  
  if [ ! -f "${log_file}" ]; then
    echo "${CFAILURE}Transaction log not found: ${log_file}${CEND}"
    return 1
  fi
  
  if [ -x "${zk_install_dir}/bin/zkTxnLogToolkit.sh" ]; then
    ${zk_install_dir}/bin/zkTxnLogToolkit.sh "${log_file}"
  else
    echo "${CFAILURE}zkTxnLogToolkit.sh not found${CEND}"
    return 1
  fi
}

# 清理旧事务日志
Cleanup_TxnLogs() {
  echo "${CMSG}=== Cleaning Up Transaction Logs ===${CEND}"
  
  if [ -x "${zk_install_dir}/bin/zkCleanup.sh" ]; then
    echo "Running zkCleanup.sh..."
    ${zk_install_dir}/bin/zkCleanup.sh "${zk_data_dir}" -n 3
    echo "${CSUCCESS}Cleanup complete${CEND}"
  else
    echo "${CWARNING}zkCleanup.sh not found, using manual cleanup${CEND}"
    
    local log_dir="${zk_log_dir:-${zk_data_dir}}/version-2"
    local snap_dir="${zk_data_dir}/version-2"
    
    # 保留最新的 3 个快照和对应的日志
    local keep_count=3
    
    # 获取要保留的快照
    local keep_snaps=$(ls -t "${snap_dir}/snapshot."* 2>/dev/null | head -${keep_count})
    
    if [ -n "${keep_snaps}" ]; then
      # 获取最旧的保留快照的 zxid
      local oldest_snap=$(echo "${keep_snaps}" | tail -1)
      local oldest_zxid=$(basename "${oldest_snap}" | sed 's/snapshot.//')
      
      echo "Keeping snapshots newer than: ${oldest_zxid}"
      
      # 删除旧的日志
      for log in "${log_dir}/log."*; do
        [ ! -f "${log}" ] && continue
        local log_zxid=$(basename "${log}" | sed 's/log.//')
        
        if [ "${log_zxid}" -lt "${oldest_zxid}" ]; then
          echo "Removing: ${log}"
          rm -f "${log}"
        fi
      done
    fi
    
    echo "${CSUCCESS}Manual cleanup complete${CEND}"
  fi
}

# 清除指定天数前的日志
Purge_TxnLogs() {
  local days=$1
  
  echo "${CMSG}=== Purging Transaction Logs Older Than ${days} Days ===${CEND}"
  
  local log_dir="${zk_log_dir:-${zk_data_dir}}/version-2"
  
  local deleted=$(find "${log_dir}" -name "log.*" -mtime +${days} -delete -print | wc -l)
  
  echo "Deleted ${deleted} old transaction log(s)"
  echo "${CSUCCESS}Purge complete${CEND}"
}

# 解析参数
action="list"
target_file=""
purge_days=""

TEMP=$(getopt -o h --long help,list,info:,dump:,cleanup,purge: -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }

eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    --list)
      action="list"
      shift
      ;;
    --info)
      action="info"
      target_file="$2"
      shift 2
      ;;
    --dump)
      action="dump"
      target_file="$2"
      shift 2
      ;;
    --cleanup)
      action="cleanup"
      shift
      ;;
    --purge)
      action="purge"
      purge_days="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

case "${action}" in
  list)
    List_TxnLogs
    ;;
  info)
    Show_TxnLog_Info "${target_file}"
    ;;
  dump)
    Dump_TxnLog "${target_file}"
    ;;
  cleanup)
    Cleanup_TxnLogs
    ;;
  purge)
    Purge_TxnLogs "${purge_days}"
    ;;
esac
