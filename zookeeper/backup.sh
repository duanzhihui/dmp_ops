#!/bin/bash
# ZooKeeper 备份执行脚本
# 项目: oneinstack/zookeeper
# 用法: ./backup.sh [OPTIONS]
# 可由 cron 定时调用

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本目录
script_dir=$(cd "$(dirname "$0")" && pwd)

# 加载配置
. "${script_dir}/options.conf"
. "${script_dir}/include/color.sh"

# 显示帮助
Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

ZooKeeper Backup Script

Options:
  -h, --help        Show this help message
  --full            Full backup (snapshots + logs + config)
  --snapshot        Snapshot backup only
  --config          Config backup only
  --dest TYPE       Backup destination (local, oss, s3)

Examples:
  $0                    # Full backup to default destination
  $0 --snapshot         # Snapshot backup only
  $0 --dest oss         # Backup to OSS

EOF
}

# ZooKeeper 完整备份
ZK_Full_Backup() {
  local backup_name="zk_backup_$(date +%Y%m%d_%H%M%S)"
  local backup_file="${backup_dir}/${backup_name}.tar.gz"
  local temp_dir="/tmp/${backup_name}"
  
  echo "${CMSG}=== ZooKeeper Full Backup ===${CEND}"
  echo "Backup file: ${backup_file}"
  
  mkdir -p "${temp_dir}" "${backup_dir}"
  
  # 1. 备份快照和事务日志
  if [ -d "${zk_data_dir}/version-2" ]; then
    echo "Backing up snapshots and transaction logs..."
    cp -a "${zk_data_dir}/version-2" "${temp_dir}/"
  fi
  
  # 2. 备份 myid
  if [ -f "${zk_data_dir}/myid" ]; then
    cp "${zk_data_dir}/myid" "${temp_dir}/"
  fi
  
  # 3. 备份配置文件
  echo "Backing up configuration files..."
  mkdir -p "${temp_dir}/conf"
  cp "${zk_install_dir}/conf/zoo.cfg" "${temp_dir}/conf/" 2>/dev/null
  cp "${zk_install_dir}/conf/java.env" "${temp_dir}/conf/" 2>/dev/null
  cp "${zk_install_dir}/conf/log4j.properties" "${temp_dir}/conf/" 2>/dev/null
  
  # 4. 记录元信息
  cat > "${temp_dir}/backup_info.txt" << EOF
Backup Time: $(date)
Hostname: $(hostname)
ZooKeeper Version: $(cat ${zk_install_dir}/zookeeper-version.txt 2>/dev/null || echo "unknown")
Deploy Mode: ${deploy_mode}
MyID: ${myid}
EOF
  
  # 5. 打包压缩
  echo "Creating archive..."
  tar czf "${backup_file}" -C /tmp "${backup_name}"
  rm -rf "${temp_dir}"
  
  # 6. 显示结果
  local file_size=$(du -h "${backup_file}" | awk '{print $1}')
  echo "${CSUCCESS}Backup created: ${backup_file} (${file_size})${CEND}"
  
  # 7. 过期清理
  Cleanup_Old_Backups
  
  echo "${backup_file}"
}

# 快照备份
ZK_Snapshot_Backup() {
  local backup_name="zk_snapshot_$(date +%Y%m%d_%H%M%S)"
  local backup_file="${backup_dir}/${backup_name}.tar.gz"
  
  echo "${CMSG}=== ZooKeeper Snapshot Backup ===${CEND}"
  
  mkdir -p "${backup_dir}"
  
  if [ -d "${zk_data_dir}/version-2" ]; then
    tar czf "${backup_file}" -C "${zk_data_dir}" version-2
    echo "${CSUCCESS}Snapshot backup: ${backup_file}${CEND}"
  else
    echo "${CWARNING}No snapshot data found${CEND}"
    return 1
  fi
  
  Cleanup_Old_Backups
  echo "${backup_file}"
}

# 配置备份
ZK_Config_Backup() {
  local backup_name="zk_config_$(date +%Y%m%d_%H%M%S)"
  local backup_file="${backup_dir}/${backup_name}.tar.gz"
  
  echo "${CMSG}=== ZooKeeper Config Backup ===${CEND}"
  
  mkdir -p "${backup_dir}"
  
  tar czf "${backup_file}" -C "${zk_install_dir}" conf
  echo "${CSUCCESS}Config backup: ${backup_file}${CEND}"
  
  echo "${backup_file}"
}

# 清理过期备份
Cleanup_Old_Backups() {
  echo "Cleaning up old backups (older than ${expired_days} days)..."
  
  local deleted=$(find "${backup_dir}" -name "zk_*.tar.gz" -mtime +${expired_days} -delete -print | wc -l)
  
  if [ "${deleted}" -gt 0 ]; then
    echo "Deleted ${deleted} old backup(s)"
  fi
}

# 上传到 OSS
Upload_To_OSS() {
  local backup_file=$1
  local remote_path="oss://${oss_bucket}/zookeeper/$(date +%F)/"
  
  echo "${CMSG}Uploading to OSS...${CEND}"
  
  if ! command -v ossutil &> /dev/null; then
    echo "${CFAILURE}ossutil not found. Please install ossutil first.${CEND}"
    return 1
  fi
  
  ossutil cp -f "${backup_file}" "${remote_path}"
  
  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Uploaded to: ${remote_path}${CEND}"
    
    # 清理远程过期备份
    local old_date=$(date +%F --date="${expired_days} days ago")
    ossutil rm -rf "oss://${oss_bucket}/zookeeper/${old_date}/" 2>/dev/null
    
    # 如果不保留本地副本
    if [ "${backup_destination}" == "oss" ]; then
      rm -f "${backup_file}"
      echo "Local backup removed"
    fi
  else
    echo "${CFAILURE}Upload failed${CEND}"
    return 1
  fi
}

# 上传到 S3
Upload_To_S3() {
  local backup_file=$1
  local remote_path="s3://${s3_bucket}/zookeeper/$(date +%F)/"
  
  echo "${CMSG}Uploading to S3...${CEND}"
  
  if ! command -v aws &> /dev/null; then
    echo "${CFAILURE}AWS CLI not found. Please install aws-cli first.${CEND}"
    return 1
  fi
  
  aws s3 cp "${backup_file}" "${remote_path}"
  
  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Uploaded to: ${remote_path}${CEND}"
  else
    echo "${CFAILURE}Upload failed${CEND}"
    return 1
  fi
}

# 解析参数
backup_type="full"
dest_override=""

TEMP=$(getopt -o h --long help,full,snapshot,config,dest: -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }

eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    --full)
      backup_type="full"
      shift
      ;;
    --snapshot)
      backup_type="snapshot"
      shift
      ;;
    --config)
      backup_type="config"
      shift
      ;;
    --dest)
      dest_override="$2"
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

# 主逻辑
main() {
  local backup_file=""
  
  # 执行备份
  case "${backup_type}" in
    full)
      backup_file=$(ZK_Full_Backup)
      ;;
    snapshot)
      backup_file=$(ZK_Snapshot_Backup)
      ;;
    config)
      backup_file=$(ZK_Config_Backup)
      ;;
  esac
  
  [ -z "${backup_file}" ] && exit 1
  
  # 上传到远程存储
  local dest=${dest_override:-${backup_destination}}
  
  case "${dest}" in
    oss)
      Upload_To_OSS "${backup_file}"
      ;;
    s3)
      Upload_To_S3 "${backup_file}"
      ;;
    local)
      echo "Backup stored locally: ${backup_file}"
      ;;
  esac
  
  echo ""
  echo "${CSUCCESS}=== Backup Complete ===${CEND}"
}

main
