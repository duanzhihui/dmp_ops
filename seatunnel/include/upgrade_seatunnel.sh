#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Upgrade Module
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

Get_Current_Version() {
  if [ ! -d "${seatunnel_install_dir}/lib" ]; then
    echo ""
    return 1
  fi

  # Parse version from jar file name
  local version=$(ls ${seatunnel_install_dir}/lib/seatunnel-*.jar 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)
  echo "${version}"
}

Get_Latest_Version() {
  # Try to get latest version from Apache download page
  local latest=$(curl -s https://seatunnel.apache.org/download/ 2>/dev/null | grep -oP 'apache-seatunnel-\K\d+\.\d+\.\d+' | head -1)
  
  if [ -z "${latest}" ]; then
    # Fallback to versions.txt
    latest=${seatunnel_ver}
  fi
  
  echo "${latest}"
}

Validate_Version() {
  local old_ver=$1
  local new_ver=$2

  # Check if versions are the same
  if [ "${old_ver}" == "${new_ver}" ]; then
    echo "${CWARNING}Same version (${old_ver}), skip upgrade.${CEND}"
    return 1
  fi

  # Check major version compatibility (2.3.x)
  local old_major=$(echo "${old_ver}" | awk -F. '{print $1"."$2}')
  local new_major=$(echo "${new_ver}" | awk -F. '{print $1"."$2}')

  if [ "${old_major}" != "${new_major}" ]; then
    echo "${CWARNING}Major version mismatch: ${old_major} -> ${new_major}${CEND}"
    echo "${CWARNING}Cross-major-version upgrade may have compatibility issues.${CEND}"
    read -e -p "Continue anyway? [y/n]: " continue_upgrade
    if [[ ! "${continue_upgrade}" =~ ^[Yy]$ ]]; then
      return 1
    fi
  fi

  return 0
}

Backup_Before_Upgrade() {
  local backup_dir=${1:-/tmp/seatunnel_upgrade_backup_$(date +%Y%m%d%H%M%S)}
  
  echo "${CMSG}Creating backup at ${backup_dir}...${CEND}"
  mkdir -p ${backup_dir}

  # Backup config directory
  if [ -d "${seatunnel_install_dir}/config" ]; then
    cp -r ${seatunnel_install_dir}/config ${backup_dir}/
    echo "  - config/ backed up"
  fi

  # Backup connectors directory
  if [ -d "${seatunnel_install_dir}/connectors" ]; then
    cp -r ${seatunnel_install_dir}/connectors ${backup_dir}/
    echo "  - connectors/ backed up"
  fi

  # Backup plugins directory
  if [ -d "${seatunnel_install_dir}/plugins" ]; then
    cp -r ${seatunnel_install_dir}/plugins ${backup_dir}/
    echo "  - plugins/ backed up"
  fi

  echo "${CSUCCESS}Backup completed: ${backup_dir}${CEND}"
  echo "${backup_dir}"
}

Restore_After_Upgrade() {
  local backup_dir=$1

  if [ ! -d "${backup_dir}" ]; then
    echo "${CWARNING}Backup directory not found: ${backup_dir}${CEND}"
    return 1
  fi

  echo "${CMSG}Restoring configuration from backup...${CEND}"

  # Restore config (merge with new config)
  if [ -d "${backup_dir}/config" ]; then
    # Keep new default configs, only restore user-modified files
    for file in seatunnel.yaml hazelcast.yaml hazelcast-client.yaml jvm_options jvm_master_options jvm_worker_options jvm_client_options plugin_config; do
      if [ -f "${backup_dir}/config/${file}" ]; then
        cp ${backup_dir}/config/${file} ${seatunnel_install_dir}/config/
        echo "  - config/${file} restored"
      fi
    done
  fi

  # Restore connectors
  if [ -d "${backup_dir}/connectors" ]; then
    cp -r ${backup_dir}/connectors/* ${seatunnel_install_dir}/connectors/ 2>/dev/null
    echo "  - connectors/ restored"
  fi

  # Restore plugins
  if [ -d "${backup_dir}/plugins" ]; then
    cp -r ${backup_dir}/plugins/* ${seatunnel_install_dir}/plugins/ 2>/dev/null
    echo "  - plugins/ restored"
  fi

  echo "${CSUCCESS}Configuration restored!${CEND}"
}

Stop_SeaTunnel_Services() {
  echo "${CMSG}Stopping SeaTunnel services...${CEND}"
  
  systemctl stop seatunnel > /dev/null 2>&1
  systemctl stop seatunnel-master > /dev/null 2>&1
  systemctl stop seatunnel-worker > /dev/null 2>&1

  # Wait for processes to stop
  sleep 3

  # Check if any SeaTunnel process is still running
  if pgrep -f "seatunnel" > /dev/null 2>&1; then
    echo "${CWARNING}SeaTunnel processes still running. Force killing...${CEND}"
    pkill -9 -f "seatunnel"
    sleep 2
  fi

  echo "${CSUCCESS}SeaTunnel services stopped.${CEND}"
}

Start_SeaTunnel_Services() {
  echo "${CMSG}Starting SeaTunnel services...${CEND}"

  if [ "${deploy_mode}" == "hybrid" ]; then
    systemctl start seatunnel
    sleep 5
    if systemctl is-active --quiet seatunnel; then
      echo "${CSUCCESS}SeaTunnel service started successfully!${CEND}"
    else
      echo "${CFAILURE}Failed to start SeaTunnel service!${CEND}"
      return 1
    fi
  elif [ "${deploy_mode}" == "separated" ]; then
    if [ "${node_role}" == "master" ]; then
      systemctl start seatunnel-master
      sleep 5
      if systemctl is-active --quiet seatunnel-master; then
        echo "${CSUCCESS}SeaTunnel Master started successfully!${CEND}"
      else
        echo "${CFAILURE}Failed to start SeaTunnel Master!${CEND}"
        return 1
      fi
    elif [ "${node_role}" == "worker" ]; then
      systemctl start seatunnel-worker
      sleep 5
      if systemctl is-active --quiet seatunnel-worker; then
        echo "${CSUCCESS}SeaTunnel Worker started successfully!${CEND}"
      else
        echo "${CFAILURE}Failed to start SeaTunnel Worker!${CEND}"
        return 1
      fi
    fi
  fi

  return 0
}

Upgrade_SeaTunnel() {
  # 1. Check if SeaTunnel is installed
  if [ ! -e "${seatunnel_install_dir}/bin/seatunnel.sh" ]; then
    echo "${CWARNING}SeaTunnel is not installed!${CEND}"
    return 1
  fi

  # 2. Get current version
  local OLD_ver=$(Get_Current_Version)
  if [ -z "${OLD_ver}" ]; then
    echo "${CWARNING}Cannot detect current SeaTunnel version!${CEND}"
    return 1
  fi

  # 3. Get latest version
  local Latest_ver=$(Get_Latest_Version)

  echo
  echo "=========================================="
  echo "${CMSG}SeaTunnel Upgrade${CEND}"
  echo "=========================================="
  echo "Current Version: ${CMSG}${OLD_ver}${CEND}"
  echo "Latest Version:  ${CMSG}${Latest_ver}${CEND}"
  echo "=========================================="
  echo

  # 4. Prompt for target version
  read -e -p "Please input upgrade version (default: ${Latest_ver}): " NEW_ver
  NEW_ver=${NEW_ver:-${Latest_ver}}

  # 5. Validate version
  if ! Validate_Version "${OLD_ver}" "${NEW_ver}"; then
    return 1
  fi

  # 6. Warning about running jobs
  echo
  echo "${CWARNING}=== IMPORTANT ===${CEND}"
  echo "${CWARNING}Before upgrading, please ensure:${CEND}"
  echo "${CWARNING}1. All running jobs have been saved (savepoint)${CEND}"
  echo "${CWARNING}2. No critical jobs are currently running${CEND}"
  echo "${CWARNING}3. You have read the release notes for ${NEW_ver}${CEND}"
  echo
  read -e -p "Have you completed the above steps? [y/n]: " confirmed
  if [[ ! "${confirmed}" =~ ^[Yy]$ ]]; then
    echo "${CMSG}Upgrade cancelled.${CEND}"
    return 1
  fi

  # 7. Backup before upgrade
  local backup_dir=$(Backup_Before_Upgrade)

  # 8. Stop services
  Stop_SeaTunnel_Services

  # 9. Download new version
  echo "${CMSG}Downloading SeaTunnel ${NEW_ver}...${CEND}"
  pushd ${seatunnel_dir}/src > /dev/null
  Download_SeaTunnel ${NEW_ver}

  local tarball="apache-seatunnel-${NEW_ver}-bin.tar.gz"
  if [ ! -f "${tarball}" ]; then
    echo "${CFAILURE}Failed to download SeaTunnel ${NEW_ver}!${CEND}"
    echo "${CMSG}Restoring from backup...${CEND}"
    Start_SeaTunnel_Services
    popd > /dev/null
    return 1
  fi

  # 10. Remove old installation (keep data)
  echo "${CMSG}Removing old installation...${CEND}"
  rm -rf ${seatunnel_install_dir}

  # 11. Extract new version
  echo "${CMSG}Extracting SeaTunnel ${NEW_ver}...${CEND}"
  tar xzf ${tarball} -C $(dirname ${seatunnel_install_dir})
  mv $(dirname ${seatunnel_install_dir})/apache-seatunnel-${NEW_ver} ${seatunnel_install_dir}

  # 12. Restore configuration
  Restore_After_Upgrade ${backup_dir}

  # 13. Set permissions
  echo "${CMSG}Setting permissions...${CEND}"
  chown -R ${run_user}:${run_group} ${seatunnel_install_dir}

  # 14. Start services
  if ! Start_SeaTunnel_Services; then
    echo "${CFAILURE}Upgrade failed! Services did not start properly.${CEND}"
    echo "${CMSG}Backup is available at: ${backup_dir}${CEND}"
    popd > /dev/null
    return 1
  fi

  # 15. Verify upgrade
  local VERIFY_ver=$(Get_Current_Version)
  if [ "${VERIFY_ver}" == "${NEW_ver}" ]; then
    echo
    echo "${CSUCCESS}=========================================="
    echo "SeaTunnel upgraded successfully!"
    echo "  From: ${OLD_ver}"
    echo "  To:   ${NEW_ver}"
    echo "==========================================${CEND}"
    echo
    echo "${CMSG}Backup is available at: ${backup_dir}${CEND}"
    echo "${CMSG}You can delete it after verifying the upgrade.${CEND}"
    
    # Clean up downloaded tarball
    rm -f ${tarball}
  else
    echo "${CFAILURE}Upgrade verification failed!${CEND}"
    echo "${CMSG}Expected: ${NEW_ver}, Got: ${VERIFY_ver}${CEND}"
    echo "${CMSG}Backup is available at: ${backup_dir}${CEND}"
  fi

  popd > /dev/null
}

Rollback_SeaTunnel() {
  local backup_dir=$1

  if [ -z "${backup_dir}" ] || [ ! -d "${backup_dir}" ]; then
    echo "${CFAILURE}Please specify a valid backup directory!${CEND}"
    echo "Usage: Rollback_SeaTunnel /path/to/backup"
    return 1
  fi

  echo "${CMSG}Rolling back SeaTunnel from backup: ${backup_dir}${CEND}"

  # Stop services
  Stop_SeaTunnel_Services

  # Restore configuration
  Restore_After_Upgrade ${backup_dir}

  # Set permissions
  chown -R ${run_user}:${run_group} ${seatunnel_install_dir}

  # Start services
  Start_SeaTunnel_Services

  echo "${CSUCCESS}Rollback completed!${CEND}"
}
