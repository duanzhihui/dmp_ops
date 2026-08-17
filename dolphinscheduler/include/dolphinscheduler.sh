#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# DolphinScheduler installation and uninstallation functions

# Install DolphinScheduler Standalone mode
Install_DolphinScheduler_Standalone() {
  local ds_ver=$1
  local ds_pkg=$(Get_DolphinScheduler_Pkg "${ds_ver}")

  echo "${CMSG}Installing DolphinScheduler ${ds_ver} (Standalone mode)...${CEND}"

  # Check if already installed
  if [ -d "${dolphinscheduler_install_dir}" ] && [ -f "${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh" ]; then
    echo "${CWARNING}DolphinScheduler is already installed at ${dolphinscheduler_install_dir}${CEND}"
    return 0
  fi

  # Create directories
  mkdir -p ${dolphinscheduler_install_dir}
  mkdir -p ${dolphinscheduler_data_dir}
  mkdir -p ${dolphinscheduler_log_dir}

  # Extract package
  echo "${CMSG}Extracting ${ds_pkg}...${CEND}"
  tar xzf ${ds_dir}/src/${ds_pkg} -C ${dolphinscheduler_install_dir} --strip-components=1

  if [ ! -f "${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh" ]; then
    echo "${CFAILURE}Failed to extract DolphinScheduler package!${CEND}"
    return 1
  fi

  # Configure JAVA_HOME in dolphinscheduler_env.sh
  Configure_Env_Standalone "${ds_ver}"

  # Set ownership
  chown -R ${run_user}:${run_group} ${dolphinscheduler_install_dir}
  chown -R ${run_user}:${run_group} ${dolphinscheduler_data_dir}
  chown -R ${run_user}:${run_group} ${dolphinscheduler_log_dir}

  # Install systemd service
  Install_Standalone_Service

  echo "${CSUCCESS}DolphinScheduler ${ds_ver} (Standalone) installed successfully!${CEND}"
}

# Configure environment for Standalone mode
Configure_Env_Standalone() {
  local ds_ver=$1
  local env_file="${dolphinscheduler_install_dir}/bin/env/dolphinscheduler_env.sh"

  echo "${CMSG}Configuring environment...${CEND}"

  if [ -f "${env_file}" ]; then
    # Remove any existing DolphinSchedulerStack configuration block
    sed -i '/^# DolphinSchedulerStack Configuration/,/^# End DolphinSchedulerStack Configuration/d' ${env_file}

    # Append JAVA_HOME configuration
    if [ -n "${JAVA_HOME}" ]; then
      cat >> ${env_file} << EOF

# DolphinSchedulerStack Configuration
export JAVA_HOME=${JAVA_HOME}
# End DolphinSchedulerStack Configuration
EOF
    fi
    echo "${CSUCCESS}Environment variables configured in ${env_file}${CEND}"
  fi
}

# Install DolphinScheduler Pseudo-Cluster mode
Install_DolphinScheduler_PseudoCluster() {
  local ds_ver=$1
  local ds_pkg=$(Get_DolphinScheduler_Pkg "${ds_ver}")

  echo "${CMSG}Installing DolphinScheduler ${ds_ver} (roles: ${node_roles:-master,worker,api,alert})...${CEND}"

  # Create directories
  mkdir -p ${dolphinscheduler_install_dir}
  mkdir -p ${dolphinscheduler_data_dir}
  mkdir -p ${dolphinscheduler_log_dir}

  # Extract package (skip if already extracted, but keep reconfiguring so that a
  # re-run after a failed attempt actually repairs the installation)
  if [ -f "${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh" ]; then
    echo "${CWARNING}DolphinScheduler already extracted at ${dolphinscheduler_install_dir}, skipping extraction.${CEND}"
  else
    echo "${CMSG}Extracting ${ds_pkg}...${CEND}"
    tar xzf ${ds_dir}/src/${ds_pkg} -C ${dolphinscheduler_install_dir} --strip-components=1

    if [ ! -f "${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh" ]; then
      echo "${CFAILURE}Failed to extract DolphinScheduler package!${CEND}"
      return 1
    fi
  fi

  # Download and install MySQL JDBC driver if using MySQL
  if [ "${db_type}" == "mysql" ]; then
    Download_MySQL_JDBC
    Install_MySQL_JDBC || return 1
  fi

  # Configure environment
  Configure_Env_PseudoCluster "${ds_ver}" || return 1

  # Configure install_env.sh
  Configure_Install_Env

  # Initialize database (shared schema: only done once, on the first node)
  if [ "${skip_db_init}" == "y" ]; then
    echo "${CMSG}Skipping database initialization (schema already initialized by the first node).${CEND}"
  else
    Init_Database || return 1
  fi

  # Set ownership
  chown -R ${run_user}:${run_group} ${dolphinscheduler_install_dir}
  chown -R ${run_user}:${run_group} ${dolphinscheduler_data_dir}
  chown -R ${run_user}:${run_group} ${dolphinscheduler_log_dir}

  # Install systemd services
  Install_PseudoCluster_Services

  echo "${CSUCCESS}DolphinScheduler ${ds_ver} installed successfully (roles: ${node_roles:-master,worker,api,alert})!${CEND}"
}

# Configure environment for Pseudo-Cluster mode
Configure_Env_PseudoCluster() {
  local ds_ver=$1
  local env_file="${dolphinscheduler_install_dir}/bin/env/dolphinscheduler_env.sh"

  echo "${CMSG}Configuring environment for Pseudo-Cluster...${CEND}"

  if [ -f "${env_file}" ]; then
    # Build JDBC URL based on database type
    local jdbc_url driver_class
    if [ "${db_type}" == "mysql" ]; then
      jdbc_url="jdbc:mysql://${db_host}:${db_port}/${db_name}?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true"
      driver_class="com.mysql.cj.jdbc.Driver"
    else
      jdbc_url="jdbc:postgresql://${db_host}:${db_port}/${db_name}"
      driver_class="org.postgresql.Driver"
    fi

    # Append environment variables to the file
    # First remove any existing DolphinSchedulerStack configuration block
    sed -i '/^# DolphinSchedulerStack Configuration/,/^# End DolphinSchedulerStack Configuration/d' ${env_file}

    # Append new configuration block
    cat >> ${env_file} << EOF

# DolphinSchedulerStack Configuration
export JAVA_HOME=${JAVA_HOME}
export DATABASE=${db_type}
export SPRING_PROFILES_ACTIVE=${db_type}
export SPRING_DATASOURCE_URL="${jdbc_url}"
export SPRING_DATASOURCE_USERNAME=${db_user}
export SPRING_DATASOURCE_PASSWORD="${db_password}"
export SPRING_DATASOURCE_DRIVER_CLASS_NAME=${driver_class}
export REGISTRY_TYPE=zookeeper
export REGISTRY_ZOOKEEPER_CONNECT_STRING=${zk_hosts}
# End DolphinSchedulerStack Configuration
EOF

    echo "${CSUCCESS}Environment variables configured in ${env_file}${CEND}"
  else
    echo "${CFAILURE}Environment file not found: ${env_file}${CEND}"
    return 1
  fi

  # Configure application.yaml files for each module
  Configure_Application_Yaml
}

# Configure install_env.sh
Configure_Install_Env() {
  local install_env_file="${dolphinscheduler_install_dir}/bin/env/install_env.sh"

  echo "${CMSG}Configuring install_env.sh...${CEND}"

  if [ -f "${install_env_file}" ]; then
    sed -i "s|^ips=.*|ips=\"${ips}\"|" ${install_env_file}
    sed -i "s|^sshPort=.*|sshPort=\"${ssh_port}\"|" ${install_env_file}
    sed -i "s|^masters=.*|masters=\"${masters}\"|" ${install_env_file}
    sed -i "s|^workers=.*|workers=\"${workers}\"|" ${install_env_file}
    sed -i "s|^alertServer=.*|alertServer=\"${alert_server}\"|" ${install_env_file}
    sed -i "s|^apiServers=.*|apiServers=\"${api_servers}\"|" ${install_env_file}
    sed -i "s|^installPath=.*|installPath=${dolphinscheduler_install_dir}|" ${install_env_file}
    sed -i "s|^deployUser=.*|deployUser=\"${run_user}\"|" ${install_env_file}
  fi
}

# Configure application.yaml files
Configure_Application_Yaml() {
  local modules=("tools" "alert-server" "api-server" "master-server" "worker-server")

  for module in "${modules[@]}"; do
    local yaml_file="${dolphinscheduler_install_dir}/${module}/conf/application.yaml"
    if [ -f "${yaml_file}" ]; then
      echo "${CMSG}Configuring ${module}/conf/application.yaml...${CEND}"

      # Note: Do NOT modify spring.profiles.active or database settings in application.yaml
      # DolphinScheduler 3.x uses multi-document YAML format with separate configs for each DB type (mysql/postgresql/h2)
      # All database configuration is passed via environment variables in dolphinscheduler_env.sh:
      #   - SPRING_PROFILES_ACTIVE (mysql or postgresql)
      #   - SPRING_DATASOURCE_URL
      #   - SPRING_DATASOURCE_USERNAME  
      #   - SPRING_DATASOURCE_PASSWORD
      #   - SPRING_DATASOURCE_DRIVER_CLASS_NAME
      
      # Only configure module-specific settings (ports, binding address)
      case "${module}" in
        api-server)
          Configure_Api_Server_Binding "${yaml_file}"
          Configure_Server_Port "${yaml_file}" "${api_port}"
          ;;
        master-server)
          Configure_Master_Server_Ports "${yaml_file}" "${master_rpc_port}" "${master_web_port}"
          ;;
        worker-server)
          Configure_Worker_Server_Ports "${yaml_file}" "${worker_rpc_port}" "${worker_web_port}"
          ;;
        alert-server)
          Configure_Alert_Server_Ports "${yaml_file}" "${alert_rpc_port}" "${alert_web_port}"
          ;;
      esac
    fi
  done
}

# Configure Master Server ports (RPC port and Web port)
# Master Server has two services that need different ports:
#   - MasterRpcServer: uses master.listen-port for internal RPC communication
#   - Jetty Web Server: uses server.port for actuator/metrics endpoints
Configure_Master_Server_Ports() {
  local yaml_file=$1
  local rpc_port=$2
  local web_port=$3
  
  [ -z "${rpc_port}" ] && rpc_port=5678
  [ -z "${web_port}" ] && web_port=5679
  
  echo "${CMSG}Configuring Master Server ports: RPC=${rpc_port}, Web=${web_port}...${CEND}"
  
  # Configure server.port (Jetty Web Server port)
  awk -v port="${web_port}" '
    BEGIN { in_server=0; done=0 }
    /^---/ { in_server=0 }
    /^server:/ { in_server=1 }
    in_server && /^[[:space:]]+port:/ && !done {
      sub(/port:.*/, "port: " port)
      done=1
    }
    { print }
  ' "${yaml_file}" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "${yaml_file}"
  
  # Configure master.listen-port (MasterRpcServer port)
  awk -v port="${rpc_port}" '
    BEGIN { in_master=0; done=0 }
    /^---/ { in_master=0 }
    /^master:/ { in_master=1 }
    in_master && /^[[:space:]]+listen-port:/ && !done {
      sub(/listen-port:.*/, "listen-port: " port)
      done=1
    }
    { print }
  ' "${yaml_file}" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "${yaml_file}"
}

# Configure Worker Server ports (RPC port and Web port)
# Worker Server has two services that need different ports:
#   - WorkerRpcServer: uses worker.listen-port for internal RPC communication
#   - Jetty Web Server: uses server.port for actuator/metrics endpoints
Configure_Worker_Server_Ports() {
  local yaml_file=$1
  local rpc_port=$2
  local web_port=$3
  
  [ -z "${rpc_port}" ] && rpc_port=1234
  [ -z "${web_port}" ] && web_port=1235
  
  echo "${CMSG}Configuring Worker Server ports: RPC=${rpc_port}, Web=${web_port}...${CEND}"
  
  # Configure server.port (Jetty Web Server port)
  awk -v port="${web_port}" '
    BEGIN { in_server=0; done=0 }
    /^---/ { in_server=0 }
    /^server:/ { in_server=1 }
    in_server && /^[[:space:]]+port:/ && !done {
      sub(/port:.*/, "port: " port)
      done=1
    }
    { print }
  ' "${yaml_file}" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "${yaml_file}"
  
  # Configure worker.listen-port (WorkerRpcServer port)
  awk -v port="${rpc_port}" '
    BEGIN { in_worker=0; done=0 }
    /^---/ { in_worker=0 }
    /^worker:/ { in_worker=1 }
    in_worker && /^[[:space:]]+listen-port:/ && !done {
      sub(/listen-port:.*/, "listen-port: " port)
      done=1
    }
    { print }
  ' "${yaml_file}" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "${yaml_file}"
}

# Configure Alert Server ports (RPC port and Web port)
# Alert Server has two services that need different ports:
#   - AlertRpcServer: uses alert.port for internal RPC communication
#   - Jetty Web Server: uses server.port for actuator/metrics endpoints
Configure_Alert_Server_Ports() {
  local yaml_file=$1
  local rpc_port=$2
  local web_port=$3
  
  [ -z "${rpc_port}" ] && rpc_port=50052
  [ -z "${web_port}" ] && web_port=50053
  
  echo "${CMSG}Configuring Alert Server ports: RPC=${rpc_port}, Web=${web_port}...${CEND}"
  
  # Configure server.port (Jetty Web Server port)
  awk -v port="${web_port}" '
    BEGIN { in_server=0; done=0 }
    /^---/ { in_server=0 }
    /^server:/ { in_server=1 }
    in_server && /^[[:space:]]+port:/ && !done {
      sub(/port:.*/, "port: " port)
      done=1
    }
    { print }
  ' "${yaml_file}" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "${yaml_file}"
  
  # Configure alert.port (AlertRpcServer port)
  # This is under the 'alert:' section in the first YAML document
  awk -v port="${rpc_port}" '
    BEGIN { in_alert=0; done=0 }
    /^---/ { in_alert=0 }
    /^alert:/ { in_alert=1 }
    in_alert && /^[[:space:]]+port:/ && !done {
      sub(/port:.*/, "port: " port)
      done=1
    }
    { print }
  ' "${yaml_file}" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "${yaml_file}"
}

# Configure server port in application.yaml
# Only modifies the port under the 'server:' section in the first YAML document
Configure_Server_Port() {
  local yaml_file=$1
  local port=$2
  
  [ -z "${port}" ] && return
  
  # Use awk to only modify port under server: section before any --- separator
  # This ensures we don't modify ports in other YAML documents (e.g., database configs)
  awk -v port="${port}" '
    BEGIN { in_server=0; done=0 }
    /^---/ { in_server=0 }
    /^server:/ { in_server=1 }
    in_server && /^[[:space:]]+port:/ && !done {
      sub(/port:.*/, "port: " port)
      done=1
    }
    { print }
  ' "${yaml_file}" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "${yaml_file}"
}

# Configure API server to bind to 0.0.0.0 for external access
# Only modifies the address under the 'server:' section in the first YAML document
Configure_Api_Server_Binding() {
  local yaml_file=$1
  
  echo "${CMSG}Configuring API server to listen on 0.0.0.0...${CEND}"
  
  # Check if server section exists in the first YAML document
  if awk '/^---/{exit} /^server:/{found=1} END{exit !found}' "${yaml_file}"; then
    # Use awk to add or modify address under server: section
    awk '
      BEGIN { in_server=0; done=0; has_address=0 }
      /^---/ { in_server=0 }
      /^server:/ { in_server=1; print; next }
      in_server && /^[[:space:]]+address:/ && !done {
        print "  address: 0.0.0.0"
        done=1
        has_address=1
        next
      }
      in_server && /^[^[:space:]]/ && !has_address && !done {
        # Reached next top-level key without finding address, insert it
        print "  address: 0.0.0.0"
        done=1
        in_server=0
      }
      { print }
      END {
        # If we were still in server section at EOF and no address was set
        if (in_server && !done) {
          print "  address: 0.0.0.0"
        }
      }
    ' "${yaml_file}" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "${yaml_file}"
  else
    # Add server section at the beginning
    local tmp_file=$(mktemp)
    printf "server:\n  address: 0.0.0.0\n\n" > "${tmp_file}"
    cat "${yaml_file}" >> "${tmp_file}"
    mv "${tmp_file}" "${yaml_file}"
  fi
}

# Install MySQL JDBC driver to all modules
Install_MySQL_JDBC() {
  local jdbc_ver=${mysql_jdbc_ver:-8.0.33}
  local jdbc_jar="mysql-connector-j-${jdbc_ver}.jar"
  local modules=("tools/libs" "alert-server/libs" "api-server/libs" "master-server/libs" "worker-server/libs")

  echo "${CMSG}Installing MySQL JDBC driver to all modules...${CEND}"

  for module in "${modules[@]}"; do
    local target_dir="${dolphinscheduler_install_dir}/${module}"
    if [ -d "${target_dir}" ]; then
      Extract_MySQL_JDBC "${target_dir}"
    fi
  done
}

# Initialize database
Init_Database() {
  echo "${CMSG}Initializing database...${CEND}"

  local tools_dir="${dolphinscheduler_install_dir}/tools"

  if [ -f "${tools_dir}/bin/upgrade-schema.sh" ]; then
    pushd ${tools_dir} > /dev/null
    
    # Set environment variables explicitly for database initialization
    export DATABASE=${db_type}
    export SPRING_PROFILES_ACTIVE=${db_type}
    
    if [ "${db_type}" == "mysql" ]; then
      export SPRING_DATASOURCE_URL="jdbc:mysql://${db_host}:${db_port}/${db_name}?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true"
      export SPRING_DATASOURCE_DRIVER_CLASS_NAME="com.mysql.cj.jdbc.Driver"
    else
      export SPRING_DATASOURCE_URL="jdbc:postgresql://${db_host}:${db_port}/${db_name}"
      export SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.postgresql.Driver"
    fi
    export SPRING_DATASOURCE_USERNAME=${db_user}
    export SPRING_DATASOURCE_PASSWORD="${db_password}"
    
    # Source environment file (for JAVA_HOME etc.)
    source ${dolphinscheduler_install_dir}/bin/env/dolphinscheduler_env.sh
    
    # Run schema initialization
    bash bin/upgrade-schema.sh
    local ret=$?
    popd > /dev/null
    
    if [ ${ret} -eq 0 ]; then
      echo "${CSUCCESS}Database initialized successfully!${CEND}"
    else
      echo "${CFAILURE}Database initialization failed! Please check logs.${CEND}"
      return 1
    fi
  else
    echo "${CWARNING}upgrade-schema.sh not found. Please initialize database manually.${CEND}"
  fi
}

# Install Standalone systemd service
Install_Standalone_Service() {
  echo "${CMSG}Installing Standalone systemd service...${CEND}"

  cat > /lib/systemd/system/dolphinscheduler-standalone.service << EOF
[Unit]
Description=Apache DolphinScheduler Standalone Server
After=network.target
Wants=network-online.target

[Service]
Type=forking
User=${run_user}
Group=${run_group}
Environment="JAVA_HOME=${JAVA_HOME}"
ExecStart=${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh start standalone-server
ExecStop=${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh stop standalone-server
Restart=on-failure
RestartSec=60
StartLimitBurst=3
StartLimitIntervalSec=600
LimitNOFILE=65535
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable dolphinscheduler-standalone
  echo "${CSUCCESS}Standalone service installed.${CEND}"
}

# Echo the roles whose systemd unit is installed on this node
Installed_Cluster_Roles() {
  local role out=""
  for role in master worker api alert; do
    [ -f "/lib/systemd/system/dolphinscheduler-${role}.service" ] && out="${out} ${role}"
  done
  echo ${out}
}

# Write a single systemd unit file
# $1 = role (master|worker|api|alert), $2 = human readable description
Write_Service_Unit() {
  local role=$1
  local description=$2
  local server="${role}-server"

  cat > /lib/systemd/system/dolphinscheduler-${role}.service << EOF
[Unit]
Description=${description}
After=network.target
Wants=network-online.target

[Service]
Type=forking
User=${run_user}
Group=${run_group}
Environment="JAVA_HOME=${JAVA_HOME}"
ExecStart=${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh start ${server}
ExecStop=${dolphinscheduler_install_dir}/bin/dolphinscheduler-daemon.sh stop ${server}
Restart=on-failure
RestartSec=60
StartLimitBurst=3
StartLimitIntervalSec=600
LimitNOFILE=65535
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
EOF
}

# Install systemd services for the roles assigned to this node.
# Units for roles this node no longer serves are stopped and removed.
Install_PseudoCluster_Services() {
  echo "${CMSG}Installing systemd services for roles: ${node_roles:-master,worker,api,alert}...${CEND}"

  local role description
  for role in master worker api alert; do
    case "${role}" in
      master) description="Apache DolphinScheduler Master Server" ;;
      worker) description="Apache DolphinScheduler Worker Server" ;;
      api)    description="Apache DolphinScheduler API Server" ;;
      alert)  description="Apache DolphinScheduler Alert Server" ;;
    esac

    if Has_Role ${role}; then
      Write_Service_Unit "${role}" "${description}"
    elif [ -f "/lib/systemd/system/dolphinscheduler-${role}.service" ]; then
      echo "${CWARNING}Role '${role}' is not assigned to this node, removing its service...${CEND}"
      systemctl stop dolphinscheduler-${role} 2>/dev/null
      systemctl disable dolphinscheduler-${role} 2>/dev/null
      rm -f /lib/systemd/system/dolphinscheduler-${role}.service
    fi
  done

  systemctl daemon-reload

  for role in master worker api alert; do
    Has_Role ${role} && systemctl enable dolphinscheduler-${role}
  done

  echo "${CSUCCESS}Services installed.${CEND}"
}

# Start Standalone server
Start_Standalone() {
  echo "${CMSG}Starting DolphinScheduler Standalone Server...${CEND}"
  systemctl start dolphinscheduler-standalone

  sleep 5
  if systemctl is-active --quiet dolphinscheduler-standalone; then
    echo "${CSUCCESS}Standalone Server started successfully!${CEND}"
  else
    echo "${CFAILURE}Failed to start Standalone Server!${CEND}"
    journalctl -u dolphinscheduler-standalone --no-pager -n 20
    return 1
  fi
}

# Start the services assigned to this node (order: Master -> Worker -> API -> Alert)
Start_PseudoCluster() {
  echo "${CMSG}Starting DolphinScheduler services (roles: ${node_roles:-master,worker,api,alert})...${CEND}"

  local role has_error=0
  for role in master worker api alert; do
    Has_Role ${role} || continue
    systemctl start dolphinscheduler-${role}
    sleep 3
  done

  sleep 5
  echo "${CMSG}Checking service status...${CEND}"
  for role in master worker api alert; do
    Has_Role ${role} || continue
    if systemctl is-active --quiet dolphinscheduler-${role}; then
      echo "${CSUCCESS}[RUNNING]${CEND} ${role}-server"
    else
      echo "${CFAILURE}[FAILED]${CEND} ${role}-server"
      journalctl -u dolphinscheduler-${role} --no-pager -n 20
      has_error=1
    fi
  done

  return ${has_error}
}

# Uninstall DolphinScheduler
Uninstall_DolphinScheduler() {
  echo "${CMSG}Uninstalling DolphinScheduler...${CEND}"

  # Stop all services
  systemctl stop dolphinscheduler-standalone 2>/dev/null
  systemctl stop dolphinscheduler-master 2>/dev/null
  systemctl stop dolphinscheduler-worker 2>/dev/null
  systemctl stop dolphinscheduler-api 2>/dev/null
  systemctl stop dolphinscheduler-alert 2>/dev/null

  # Disable services
  systemctl disable dolphinscheduler-standalone 2>/dev/null
  systemctl disable dolphinscheduler-master 2>/dev/null
  systemctl disable dolphinscheduler-worker 2>/dev/null
  systemctl disable dolphinscheduler-api 2>/dev/null
  systemctl disable dolphinscheduler-alert 2>/dev/null

  # Remove service files
  rm -f /lib/systemd/system/dolphinscheduler-standalone.service
  rm -f /lib/systemd/system/dolphinscheduler-master.service
  rm -f /lib/systemd/system/dolphinscheduler-worker.service
  rm -f /lib/systemd/system/dolphinscheduler-api.service
  rm -f /lib/systemd/system/dolphinscheduler-alert.service
  systemctl daemon-reload

  # Backup data directory
  if [ -d "${dolphinscheduler_data_dir}" ]; then
    local backup_name="${dolphinscheduler_data_dir}_$(date +%Y%m%d%H%M%S)"
    echo "${CMSG}Backing up data directory to ${backup_name}...${CEND}"
    mv ${dolphinscheduler_data_dir} ${backup_name}
  fi

  # Remove installation directory
  if [ -d "${dolphinscheduler_install_dir}" ]; then
    rm -rf ${dolphinscheduler_install_dir}
    echo "${CSUCCESS}Removed ${dolphinscheduler_install_dir}${CEND}"
  fi

  # Remove log directory
  if [ -d "${dolphinscheduler_log_dir}" ]; then
    rm -rf ${dolphinscheduler_log_dir}
    echo "${CSUCCESS}Removed ${dolphinscheduler_log_dir}${CEND}"
  fi

  echo "${CSUCCESS}DolphinScheduler uninstalled successfully!${CEND}"
}
