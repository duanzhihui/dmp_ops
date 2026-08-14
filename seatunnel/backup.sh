#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Backup Script
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# Get script directory
seatunnel_dir=$(dirname $(readlink -f $0))
pushd ${seatunnel_dir} > /dev/null

# Source configuration
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${seatunnel_dir}"
. ./options.conf
. ./versions.txt
. ./include/color.sh

# Logging
log_file=${backup_dir}/backup.log
mkdir -p ${backup_dir}

log() {
  local message=$1
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${timestamp}] ${message}" | tee -a ${log_file}
}

# Backup functions
Backup_Config() {
  local backup_file=${backup_dir}/seatunnel_config_$(date +%Y%m%d_%H%M%S).tgz
  
  log "Backing up config directory..."
  
  if [ -d "${seatunnel_install_dir}/config" ]; then
    tar czf ${backup_file} -C ${seatunnel_install_dir} config
    if [ $? -eq 0 ]; then
      log "Config backup created: ${backup_file}"
      echo "${backup_file}"
      return 0
    else
      log "ERROR: Failed to backup config"
      return 1
    fi
  else
    log "WARNING: Config directory not found"
    return 1
  fi
}

Backup_Connectors() {
  local backup_file=${backup_dir}/seatunnel_connectors_$(date +%Y%m%d_%H%M%S).tgz
  
  log "Backing up connectors directory..."
  
  if [ -d "${seatunnel_install_dir}/connectors" ]; then
    tar czf ${backup_file} -C ${seatunnel_install_dir} connectors
    if [ $? -eq 0 ]; then
      log "Connectors backup created: ${backup_file}"
      echo "${backup_file}"
      return 0
    else
      log "ERROR: Failed to backup connectors"
      return 1
    fi
  else
    log "WARNING: Connectors directory not found"
    return 1
  fi
}

Backup_Jobs() {
  local backup_file=${backup_dir}/seatunnel_jobs_$(date +%Y%m%d_%H%M%S).tgz
  local jobs_dir=${seatunnel_install_dir}/jobs
  
  log "Backing up jobs directory..."
  
  if [ -d "${jobs_dir}" ]; then
    tar czf ${backup_file} -C ${seatunnel_install_dir} jobs
    if [ $? -eq 0 ]; then
      log "Jobs backup created: ${backup_file}"
      echo "${backup_file}"
      return 0
    else
      log "ERROR: Failed to backup jobs"
      return 1
    fi
  else
    log "INFO: Jobs directory not found, skipping"
    return 0
  fi
}

Backup_Full() {
  local backup_file=${backup_dir}/seatunnel_backup_$(date +%Y%m%d_%H%M%S).tgz
  
  log "Creating full backup..."
  
  local items=""
  [ -d "${seatunnel_install_dir}/config" ] && items="${items} config"
  [ -d "${seatunnel_install_dir}/connectors" ] && items="${items} connectors"
  [ -d "${seatunnel_install_dir}/plugins" ] && items="${items} plugins"
  [ -d "${seatunnel_install_dir}/jobs" ] && items="${items} jobs"
  
  if [ -n "${items}" ]; then
    tar czf ${backup_file} -C ${seatunnel_install_dir} ${items}
    if [ $? -eq 0 ]; then
      log "Full backup created: ${backup_file}"
      echo "${backup_file}"
      return 0
    else
      log "ERROR: Failed to create full backup"
      return 1
    fi
  else
    log "WARNING: No directories to backup"
    return 1
  fi
}

# Clean old backups
Clean_Old_Backups() {
  local days=${expired_days:-7}
  
  log "Cleaning backups older than ${days} days..."
  
  find ${backup_dir} -name "seatunnel_*.tgz" -mtime +${days} -delete 2>/dev/null
  
  local deleted_count=$(find ${backup_dir} -name "seatunnel_*.tgz" -mtime +${days} 2>/dev/null | wc -l)
  log "Cleaned ${deleted_count} old backup files"
}

# Upload to remote/cloud
Upload_To_Remote() {
  local backup_file=$1
  
  if [ -z "${remote_host}" ] || [ -z "${remote_user}" ] || [ -z "${remote_dir}" ]; then
    log "Remote backup not configured, skipping"
    return 0
  fi
  
  log "Uploading to remote: ${remote_user}@${remote_host}:${remote_dir}"
  
  scp ${backup_file} ${remote_user}@${remote_host}:${remote_dir}/
  if [ $? -eq 0 ]; then
    log "Remote upload successful"
    return 0
  else
    log "ERROR: Remote upload failed"
    return 1
  fi
}

Upload_To_OSS() {
  local backup_file=$1
  
  if [ -z "${oss_bucket}" ]; then
    log "OSS backup not configured, skipping"
    return 0
  fi
  
  log "Uploading to OSS: oss://${oss_bucket}"
  
  if command -v ossutil > /dev/null 2>&1; then
    ossutil cp -f ${backup_file} oss://${oss_bucket}/seatunnel/$(date +%F)/
    if [ $? -eq 0 ]; then
      log "OSS upload successful"
      # Clean old OSS backups
      ossutil rm -rf oss://${oss_bucket}/seatunnel/$(date +%F --date="${expired_days} days ago")/ 2>/dev/null
      return 0
    else
      log "ERROR: OSS upload failed"
      return 1
    fi
  else
    log "WARNING: ossutil not found, skipping OSS upload"
    return 1
  fi
}

Upload_To_S3() {
  local backup_file=$1
  
  if [ -z "${s3_bucket}" ]; then
    log "S3 backup not configured, skipping"
    return 0
  fi
  
  log "Uploading to S3: s3://${s3_bucket}"
  
  if command -v aws > /dev/null 2>&1; then
    aws s3 cp ${backup_file} s3://${s3_bucket}/seatunnel/$(date +%F)/
    if [ $? -eq 0 ]; then
      log "S3 upload successful"
      return 0
    else
      log "ERROR: S3 upload failed"
      return 1
    fi
  else
    log "WARNING: aws cli not found, skipping S3 upload"
    return 1
  fi
}

# Main backup logic
Main_Backup() {
  log "========== Starting SeaTunnel Backup =========="
  
  local backup_files=()
  
  # Backup based on content configuration
  for content in $(echo ${backup_content} | tr ',' ' '); do
    case "${content}" in
      config)
        local file=$(Backup_Config)
        [ -n "${file}" ] && backup_files+=("${file}")
        ;;
      connectors)
        local file=$(Backup_Connectors)
        [ -n "${file}" ] && backup_files+=("${file}")
        ;;
      jobs)
        local file=$(Backup_Jobs)
        [ -n "${file}" ] && backup_files+=("${file}")
        ;;
      full)
        local file=$(Backup_Full)
        [ -n "${file}" ] && backup_files+=("${file}")
        ;;
    esac
  done
  
  # Upload to destinations
  for dest in $(echo ${backup_destination} | tr ',' ' '); do
    case "${dest}" in
      local)
        log "Local backup completed"
        ;;
      remote)
        for file in "${backup_files[@]}"; do
          Upload_To_Remote "${file}"
        done
        ;;
      oss)
        for file in "${backup_files[@]}"; do
          Upload_To_OSS "${file}"
        done
        ;;
      s3)
        for file in "${backup_files[@]}"; do
          Upload_To_S3 "${file}"
        done
        ;;
    esac
  done
  
  # Clean old backups
  Clean_Old_Backups
  
  log "========== Backup Completed =========="
}

# Run backup
Main_Backup

popd > /dev/null
