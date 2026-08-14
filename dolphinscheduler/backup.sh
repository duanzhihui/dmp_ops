#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Backup script
#
# Supports: Database backup, Configuration backup, Log backup
# Destinations: local, oss, s3

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

ds_dir=$(dirname "$(readlink -f $0)")
pushd ${ds_dir} > /dev/null
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${ds_dir}"
. ./options.conf
. ./include/color.sh

# Backup timestamp
backup_time=$(date +%Y%m%d_%H%M%S)
backup_date=$(date +%Y%m%d)

# Create backup directory
mkdir -p ${backup_dir}/${backup_date}

# Backup database
Backup_Database() {
  echo "${CMSG}Backing up database...${CEND}"

  local db_backup_file="${backup_dir}/${backup_date}/db_${db_name}_${backup_time}.sql"

  if [ "${db_type}" == "mysql" ]; then
    if command -v mysqldump > /dev/null 2>&1; then
      mysqldump -h${db_host} -P${db_port} -u${db_user} -p"${db_password}" \
        --databases ${db_name} \
        --single-transaction \
        --quick \
        --lock-tables=false \
        > ${db_backup_file}

      if [ $? -eq 0 ]; then
        gzip ${db_backup_file}
        echo "${CSUCCESS}Database backup completed: ${db_backup_file}.gz${CEND}"
      else
        echo "${CFAILURE}Database backup failed!${CEND}"
        return 1
      fi
    else
      echo "${CWARNING}mysqldump not found. Skipping database backup.${CEND}"
    fi
  elif [ "${db_type}" == "postgresql" ]; then
    if command -v pg_dump > /dev/null 2>&1; then
      PGPASSWORD="${db_password}" pg_dump \
        -h ${db_host} \
        -p ${db_port} \
        -U ${db_user} \
        -d ${db_name} \
        > ${db_backup_file}

      if [ $? -eq 0 ]; then
        gzip ${db_backup_file}
        echo "${CSUCCESS}Database backup completed: ${db_backup_file}.gz${CEND}"
      else
        echo "${CFAILURE}Database backup failed!${CEND}"
        return 1
      fi
    else
      echo "${CWARNING}pg_dump not found. Skipping database backup.${CEND}"
    fi
  fi
}

# Backup configuration files
Backup_Config() {
  echo "${CMSG}Backing up configuration files...${CEND}"

  local config_backup_file="${backup_dir}/${backup_date}/config_${backup_time}.tar.gz"

  if [ -d "${dolphinscheduler_install_dir}" ]; then
    tar czf ${config_backup_file} \
      ${dolphinscheduler_install_dir}/bin/env/*.sh \
      ${dolphinscheduler_install_dir}/*/conf/*.yaml \
      ${dolphinscheduler_install_dir}/*/conf/*.properties \
      2>/dev/null

    if [ $? -eq 0 ]; then
      echo "${CSUCCESS}Configuration backup completed: ${config_backup_file}${CEND}"
    else
      echo "${CWARNING}Some configuration files may not exist.${CEND}"
    fi
  else
    echo "${CWARNING}DolphinScheduler installation directory not found.${CEND}"
  fi
}

# Backup logs
Backup_Logs() {
  echo "${CMSG}Backing up log files...${CEND}"

  local log_backup_file="${backup_dir}/${backup_date}/logs_${backup_time}.tar.gz"

  if [ -d "${dolphinscheduler_log_dir}" ]; then
    tar czf ${log_backup_file} ${dolphinscheduler_log_dir} 2>/dev/null

    if [ $? -eq 0 ]; then
      echo "${CSUCCESS}Log backup completed: ${log_backup_file}${CEND}"
    else
      echo "${CWARNING}Log backup may be incomplete.${CEND}"
    fi
  elif [ -d "${dolphinscheduler_install_dir}/standalone-server/logs" ]; then
    tar czf ${log_backup_file} ${dolphinscheduler_install_dir}/*/logs 2>/dev/null
    echo "${CSUCCESS}Log backup completed: ${log_backup_file}${CEND}"
  else
    echo "${CWARNING}Log directory not found.${CEND}"
  fi
}

# Clean old backups
Clean_Old_Backups() {
  echo "${CMSG}Cleaning old backups (older than ${expired_days} days)...${CEND}"

  local old_date=$(date +%Y%m%d --date="${expired_days} days ago")

  # Find and remove old backup directories
  for dir in ${backup_dir}/*/; do
    local dir_date=$(basename ${dir})
    if [[ "${dir_date}" =~ ^[0-9]{8}$ ]] && [ "${dir_date}" -lt "${old_date}" ]; then
      echo "Removing old backup: ${dir}"
      rm -rf ${dir}
    fi
  done

  echo "${CSUCCESS}Old backups cleaned.${CEND}"
}

# Upload to OSS (Aliyun)
Upload_To_OSS() {
  local file=$1

  if [ -z "${oss_bucket}" ]; then
    echo "${CWARNING}OSS bucket not configured. Skipping OSS upload.${CEND}"
    return 1
  fi

  if ! command -v ossutil > /dev/null 2>&1; then
    echo "${CWARNING}ossutil not found. Skipping OSS upload.${CEND}"
    return 1
  fi

  echo "${CMSG}Uploading to OSS: ${file}${CEND}"
  ossutil cp -f ${file} oss://${oss_bucket}/dolphinscheduler/${backup_date}/

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Uploaded to OSS successfully.${CEND}"
    # Clean old OSS backups
    local old_date=$(date +%Y%m%d --date="${expired_days} days ago")
    ossutil rm -rf oss://${oss_bucket}/dolphinscheduler/${old_date}/ 2>/dev/null
  else
    echo "${CFAILURE}OSS upload failed!${CEND}"
    return 1
  fi
}

# Upload to S3 (AWS)
Upload_To_S3() {
  local file=$1

  if [ -z "${s3_bucket}" ]; then
    echo "${CWARNING}S3 bucket not configured. Skipping S3 upload.${CEND}"
    return 1
  fi

  if ! command -v aws > /dev/null 2>&1; then
    echo "${CWARNING}AWS CLI not found. Skipping S3 upload.${CEND}"
    return 1
  fi

  echo "${CMSG}Uploading to S3: ${file}${CEND}"
  aws s3 cp ${file} s3://${s3_bucket}/dolphinscheduler/${backup_date}/

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Uploaded to S3 successfully.${CEND}"
  else
    echo "${CFAILURE}S3 upload failed!${CEND}"
    return 1
  fi
}

# Main backup logic
Main() {
  echo ""
  echo "${CMSG}========== DolphinScheduler Backup ==========${CEND}"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Backup directory: ${backup_dir}/${backup_date}"
  echo ""

  # Parse backup content
  local backup_content_arr=(${backup_content//,/ })

  for content in "${backup_content_arr[@]}"; do
    case "${content}" in
      db)
        Backup_Database
        ;;
      config)
        Backup_Config
        ;;
      logs)
        Backup_Logs
        ;;
    esac
  done

  # Upload to cloud storage
  local backup_dest_arr=(${backup_destination//,/ })

  for dest in "${backup_dest_arr[@]}"; do
    case "${dest}" in
      oss)
        for file in ${backup_dir}/${backup_date}/*; do
          Upload_To_OSS "${file}"
        done
        ;;
      s3)
        for file in ${backup_dir}/${backup_date}/*; do
          Upload_To_S3 "${file}"
        done
        ;;
    esac
  done

  # Clean old backups
  Clean_Old_Backups

  echo ""
  echo "${CSUCCESS}========== Backup Completed ==========${CEND}"
  echo "Backup files:"
  ls -lh ${backup_dir}/${backup_date}/
  echo ""
}

Main
popd > /dev/null
