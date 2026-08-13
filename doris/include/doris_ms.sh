#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Meta Service (MS) installation and management
#
# Meta Service is required for 存算分离 (separating storage-compute) mode
# Only available in Doris 3.x+
# Unified package: apache-doris-<ver>-bin-<arch>.tar.gz contains ms/ subdir

Install_MS() {
  local doris_ver=$1
  local major_ver=${doris_ver%%.*}

  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Installing Doris Meta Service ${doris_ver}${CEND}"
  echo "${CMSG}============================================${CEND}"

  # Version check: MS only available in 3.x+
  if [ "${major_ver}" -lt 3 ]; then
    echo "${CFAILURE}Meta Service requires Doris 3.x+! Current version: ${doris_ver}${CEND}"
    return 1
  fi

  # Check if MS already installed
  if [ -e "${ms_install_dir}/bin/start.sh" ]; then
    echo "${CWARNING}Meta Service already installed at ${ms_install_dir}${CEND}"
    return 1
  fi

  # Create directories
  mkdir -p ${ms_install_dir}
  mkdir -p ${ms_log_dir}

  # Extract ms/ from unified package
  Extract_Component "${doris_ver}" "ms" "${ms_install_dir}" || return 1

  # Configure MS
  Configure_MS

  # Create symlink for log directory
  if [ -d "${ms_install_dir}/log" ]; then
    rm -rf ${ms_install_dir}/log
  fi
  ln -sf ${ms_log_dir} ${ms_install_dir}/log

  # Set ownership
  chown -R ${run_user}:${run_group} ${ms_install_dir}
  chown -R ${run_user}:${run_group} ${ms_log_dir}

  # Install systemd service
  Install_MS_Service

  echo "${CSUCCESS}Meta Service ${doris_ver} installed successfully!${CEND}"
  echo "${CSUCCESS}MS install dir: ${ms_install_dir}${CEND}"
  echo "${CSUCCESS}MS log dir: ${ms_log_dir}${CEND}"
}

Configure_MS() {
  local ms_conf="${ms_install_dir}/conf/doris_cloud.conf"

  if [ ! -f "${ms_conf}" ]; then
    cp ${doris_dir}/config/doris_cloud.conf ${ms_conf}
  fi

  # Set brpc_listen_port
  if grep -q "^brpc_listen_port" ${ms_conf}; then
    sed -i "s|^brpc_listen_port.*|brpc_listen_port = ${ms_brpc_port}|" ${ms_conf}
  else
    echo "brpc_listen_port = ${ms_brpc_port}" >> ${ms_conf}
  fi

  # Set fdb_cluster connection string
  if [ -n "${fdb_cluster}" ]; then
    if grep -q "^fdb_cluster" ${ms_conf}; then
      sed -i "s|^fdb_cluster.*|fdb_cluster = ${fdb_cluster}|" ${ms_conf}
    else
      echo "fdb_cluster = ${fdb_cluster}" >> ${ms_conf}
    fi
  else
    # Try to read from FDB cluster file
    local fdb_cluster_file="${fdb_home}/conf/fdb.cluster"
    if [ -f "${fdb_cluster_file}" ]; then
      local fdb_conn=$(tail -1 ${fdb_cluster_file})
      if grep -q "^fdb_cluster" ${ms_conf}; then
        sed -i "s|^fdb_cluster.*|fdb_cluster = ${fdb_conn}|" ${ms_conf}
      else
        echo "fdb_cluster = ${fdb_conn}" >> ${ms_conf}
      fi
      fdb_cluster="${fdb_conn}"
      echo "${CSUCCESS}Auto-detected FDB cluster: ${fdb_conn}${CEND}"
    elif [ -f "/etc/foundationdb/fdb.cluster" ]; then
      local fdb_conn=$(tail -1 /etc/foundationdb/fdb.cluster)
      if grep -q "^fdb_cluster" ${ms_conf}; then
        sed -i "s|^fdb_cluster.*|fdb_cluster = ${fdb_conn}|" ${ms_conf}
      else
        echo "fdb_cluster = ${fdb_conn}" >> ${ms_conf}
      fi
      fdb_cluster="${fdb_conn}"
      echo "${CSUCCESS}Auto-detected FDB cluster: ${fdb_conn}${CEND}"
    else
      echo "${CWARNING}FDB cluster connection not set! Please configure fdb_cluster in doris_cloud.conf${CEND}"
    fi
  fi

  echo "${CSUCCESS}Meta Service configuration updated: ${ms_conf}${CEND}"
}

Install_MS_Service() {
  cp ${doris_dir}/init.d/doris-ms.service /lib/systemd/system/doris-ms.service
  sed -i "s|@RUN_USER@|${run_user}|g" /lib/systemd/system/doris-ms.service
  sed -i "s|@RUN_GROUP@|${run_group}|g" /lib/systemd/system/doris-ms.service
  sed -i "s|@MS_INSTALL_DIR@|${ms_install_dir}|g" /lib/systemd/system/doris-ms.service
  sed -i "s|@JAVA_HOME@|${JAVA_HOME}|g" /lib/systemd/system/doris-ms.service
  systemctl daemon-reload
  systemctl enable doris-ms
  echo "${CSUCCESS}Doris Meta Service systemd service installed.${CEND}"
}

Start_MS() {
  echo "${CMSG}Starting Doris Meta Service...${CEND}"

  # Meta Service requires JDK 17
  if [ -n "${JAVA_HOME}" ]; then
    su - ${run_user} -s /bin/bash -c "export JAVA_HOME=${JAVA_HOME} && ${ms_install_dir}/bin/start.sh --daemon"
  else
    su - ${run_user} -s /bin/bash -c "${ms_install_dir}/bin/start.sh --daemon"
  fi

  # Wait and check status, retry for up to 60s
  local retry=0
  while [ ${retry} -lt 12 ]; do
    if MS_Process_Alive; then
      echo "${CSUCCESS}Meta Service started successfully!${CEND}"
      return 0
    fi
    sleep 5
    retry=$((retry + 1))
  done

  echo "${CFAILURE}Meta Service start failed! Check log: ${ms_log_dir}/${CEND}"
  return 1
}

Stop_MS() {
  echo "${CMSG}Stopping Doris Meta Service...${CEND}"
  if [ -x "${ms_install_dir}/bin/stop.sh" ]; then
    su - ${run_user} -s /bin/bash -c "${ms_install_dir}/bin/stop.sh"
  fi
  sleep 2
  echo "${CSUCCESS}Meta Service stopped.${CEND}"
}

MS_Process_Alive() {
  local pid_file="${ms_install_dir}/bin/doris_cloud.pid"
  if [ -f "${pid_file}" ]; then
    local pid=$(cat ${pid_file} 2>/dev/null)
    [ -n "${pid}" ] && kill -0 ${pid} 2>/dev/null && return 0
  fi
  ps aux | grep -v grep | grep -q "doris_cloud\|meta_service\|${ms_install_dir}" && return 0
  return 1
}

Check_MS_Status() {
  if MS_Process_Alive; then
    echo "${CSUCCESS}Meta Service is running.${CEND}"
    return 0
  else
    echo "${CWARNING}Meta Service is not running.${CEND}"
    return 1
  fi
}

Uninstall_MS() {
  echo "${CMSG}Uninstalling Doris Meta Service...${CEND}"

  # Stop MS
  Stop_MS

  # Remove systemd service
  if [ -e "/lib/systemd/system/doris-ms.service" ]; then
    systemctl disable doris-ms > /dev/null 2>&1
    rm -f /lib/systemd/system/doris-ms.service
    systemctl daemon-reload
  fi

  # Remove installation directory
  [ -d "${ms_install_dir}" ] && rm -rf ${ms_install_dir}

  # Remove log directory
  [ -d "${ms_log_dir}" ] && rm -rf ${ms_log_dir}

  echo "${CSUCCESS}Meta Service uninstalled successfully!${CEND}"
}
