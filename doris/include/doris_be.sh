#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# BE (Backend) node installation and management
#
# Unified package: apache-doris-<ver>-bin-<arch>.tar.gz contains be/ subdir

Install_BE() {
  local doris_ver=$1
  local major_ver=${doris_ver%%.*}

  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Installing Doris BE ${doris_ver}${CEND}"
  echo "${CMSG}============================================${CEND}"

  # Check if BE already installed
  if [ -e "${be_install_dir}/bin/start_be.sh" ]; then
    echo "${CWARNING}Doris BE already installed at ${be_install_dir}${CEND}"
    return 1
  fi

  # Create directories
  mkdir -p ${be_install_dir}
  mkdir -p ${be_data_dir}
  mkdir -p ${be_log_dir}

  # Extract be/ from unified package
  Extract_Component "${doris_ver}" "be" "${be_install_dir}" || return 1

  # Configure BE
  Configure_BE

  # Create symlink for storage directory
  if [ -d "${be_install_dir}/storage" ]; then
    rm -rf ${be_install_dir}/storage
  fi
  ln -sf ${be_data_dir} ${be_install_dir}/storage

  # Create symlink for log directory
  if [ -d "${be_install_dir}/log" ]; then
    rm -rf ${be_install_dir}/log
  fi
  ln -sf ${be_log_dir} ${be_install_dir}/log

  # Set ownership
  chown -R ${run_user}:${run_group} ${be_install_dir}
  chown -R ${run_user}:${run_group} ${be_data_dir}
  chown -R ${run_user}:${run_group} ${be_log_dir}

  # Install systemd service
  Install_BE_Service

  echo "${CSUCCESS}Doris BE ${doris_ver} installed successfully!${CEND}"
  echo "${CSUCCESS}BE install dir: ${be_install_dir}${CEND}"
  echo "${CSUCCESS}BE data dir: ${be_data_dir}${CEND}"
  echo "${CSUCCESS}BE log dir: ${be_log_dir}${CEND}"
}

Configure_BE() {
  local be_conf="${be_install_dir}/conf/be.conf"

  if [ ! -f "${be_conf}" ]; then
    cp ${doris_dir}/config/be.conf ${be_conf}
  fi

  # Set JAVA_HOME
  if [ -n "${JAVA_HOME}" ]; then
    if grep -q "^JAVA_HOME" ${be_conf}; then
      sed -i "s|^JAVA_HOME.*|JAVA_HOME = ${JAVA_HOME}|" ${be_conf}
    else
      sed -i "1a JAVA_HOME = ${JAVA_HOME}" ${be_conf}
    fi
  fi

  # Set priority_networks
  if [ -n "${priority_networks}" ]; then
    if grep -q "^priority_networks" ${be_conf}; then
      sed -i "s|^priority_networks.*|priority_networks = ${priority_networks}|" ${be_conf}
    elif grep -q "^# priority_networks" ${be_conf}; then
      sed -i "s|^# priority_networks.*|priority_networks = ${priority_networks}|" ${be_conf}
    else
      echo "priority_networks = ${priority_networks}" >> ${be_conf}
    fi
  fi

  # Set storage_root_path (存算一体 mode uses local storage)
  if [ "${deploy_mode}" != "separated" ]; then
    if grep -q "^storage_root_path" ${be_conf}; then
      sed -i "s|^storage_root_path.*|storage_root_path = ${be_data_dir},medium:${be_storage_medium}|" ${be_conf}
    else
      echo "storage_root_path = ${be_data_dir},medium:${be_storage_medium}" >> ${be_conf}
    fi
  fi

  # Set BE ports
  if grep -q "^heartbeat_service_port" ${be_conf}; then
    sed -i "s|^heartbeat_service_port.*|heartbeat_service_port = ${be_heartbeat_service_port}|" ${be_conf}
  fi

  if grep -q "^brpc_port" ${be_conf}; then
    sed -i "s|^brpc_port.*|brpc_port = ${be_brpc_port}|" ${be_conf}
  fi

  if grep -q "^webserver_port" ${be_conf}; then
    sed -i "s|^webserver_port.*|webserver_port = ${be_webserver_port}|" ${be_conf}
  fi

  echo "${CSUCCESS}BE configuration updated: ${be_conf}${CEND}"
}

Install_BE_Service() {
  cp ${doris_dir}/init.d/doris-be.service /lib/systemd/system/doris-be.service
  sed -i "s|@RUN_USER@|${run_user}|g" /lib/systemd/system/doris-be.service
  sed -i "s|@RUN_GROUP@|${run_group}|g" /lib/systemd/system/doris-be.service
  sed -i "s|@BE_INSTALL_DIR@|${be_install_dir}|g" /lib/systemd/system/doris-be.service
  sed -i "s|@JAVA_HOME@|${JAVA_HOME}|g" /lib/systemd/system/doris-be.service
  systemctl daemon-reload
  systemctl enable doris-be
  echo "${CSUCCESS}Doris BE systemd service installed.${CEND}"
}

Start_BE() {
  echo "${CMSG}Starting Doris BE...${CEND}"

  # Ensure swap is disabled (BE refuses to start with swap on)
  local swap_total=$(free -m | grep Swap | awk '{print $2}')
  if [ ${swap_total} -gt 0 ]; then
    echo "${CWARNING}Swap still enabled, disabling before BE start...${CEND}"
    swapoff -a
  fi

  su - ${run_user} -s /bin/bash -c "export JAVA_HOME=${JAVA_HOME} && ${be_install_dir}/bin/start_be.sh --daemon"

  # BE loads tablet meta on startup, retry for up to 60s
  local retry=0
  while [ ${retry} -lt 12 ]; do
    if BE_Process_Alive; then
      echo "${CSUCCESS}Doris BE started successfully!${CEND}"
      return 0
    fi
    sleep 5
    retry=$((retry + 1))
  done

  echo "${CFAILURE}Doris BE start failed! Check log: ${be_log_dir}/be.INFO${CEND}"
  return 1
}

Stop_BE() {
  echo "${CMSG}Stopping Doris BE...${CEND}"
  if [ -x "${be_install_dir}/bin/stop_be.sh" ]; then
    su - ${run_user} -s /bin/bash -c "${be_install_dir}/bin/stop_be.sh"
  fi
  sleep 2
  echo "${CSUCCESS}Doris BE stopped.${CEND}"
}

BE_Process_Alive() {
  local pid_file="${be_install_dir}/bin/be.pid"
  if [ -f "${pid_file}" ]; then
    local pid=$(cat ${pid_file} 2>/dev/null)
    [ -n "${pid}" ] && kill -0 ${pid} 2>/dev/null && return 0
  fi
  ps aux | grep -v grep | grep -q "${be_install_dir}/lib/doris_be" && return 0
  return 1
}

Check_BE_Status() {
  if BE_Process_Alive; then
    echo "${CSUCCESS}Doris BE is running.${CEND}"
    return 0
  else
    echo "${CWARNING}Doris BE is not running.${CEND}"
    return 1
  fi
}

Register_BE() {
  local fe_ip=$1
  local be_ip=$2
  local be_port=${3:-${be_heartbeat_service_port}}

  echo "${CMSG}Registering BE node: ${be_ip}:${be_port}${CEND}"
  local output
  output=$(mysql -uroot -P${fe_query_port} -h${fe_ip} \
    -e "ALTER SYSTEM ADD BACKEND \"${be_ip}:${be_port}\"" 2>&1)
  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}BE node registered successfully!${CEND}"
  elif echo "${output}" | grep -qi "already exists"; then
    # Re-run of a previous deployment: the node is already in the FE metadata
    echo "${CWARNING}BE node ${be_ip}:${be_port} already registered, skipping.${CEND}"
  else
    echo "${output}"
    echo "${CFAILURE}Failed to register BE node!${CEND}"
    return 1
  fi
}

Decommission_BE() {
  local fe_ip=$1
  local be_ip=$2
  local be_port=${3:-${be_heartbeat_service_port}}

  echo "${CMSG}Decommissioning BE node: ${be_ip}:${be_port}${CEND}"
  mysql -uroot -P${fe_query_port} -h${fe_ip} -e "ALTER SYSTEM DECOMMISSION BACKEND \"${be_ip}:${be_port}\""
  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}BE node decommission started. Check status with 'show backends'.${CEND}"
  else
    echo "${CFAILURE}Failed to decommission BE node!${CEND}"
    return 1
  fi
}

Uninstall_BE() {
  echo "${CMSG}Uninstalling Doris BE...${CEND}"

  # Stop BE
  Stop_BE

  # Remove systemd service
  if [ -e "/lib/systemd/system/doris-be.service" ]; then
    systemctl disable doris-be > /dev/null 2>&1
    rm -f /lib/systemd/system/doris-be.service
    systemctl daemon-reload
  fi

  # Remove installation directory
  [ -d "${be_install_dir}" ] && rm -rf ${be_install_dir}

  # Backup and remove data directory
  if [ -d "${be_data_dir}" ]; then
    echo "${CWARNING}Backing up BE data to ${be_data_dir}.bak.$(date +%Y%m%d%H%M%S)${CEND}"
    mv ${be_data_dir} ${be_data_dir}.bak.$(date +%Y%m%d%H%M%S)
  fi

  # Remove log directory
  [ -d "${be_log_dir}" ] && rm -rf ${be_log_dir}

  echo "${CSUCCESS}Doris BE uninstalled successfully!${CEND}"
}
