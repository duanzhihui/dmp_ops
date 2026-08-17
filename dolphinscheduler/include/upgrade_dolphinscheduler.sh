#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Upgrade functions

# Upgrade DolphinScheduler
Upgrade_DolphinScheduler() {
  local new_ver=$1

  echo "${CMSG}Upgrading DolphinScheduler to ${new_ver}...${CEND}"

  # Check if DolphinScheduler is installed
  if [ ! -d "${dolphinscheduler_install_dir}" ]; then
    echo "${CFAILURE}DolphinScheduler is not installed!${CEND}"
    return 1
  fi

  # Get current version
  local current_ver=""
  if [ -f "${dolphinscheduler_install_dir}/VERSION" ]; then
    current_ver=$(cat ${dolphinscheduler_install_dir}/VERSION 2>/dev/null)
  fi

  if [ -z "${current_ver}" ]; then
    echo "${CWARNING}Cannot detect current version. Proceeding with upgrade...${CEND}"
  else
    echo "${CMSG}Current version: ${current_ver}${CEND}"
    echo "${CMSG}Target version: ${new_ver}${CEND}"

    if [ "${current_ver}" == "${new_ver}" ]; then
      echo "${CWARNING}Already running version ${new_ver}. Nothing to upgrade.${CEND}"
      return 0
    fi

    # Check version compatibility (major version must match)
    local current_major=${current_ver%%.*}
    local new_major=${new_ver%%.*}
    if [ "${current_major}" != "${new_major}" ]; then
      echo "${CWARNING}Warning: Upgrading across major versions (${current_major}.x -> ${new_major}.x)${CEND}"
      echo "${CWARNING}This may require additional migration steps.${CEND}"
      read -e -p "Continue? [y/n]: " confirm
      if [ "${confirm}" != "y" ]; then
        echo "Upgrade cancelled."
        return 0
      fi
    fi
  fi

  # Backup before upgrade
  Backup_Before_Upgrade

  # Stop all services
  echo "${CMSG}Stopping DolphinScheduler services...${CEND}"
  systemctl stop dolphinscheduler-standalone 2>/dev/null
  systemctl stop dolphinscheduler-master 2>/dev/null
  systemctl stop dolphinscheduler-worker 2>/dev/null
  systemctl stop dolphinscheduler-api 2>/dev/null
  systemctl stop dolphinscheduler-alert 2>/dev/null

  # Download new version
  echo "${CMSG}Downloading DolphinScheduler ${new_ver}...${CEND}"
  Download_DolphinScheduler "${new_ver}"

  # Backup current installation
  local backup_dir="${dolphinscheduler_install_dir}_backup_$(date +%Y%m%d%H%M%S)"
  echo "${CMSG}Backing up current installation to ${backup_dir}...${CEND}"
  mv ${dolphinscheduler_install_dir} ${backup_dir}

  # Extract new version
  local ds_pkg=$(Get_DolphinScheduler_Pkg "${new_ver}")
  mkdir -p ${dolphinscheduler_install_dir}
  tar xzf ${ds_dir}/src/${ds_pkg} -C ${dolphinscheduler_install_dir} --strip-components=1

  # Restore configuration files
  echo "${CMSG}Restoring configuration files...${CEND}"
  if [ -f "${backup_dir}/bin/env/dolphinscheduler_env.sh" ]; then
    cp -f ${backup_dir}/bin/env/dolphinscheduler_env.sh ${dolphinscheduler_install_dir}/bin/env/
  fi
  if [ -f "${backup_dir}/bin/env/install_env.sh" ]; then
    cp -f ${backup_dir}/bin/env/install_env.sh ${dolphinscheduler_install_dir}/bin/env/
  fi

  # Restore application.yaml files
  for module in alert-server api-server master-server worker-server; do
    if [ -f "${backup_dir}/${module}/conf/application.yaml" ]; then
      cp -f ${backup_dir}/${module}/conf/application.yaml ${dolphinscheduler_install_dir}/${module}/conf/
    fi
  done

  # Restore MySQL JDBC driver if exists
  if [ "${db_type}" == "mysql" ]; then
    for module in tools/libs alert-server/libs api-server/libs master-server/libs worker-server/libs; do
      local jdbc_jar=$(ls ${backup_dir}/${module}/mysql-connector-*.jar 2>/dev/null | head -1)
      if [ -n "${jdbc_jar}" ]; then
        cp -f ${jdbc_jar} ${dolphinscheduler_install_dir}/${module}/
      fi
    done
  fi

  # Run database upgrade script
  echo "${CMSG}Running database upgrade script...${CEND}"
  if [ -f "${dolphinscheduler_install_dir}/tools/bin/upgrade-schema.sh" ]; then
    pushd ${dolphinscheduler_install_dir}/tools > /dev/null
    source ${dolphinscheduler_install_dir}/bin/env/dolphinscheduler_env.sh
    bash bin/upgrade-schema.sh
    popd > /dev/null
  fi

  # Set ownership
  chown -R ${run_user}:${run_group} ${dolphinscheduler_install_dir}

  # Start services (only the roles installed on this node)
  echo "${CMSG}Starting DolphinScheduler services...${CEND}"
  if [ -f "/lib/systemd/system/dolphinscheduler-standalone.service" ]; then
    systemctl start dolphinscheduler-standalone
  else
    for role in $(Installed_Cluster_Roles); do
      systemctl start dolphinscheduler-${role}
      sleep 3
    done
  fi

  # Verify upgrade
  sleep 5
  echo "${CMSG}Verifying upgrade...${CEND}"
  Show_Cluster_Status

  echo "${CSUCCESS}DolphinScheduler upgraded to ${new_ver} successfully!${CEND}"
  echo "${CMSG}Backup saved at: ${backup_dir}${CEND}"
}

# Backup before upgrade
Backup_Before_Upgrade() {
  local backup_time=$(date +%Y%m%d%H%M%S)
  local backup_path="${backup_dir:-/data/backup/dolphinscheduler}/upgrade_${backup_time}"

  echo "${CMSG}Creating pre-upgrade backup at ${backup_path}...${CEND}"
  mkdir -p ${backup_path}

  # Backup database
  if [ "${db_type}" == "mysql" ]; then
    if command -v mysqldump > /dev/null 2>&1; then
      echo "${CMSG}Backing up MySQL database...${CEND}"
      mysqldump -h${db_host} -P${db_port} -u${db_user} -p"${db_password}" --databases ${db_name} > ${backup_path}/database_backup.sql
      if [ $? -eq 0 ]; then
        gzip ${backup_path}/database_backup.sql
        echo "${CSUCCESS}Database backup completed: ${backup_path}/database_backup.sql.gz${CEND}"
      fi
    fi
  elif [ "${db_type}" == "postgresql" ]; then
    if command -v pg_dump > /dev/null 2>&1; then
      echo "${CMSG}Backing up PostgreSQL database...${CEND}"
      PGPASSWORD="${db_password}" pg_dump -h ${db_host} -p ${db_port} -U ${db_user} ${db_name} > ${backup_path}/database_backup.sql
      if [ $? -eq 0 ]; then
        gzip ${backup_path}/database_backup.sql
        echo "${CSUCCESS}Database backup completed: ${backup_path}/database_backup.sql.gz${CEND}"
      fi
    fi
  fi

  # Backup configuration files
  echo "${CMSG}Backing up configuration files...${CEND}"
  tar czf ${backup_path}/config_backup.tar.gz \
    ${dolphinscheduler_install_dir}/bin/env/*.sh \
    ${dolphinscheduler_install_dir}/*/conf/*.yaml \
    2>/dev/null

  echo "${CSUCCESS}Pre-upgrade backup completed at ${backup_path}${CEND}"
}

# Get latest version from Apache
Get_Latest_Version() {
  echo "${CMSG}Checking latest DolphinScheduler version...${CEND}"

  # Try to get from Apache downloads page
  local latest_ver=$(curl -s https://downloads.apache.org/dolphinscheduler/ 2>/dev/null | grep -oP '(?<=href=")[0-9]+\.[0-9]+\.[0-9]+(?=/")' | sort -V | tail -1)

  if [ -n "${latest_ver}" ]; then
    echo "${CSUCCESS}Latest version: ${latest_ver}${CEND}"
    echo "${latest_ver}"
  else
    echo "${CWARNING}Could not determine latest version.${CEND}"
    echo ""
  fi
}

# Rollback to previous version
Rollback_Upgrade() {
  local backup_dir=$1

  if [ -z "${backup_dir}" ] || [ ! -d "${backup_dir}" ]; then
    echo "${CFAILURE}Backup directory not found!${CEND}"
    echo "Usage: Rollback_Upgrade /path/to/backup_dir"
    return 1
  fi

  echo "${CMSG}Rolling back to backup: ${backup_dir}${CEND}"

  # Stop services
  systemctl stop dolphinscheduler-standalone 2>/dev/null
  systemctl stop dolphinscheduler-master 2>/dev/null
  systemctl stop dolphinscheduler-worker 2>/dev/null
  systemctl stop dolphinscheduler-api 2>/dev/null
  systemctl stop dolphinscheduler-alert 2>/dev/null

  # Remove current installation
  rm -rf ${dolphinscheduler_install_dir}

  # Restore from backup
  mv ${backup_dir} ${dolphinscheduler_install_dir}

  # Set ownership
  chown -R ${run_user}:${run_group} ${dolphinscheduler_install_dir}

  # Start services (only the roles installed on this node)
  if [ -f "/lib/systemd/system/dolphinscheduler-standalone.service" ]; then
    systemctl start dolphinscheduler-standalone
  else
    for role in $(Installed_Cluster_Roles); do
      systemctl start dolphinscheduler-${role}
      sleep 3
    done
  fi

  echo "${CSUCCESS}Rollback completed!${CEND}"
}
