#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# FE (Frontend) node installation and management
#
# Unified package: apache-doris-<ver>-bin-<arch>.tar.gz contains fe/ subdir

Install_FE() {
  local doris_ver=$1
  local major_ver=${doris_ver%%.*}

  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Installing Doris FE ${doris_ver}${CEND}"
  echo "${CMSG}============================================${CEND}"

  # Check if FE already installed
  if [ -e "${fe_install_dir}/bin/start_fe.sh" ]; then
    echo "${CWARNING}Doris FE already installed at ${fe_install_dir}${CEND}"
    return 1
  fi

  # Create directories
  mkdir -p ${fe_install_dir}
  mkdir -p ${fe_meta_dir}
  mkdir -p ${fe_log_dir}

  # Extract fe/ from unified package
  Extract_Component "${doris_ver}" "fe" "${fe_install_dir}" || return 1

  # Configure FE
  Configure_FE "${doris_ver}"

  # Create symlink for meta directory
  if [ -d "${fe_install_dir}/doris-meta" ]; then
    rm -rf ${fe_install_dir}/doris-meta
  fi
  ln -sf ${fe_meta_dir} ${fe_install_dir}/doris-meta

  # Create symlink for log directory
  if [ -d "${fe_install_dir}/log" ]; then
    rm -rf ${fe_install_dir}/log
  fi
  ln -sf ${fe_log_dir} ${fe_install_dir}/log

  # Set ownership
  chown -R ${run_user}:${run_group} ${fe_install_dir}
  chown -R ${run_user}:${run_group} ${fe_meta_dir}
  chown -R ${run_user}:${run_group} ${fe_log_dir}

  # Install systemd service
  Install_FE_Service

  echo "${CSUCCESS}Doris FE ${doris_ver} installed successfully!${CEND}"
  echo "${CSUCCESS}FE install dir: ${fe_install_dir}${CEND}"
  echo "${CSUCCESS}FE meta dir: ${fe_meta_dir}${CEND}"
  echo "${CSUCCESS}FE log dir: ${fe_log_dir}${CEND}"
}

Configure_FE() {
  local doris_ver=${1:-""}
  local major_ver=${doris_ver%%.*}
  local fe_conf="${fe_install_dir}/conf/fe.conf"

  if [ ! -f "${fe_conf}" ]; then
    cp ${doris_dir}/config/fe.conf ${fe_conf}
  fi

  # Set JAVA_HOME
  if [ -n "${JAVA_HOME}" ]; then
    if grep -q "^JAVA_HOME" ${fe_conf}; then
      sed -i "s|^JAVA_HOME.*|JAVA_HOME = ${JAVA_HOME}|" ${fe_conf}
    else
      sed -i "1a JAVA_HOME = ${JAVA_HOME}" ${fe_conf}
    fi
  fi

  # Set priority_networks
  if [ -n "${priority_networks}" ]; then
    if grep -q "^priority_networks" ${fe_conf}; then
      sed -i "s|^priority_networks.*|priority_networks = ${priority_networks}|" ${fe_conf}
    elif grep -q "^# priority_networks" ${fe_conf}; then
      sed -i "s|^# priority_networks.*|priority_networks = ${priority_networks}|" ${fe_conf}
    else
      echo "priority_networks = ${priority_networks}" >> ${fe_conf}
    fi
  fi

  # Set lower_case_table_names
  if grep -q "^lower_case_table_names" ${fe_conf}; then
    sed -i "s|^lower_case_table_names.*|lower_case_table_names = ${fe_lower_case_table_names}|" ${fe_conf}
  else
    echo "lower_case_table_names = ${fe_lower_case_table_names}" >> ${fe_conf}
  fi

  # Set Java Heap (only for the JAVA_OPTS line matching JDK version)
  if grep -q "^JAVA_OPTS=" ${fe_conf}; then
    sed -i "/^JAVA_OPTS=/s|-Xmx[0-9]*[gGmM]|-Xmx${fe_java_heap}|" ${fe_conf}
  fi
  if grep -q "^JAVA_OPTS_FOR_JDK_17=" ${fe_conf}; then
    sed -i "/^JAVA_OPTS_FOR_JDK_17=/s|-Xmx[0-9]*[gGmM]|-Xmx${fe_java_heap}|" ${fe_conf}
  fi

  # Set meta directory
  if grep -q "^meta_dir" ${fe_conf}; then
    sed -i "s|^meta_dir.*|meta_dir = ${fe_meta_dir}|" ${fe_conf}
  elif grep -q "^# meta_dir" ${fe_conf}; then
    sed -i "s|^# meta_dir.*|meta_dir = ${fe_meta_dir}|" ${fe_conf}
  else
    echo "meta_dir = ${fe_meta_dir}" >> ${fe_conf}
  fi

  # Set http port
  if grep -q "^http_port" ${fe_conf}; then
    sed -i "s|^http_port.*|http_port = ${fe_http_port}|" ${fe_conf}
  fi

  # Set rpc port
  if grep -q "^rpc_port" ${fe_conf}; then
    sed -i "s|^rpc_port.*|rpc_port = ${fe_rpc_port}|" ${fe_conf}
  fi

  # Set query port
  if grep -q "^query_port" ${fe_conf}; then
    sed -i "s|^query_port.*|query_port = ${fe_query_port}|" ${fe_conf}
  fi

  # Set edit_log_port
  if grep -q "^edit_log_port" ${fe_conf}; then
    sed -i "s|^edit_log_port.*|edit_log_port = ${fe_edit_log_port}|" ${fe_conf}
  fi

  # 存算分离 mode: set deploy_mode=cloud, cluster_id, meta_service_endpoint
  if [ "${deploy_mode}" == "separated" ]; then
    if [ -n "${major_ver}" ] && [ "${major_ver}" -lt 3 ]; then
      echo "${CFAILURE}Doris ${doris_ver} does not support separating storage-compute mode!${CEND}"
      echo "${CFAILURE}Separating mode requires Doris 3.x+${CEND}"
      return 1
    fi

    # Set deploy_mode = cloud
    if grep -q "^deploy_mode" ${fe_conf}; then
      sed -i "s|^deploy_mode.*|deploy_mode = cloud|" ${fe_conf}
    else
      echo "deploy_mode = cloud" >> ${fe_conf}
    fi

    # Set cluster_id
    if [ -z "${cloud_cluster_id}" ]; then
      cloud_cluster_id=$(echo $(($((RANDOM << 15)) | $RANDOM)))
    fi
    if grep -q "^cluster_id" ${fe_conf}; then
      sed -i "s|^cluster_id.*|cluster_id = ${cloud_cluster_id}|" ${fe_conf}
    else
      echo "cluster_id = ${cloud_cluster_id}" >> ${fe_conf}
    fi

    # Set meta_service_endpoint from ms_nodes
    if [ -n "${ms_nodes}" ]; then
      local ms_endpoint=$(echo ${ms_nodes} | awk -F, '{for(i=1;i<=NF;i++){split($i,a,":"); printf "http://"a[1]":"a[2]; if(i<NF) printf ","}}')
      if grep -q "^meta_service_endpoint" ${fe_conf}; then
        sed -i "s|^meta_service_endpoint.*|meta_service_endpoint = ${ms_endpoint}|" ${fe_conf}
      else
        echo "meta_service_endpoint = ${ms_endpoint}" >> ${fe_conf}
      fi
    fi
  fi

  echo "${CSUCCESS}FE configuration updated: ${fe_conf}${CEND}"
}

Install_FE_Service() {
  cp ${doris_dir}/init.d/doris-fe.service /lib/systemd/system/doris-fe.service
  sed -i "s|@RUN_USER@|${run_user}|g" /lib/systemd/system/doris-fe.service
  sed -i "s|@RUN_GROUP@|${run_group}|g" /lib/systemd/system/doris-fe.service
  sed -i "s|@FE_INSTALL_DIR@|${fe_install_dir}|g" /lib/systemd/system/doris-fe.service
  sed -i "s|@JAVA_HOME@|${JAVA_HOME}|g" /lib/systemd/system/doris-fe.service
  systemctl daemon-reload
  systemctl enable doris-fe
  echo "${CSUCCESS}Doris FE systemd service installed.${CEND}"
}

Start_FE() {
  local helper_node=$1

  echo "${CMSG}Starting Doris FE...${CEND}"
  if [ -n "${helper_node}" ]; then
    su - ${run_user} -s /bin/bash -c "export JAVA_HOME=${JAVA_HOME} && ${fe_install_dir}/bin/start_fe.sh --helper ${helper_node} --daemon"
  else
    su - ${run_user} -s /bin/bash -c "export JAVA_HOME=${JAVA_HOME} && ${fe_install_dir}/bin/start_fe.sh --daemon"
  fi

  # FE needs some time to bootstrap the JVM, retry for up to 60s
  local retry=0
  while [ ${retry} -lt 12 ]; do
    if FE_Process_Alive; then
      echo "${CSUCCESS}Doris FE started successfully!${CEND}"
      return 0
    fi
    sleep 5
    retry=$((retry + 1))
  done

  echo "${CFAILURE}Doris FE start failed! Check log: ${fe_log_dir}/fe.log${CEND}"
  return 1
}

Stop_FE() {
  echo "${CMSG}Stopping Doris FE...${CEND}"
  if [ -x "${fe_install_dir}/bin/stop_fe.sh" ]; then
    su - ${run_user} -s /bin/bash -c "${fe_install_dir}/bin/stop_fe.sh"
  fi
  sleep 2
  echo "${CSUCCESS}Doris FE stopped.${CEND}"
}

# FE main class since 2.x is org.apache.doris.DorisFE; the pid file is the
# authoritative source (it is also what the systemd unit uses).
FE_Process_Alive() {
  local pid_file="${fe_install_dir}/bin/fe.pid"
  if [ -f "${pid_file}" ]; then
    local pid=$(cat ${pid_file} 2>/dev/null)
    [ -n "${pid}" ] && kill -0 ${pid} 2>/dev/null && return 0
  fi
  ps aux | grep -v grep | grep -q "org.apache.doris.DorisFE\|${fe_install_dir}/lib" && return 0
  return 1
}

Check_FE_Status() {
  if FE_Process_Alive; then
    echo "${CSUCCESS}Doris FE is running.${CEND}"
    return 0
  else
    echo "${CWARNING}Doris FE is not running.${CEND}"
    return 1
  fi
}

Register_FE_Follower() {
  local master_ip=$1
  local follower_ip=$2
  local follower_port=${3:-${fe_edit_log_port}}

  echo "${CMSG}Registering FE Follower: ${follower_ip}:${follower_port}${CEND}"
  local output
  output=$(mysql -uroot -P${fe_query_port} -h${master_ip} \
    -e "ALTER SYSTEM ADD FOLLOWER \"${follower_ip}:${follower_port}\"" 2>&1)
  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}FE Follower registered successfully!${CEND}"
  elif echo "${output}" | grep -qi "already exist"; then
    # Re-run of a previous deployment: the node is already in the FE metadata
    echo "${CWARNING}FE Follower ${follower_ip}:${follower_port} already registered, skipping.${CEND}"
  else
    echo "${output}"
    echo "${CFAILURE}Failed to register FE Follower!${CEND}"
    return 1
  fi
}

Register_FE_Observer() {
  local master_ip=$1
  local observer_ip=$2
  local observer_port=${3:-${fe_edit_log_port}}

  echo "${CMSG}Registering FE Observer: ${observer_ip}:${observer_port}${CEND}"
  local output
  output=$(mysql -uroot -P${fe_query_port} -h${master_ip} \
    -e "ALTER SYSTEM ADD OBSERVER \"${observer_ip}:${observer_port}\"" 2>&1)
  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}FE Observer registered successfully!${CEND}"
  elif echo "${output}" | grep -qi "already exist"; then
    echo "${CWARNING}FE Observer ${observer_ip}:${observer_port} already registered, skipping.${CEND}"
  else
    echo "${output}"
    echo "${CFAILURE}Failed to register FE Observer!${CEND}"
    return 1
  fi
}

Uninstall_FE() {
  echo "${CMSG}Uninstalling Doris FE...${CEND}"

  # Stop FE
  Stop_FE

  # Remove systemd service
  if [ -e "/lib/systemd/system/doris-fe.service" ]; then
    systemctl disable doris-fe > /dev/null 2>&1
    rm -f /lib/systemd/system/doris-fe.service
    systemctl daemon-reload
  fi

  # Remove installation directory
  [ -d "${fe_install_dir}" ] && rm -rf ${fe_install_dir}

  # Backup and remove meta directory
  if [ -d "${fe_meta_dir}" ]; then
    echo "${CWARNING}Backing up FE meta data to ${fe_meta_dir}.bak.$(date +%Y%m%d%H%M%S)${CEND}"
    mv ${fe_meta_dir} ${fe_meta_dir}.bak.$(date +%Y%m%d%H%M%S)
  fi

  # Remove log directory
  [ -d "${fe_log_dir}" ] && rm -rf ${fe_log_dir}

  echo "${CSUCCESS}Doris FE uninstalled successfully!${CEND}"
}
