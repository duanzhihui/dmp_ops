#!/bin/bash
# MySQL 备份执行脚本
# Author: DMP OPS
#
# 说明: 由 cron 定时调用的备份执行器，支持多种备份目标

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本所在目录
mysql_dir=$(dirname "$(readlink -f $0)")
pushd ${mysql_dir} > /dev/null

# 加载配置
. ./options.conf
. ./include/color.sh
. ./include/check_dir.sh

# 日志文件
LogFile=${backup_dir}/backup.log

# 确保备份目录存在
[ ! -d "${backup_dir}" ] && mkdir -p ${backup_dir}

# 记录日志
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> ${LogFile}
  echo "$1"
}

# 本地数据库备份
DB_Local_BK() {
  log "Starting local database backup..."
  
  for D in $(echo ${db_name} | tr ',' ' '); do
    log "Backing up database: ${D}"
    pushd ${mysql_dir}/tools > /dev/null
    ./db_bk.sh ${D}
    popd > /dev/null
  done
  
  log "Local database backup completed."
}

# 远程备份（rsync/scp）
DB_Remote_BK() {
  log "Starting remote database backup..."
  
  for D in $(echo ${db_name} | tr ',' ' '); do
    # 先执行本地备份
    pushd ${mysql_dir}/tools > /dev/null
    ./db_bk.sh ${D}
    popd > /dev/null
    
    # 查找最新的备份文件
    DB_GREP="DB_${D}_$(date +%Y%m%d)"
    DB_FILE=$(ls -lrt ${backup_dir} 2>/dev/null | grep ${DB_GREP} | tail -1 | awk '{print $NF}')
    
    if [ -n "${DB_FILE}" ] && [ -f "${backup_dir}/${DB_FILE}" ]; then
      # 使用 rsync 同步到远程
      rsync -avz -e "ssh -p ${remote_port}" ${backup_dir}/${DB_FILE} ${remote_user}@${remote_host}:${remote_dir}/
      
      if [ $? -eq 0 ]; then
        log "Remote backup success: ${DB_FILE}"
        
        # 清理远程过期备份
        ssh -p ${remote_port} ${remote_user}@${remote_host} "find ${remote_dir} -name 'DB_${D}_*.tgz' -mtime +${expired_days} -delete"
        
        # 如果不需要保留本地，删除本地文件
        if [ -z "$(echo ${backup_destination} | grep -ow 'local')" ]; then
          rm -f ${backup_dir}/${DB_FILE}
        fi
      else
        log "Remote backup failed: ${DB_FILE}"
      fi
    fi
  done
  
  log "Remote database backup completed."
}

# 阿里云 OSS 备份
DB_OSS_BK() {
  log "Starting OSS database backup..."
  
  # 检查 ossutil 是否安装
  if ! command -v ossutil >/dev/null 2>&1; then
    log "ERROR: ossutil is not installed"
    return 1
  fi
  
  for D in $(echo ${db_name} | tr ',' ' '); do
    # 先执行本地备份
    pushd ${mysql_dir}/tools > /dev/null
    ./db_bk.sh ${D}
    popd > /dev/null
    
    # 查找最新的备份文件
    DB_GREP="DB_${D}_$(date +%Y%m%d)"
    DB_FILE=$(ls -lrt ${backup_dir} 2>/dev/null | grep ${DB_GREP} | tail -1 | awk '{print $NF}')
    
    if [ -n "${DB_FILE}" ] && [ -f "${backup_dir}/${DB_FILE}" ]; then
      # 上传到 OSS
      ossutil cp -f ${backup_dir}/${DB_FILE} oss://${oss_bucket}/mysql_backup/$(date +%F)/${DB_FILE}
      
      if [ $? -eq 0 ]; then
        log "OSS backup success: ${DB_FILE}"
        
        # 清理过期备份
        ossutil rm -rf oss://${oss_bucket}/mysql_backup/$(date +%F --date="${expired_days} days ago")/ 2>/dev/null
        
        # 如果不需要保留本地，删除本地文件
        if [ -z "$(echo ${backup_destination} | grep -ow 'local')" ]; then
          rm -f ${backup_dir}/${DB_FILE}
        fi
      else
        log "OSS backup failed: ${DB_FILE}"
      fi
    fi
  done
  
  log "OSS database backup completed."
}

# 腾讯云 COS 备份
DB_COS_BK() {
  log "Starting COS database backup..."
  
  # 检查 coscmd 是否安装
  if ! command -v coscmd >/dev/null 2>&1; then
    log "ERROR: coscmd is not installed"
    return 1
  fi
  
  for D in $(echo ${db_name} | tr ',' ' '); do
    pushd ${mysql_dir}/tools > /dev/null
    ./db_bk.sh ${D}
    popd > /dev/null
    
    DB_GREP="DB_${D}_$(date +%Y%m%d)"
    DB_FILE=$(ls -lrt ${backup_dir} 2>/dev/null | grep ${DB_GREP} | tail -1 | awk '{print $NF}')
    
    if [ -n "${DB_FILE}" ] && [ -f "${backup_dir}/${DB_FILE}" ]; then
      coscmd upload ${backup_dir}/${DB_FILE} /mysql_backup/$(date +%F)/${DB_FILE}
      
      if [ $? -eq 0 ]; then
        log "COS backup success: ${DB_FILE}"
        if [ -z "$(echo ${backup_destination} | grep -ow 'local')" ]; then
          rm -f ${backup_dir}/${DB_FILE}
        fi
      else
        log "COS backup failed: ${DB_FILE}"
      fi
    fi
  done
  
  log "COS database backup completed."
}

# AWS S3 备份
DB_S3_BK() {
  log "Starting S3 database backup..."
  
  # 检查 aws cli 是否安装
  if ! command -v aws >/dev/null 2>&1; then
    log "ERROR: aws cli is not installed"
    return 1
  fi
  
  for D in $(echo ${db_name} | tr ',' ' '); do
    pushd ${mysql_dir}/tools > /dev/null
    ./db_bk.sh ${D}
    popd > /dev/null
    
    DB_GREP="DB_${D}_$(date +%Y%m%d)"
    DB_FILE=$(ls -lrt ${backup_dir} 2>/dev/null | grep ${DB_GREP} | tail -1 | awk '{print $NF}')
    
    if [ -n "${DB_FILE}" ] && [ -f "${backup_dir}/${DB_FILE}" ]; then
      aws s3 cp ${backup_dir}/${DB_FILE} s3://${s3_bucket}/mysql_backup/$(date +%F)/${DB_FILE}
      
      if [ $? -eq 0 ]; then
        log "S3 backup success: ${DB_FILE}"
        if [ -z "$(echo ${backup_destination} | grep -ow 'local')" ]; then
          rm -f ${backup_dir}/${DB_FILE}
        fi
      else
        log "S3 backup failed: ${DB_FILE}"
      fi
    fi
  done
  
  log "S3 database backup completed."
}

# 主逻辑
main() {
  log "========== MySQL Backup Started =========="
  
  # 检查配置
  if [ -z "${db_name}" ]; then
    log "ERROR: No database specified in options.conf (db_name)"
    exit 1
  fi
  
  if [ -z "${backup_destination}" ]; then
    log "WARNING: No backup destination specified, using 'local'"
    backup_destination="local"
  fi
  
  # 按目标分发备份
  for DEST in $(echo ${backup_destination} | tr ',' ' '); do
    case "${DEST}" in
      local)
        DB_Local_BK
        ;;
      remote)
        DB_Remote_BK
        ;;
      oss)
        DB_OSS_BK
        ;;
      cos)
        DB_COS_BK
        ;;
      s3)
        DB_S3_BK
        ;;
      *)
        log "WARNING: Unknown backup destination: ${DEST}"
        ;;
    esac
  done
  
  log "========== MySQL Backup Completed =========="
}

# 执行
main

popd > /dev/null
