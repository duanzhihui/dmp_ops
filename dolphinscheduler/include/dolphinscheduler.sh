#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# DolphinScheduler installation and uninstallation functions

#########################################################################
# Generic config file editing helpers
#########################################################################

# All modules that ship a conf/ directory. 'standalone-server' only exists in
# the standalone package, the others only in the cluster package; callers just
# skip the ones that are missing.
ds_all_modules=(tools alert-server api-server master-server worker-server standalone-server)

# Set (or insert) a key inside a YAML block.
# $1 = file
# $2 = awk regex matching the block header line, e.g. '^worker:' or '^  jackson:'
# $3 = indentation (in spaces) of the child key
# $4 = key
# $5 = value
#
# Only the first matching block is touched, so the multi-document profile
# sections further down the file (mysql / postgresql / h2) stay untouched.
# When the key is absent it is appended at the end of the block.
Yaml_Set_Key() {
  local file=$1 anchor=$2 ind=$3 key=$4 value=$5

  [ -f "${file}" ] || return 0

  awk -v anchor="${anchor}" -v ind="${ind}" -v key="${key}" -v value="${value}" '
    function pad(n,  s) { s = ""; while (n-- > 0) s = s " "; return s }
    BEGIN { sp = pad(ind + 0); inside = 0; done = 0; seen = 0 }
    {
      if (!seen && $0 ~ anchor) { seen = 1; inside = 1; print; next }

      if (inside) {
        # blank lines and comments belong to the block, keep scanning
        if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) { print; next }

        match($0, /^[ ]*/)
        cur = RLENGTH

        # dedented line: the block ended, insert the key before it
        if (cur < ind + 0) {
          if (!done) { print sp key ": " value; done = 1 }
          inside = 0
          print
          next
        }

        if (cur == ind + 0 && index($0, sp key ":") == 1) {
          print sp key ": " value
          done = 1
          next
        }
      }
      print
    }
    END { if (inside && !done) print sp key ": " value }
  ' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
}

# Set (or insert) a key in a .properties file. A key that is present but
# commented out is uncommented and reused, so the surrounding documentation
# comments stay meaningful.
# $1 = file, $2 = key, $3 = value
Properties_Set() {
  local file=$1 key=$2 value=$3

  [ -f "${file}" ] || return 0

  # '.' is the only regex metacharacter that occurs in DolphinScheduler keys
  local key_re=${key//./\\.}
  # protect the sed replacement text
  local value_esc
  value_esc=$(printf '%s' "${value}" | sed -e 's/[\\&|]/\\&/g')

  if grep -qE "^[[:space:]]*#?[[:space:]]*${key_re}=" "${file}"; then
    sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key_re}=.*|${key}=${value_esc}|" "${file}"
  else
    echo "${key}=${value}" >> "${file}"
  fi
}

# Return 0 when ${1} (e.g. 3.3.2) is >= ${2} (e.g. 3.3)
Version_Ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]
}

#########################################################################

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

  Configure_Common_Properties
  Configure_Timezone
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

  # Initialize database (shared schema: only done once, on the first node).
  # Worker groups live in the same shared schema on 3.2.x, so they are
  # registered together with it.
  if [ "${skip_db_init}" == "y" ]; then
    echo "${CMSG}Skipping database initialization (schema already initialized by the first node).${CEND}"
  else
    Init_Database || return 1
    Register_Worker_Groups_DB "${ds_ver}"
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
export REGISTRY_ZOOKEEPER_NAMESPACE=${registry_namespace:-dolphinscheduler}
# End DolphinSchedulerStack Configuration
EOF

    echo "${CSUCCESS}Environment variables configured in ${env_file}${CEND}"
  else
    echo "${CFAILURE}Environment file not found: ${env_file}${CEND}"
    return 1
  fi

  # Configure application.yaml files for each module
  Configure_Application_Yaml "${ds_ver}"

  # Configure common.properties (resource storage, network, working dir)
  Configure_Common_Properties

  # Align the JSON timezone of every module with options.conf
  Configure_Timezone
}

# NOTE: bin/env/install_env.sh is deliberately NOT written.
# It is only read by DolphinScheduler's own install.sh, which this toolkit
# never runs (services are started through systemd units written by
# Write_Service_Unit). Writing it would only create the illusion that
# 'workers=ip:group' has been applied - the group is handled by
# Configure_Worker_Group / Register_Worker_Groups_DB instead.

# Configure application.yaml files
# $1 = DolphinScheduler version (e.g. 3.3.2)
Configure_Application_Yaml() {
  local ds_ver=$1
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
          Configure_Load_Protection "${yaml_file}" "master"
          ;;
        worker-server)
          Configure_Worker_Server_Ports "${yaml_file}" "${worker_rpc_port}" "${worker_web_port}"
          Configure_Worker_Group "${yaml_file}" "${ds_ver}"
          Configure_Load_Protection "${yaml_file}" "worker"
          ;;
        alert-server)
          Configure_Alert_Server_Ports "${yaml_file}" "${alert_rpc_port}" "${alert_web_port}"
          ;;
      esac

      # Every role must use the same registry namespace, otherwise masters and
      # workers register into different trees and never see each other.
      Yaml_Set_Key "${yaml_file}" '^  zookeeper:' 4 "namespace" "${registry_namespace:-dolphinscheduler}"
    fi
  done
}

# Resolve the worker group of the local node from the 'workers' list
# (format: ip:group,ip:group). Falls back to 'default'.
Get_Local_Worker_Group() {
  local entry ip group
  for entry in ${workers//,/ }; do
    ip=${entry%%:*}
    group=${entry#*:}
    [ "${group}" == "${entry}" ] && group="default"
    if Is_Local_Node "${ip}"; then
      echo "${group:-default}"
      return 0
    fi
  done
  echo "default"
  return 1
}

# Configure the worker group of this node.
#
# DolphinScheduler 3.3+ takes the group from worker.group in application.yaml
# and registers under /<namespace>/nodes/worker/<group>/<host:port>.
# DolphinScheduler 3.2.x has no such setting: groups live in the
# t_ds_worker_group table and are written by Register_Worker_Groups_DB.
#
# $1 = worker-server application.yaml, $2 = DolphinScheduler version
Configure_Worker_Group() {
  local yaml_file=$1
  local ds_ver=$2
  local group

  group=$(Get_Local_Worker_Group) || \
    echo "${CWARNING}This node is not listed in 'workers', falling back to group 'default'.${CEND}"

  if Version_Ge "${ds_ver}" "3.3"; then
    echo "${CMSG}Configuring worker group: ${group}...${CEND}"
    Yaml_Set_Key "${yaml_file}" '^worker:' 2 "group" "${group}"
  else
    echo "${CMSG}DolphinScheduler ${ds_ver}: worker group '${group}' is registered in t_ds_worker_group.${CEND}"
  fi
}

# Configure master/worker overload protection.
# With the shipped defaults (0.7 in 3.2.x, 0.8 in 3.3+) a node that is merely
# a bit loaded reports itself BUSY; the master then refuses to dispatch to it
# and task instances keep an empty host.
#
# $1 = application.yaml, $2 = section (master|worker)
Configure_Load_Protection() {
  local yaml_file=$1
  local section=$2
  local enabled=${server_load_protection_enabled:-false}

  echo "${CMSG}Configuring ${section} server-load-protection (enabled=${enabled})...${CEND}"

  Yaml_Set_Key "${yaml_file}" '^  server-load-protection:' 4 "enabled" "${enabled}"

  if [ "${enabled}" == "true" ]; then
    Yaml_Set_Key "${yaml_file}" '^  server-load-protection:' 4 \
      "max-system-cpu-usage-percentage-thresholds" "${server_load_protection_max_cpu:-0.9}"
    Yaml_Set_Key "${yaml_file}" '^  server-load-protection:' 4 \
      "max-jvm-cpu-usage-percentage-thresholds" "${server_load_protection_max_jvm_cpu:-0.9}"
    Yaml_Set_Key "${yaml_file}" '^  server-load-protection:' 4 \
      "max-system-memory-usage-percentage-thresholds" "${server_load_protection_max_memory:-0.9}"
    Yaml_Set_Key "${yaml_file}" '^  server-load-protection:' 4 \
      "max-disk-usage-percentage-thresholds" "${server_load_protection_max_disk:-0.9}"
  fi
}

# Align spring.jackson.time-zone of every module with options.conf.
# The packages ship 'UTC', which makes every timestamp in the UI (and in the
# task instance list you look at while debugging) off by the UTC offset.
Configure_Timezone() {
  local tz=${timezone}
  [ -z "${tz}" ] && return 0

  echo "${CMSG}Configuring timezone: ${tz}...${CEND}"

  local module yaml_file
  for module in "${ds_all_modules[@]}"; do
    yaml_file="${dolphinscheduler_install_dir}/${module}/conf/application.yaml"
    [ -f "${yaml_file}" ] || continue
    Yaml_Set_Key "${yaml_file}" '^  jackson:' 4 "time-zone" "${tz}"
  done
}

# Configure conf/common.properties of every module.
#
# Without this the resource storage settings collected in options.conf are
# never applied, and - more importantly - the network settings keep their
# defaults, so on a multi-NIC host a server may register an address the other
# nodes cannot reach (task dispatch then fails and host stays empty).
Configure_Common_Properties() {
  echo "${CMSG}Configuring common.properties...${CEND}"

  local storage=${resource_storage_type:-LOCAL}
  local basedir=${data_basedir_path:-/data/dolphinscheduler/exec}

  if [ "${deploy_mode}" == "cluster" ] && [ "${storage}" == "LOCAL" ]; then
    echo "${CWARNING}resource_storage_type=LOCAL in cluster mode: ${resource_local_path} must be a shared mount,${CEND}"
    echo "${CWARNING}otherwise a task will not find resources uploaded through another node.${CEND}"
  fi

  mkdir -p "${basedir}"
  chown -R ${run_user}:${run_group} "${basedir}" 2>/dev/null

  local module prop
  for module in "${ds_all_modules[@]}"; do
    prop="${dolphinscheduler_install_dir}/${module}/conf/common.properties"
    [ -f "${prop}" ] || continue

    Properties_Set "${prop}" "data.basedir.path" "${basedir}"
    Properties_Set "${prop}" "resource.storage.type" "${storage}"

    case "${storage}" in
      LOCAL)
        # LOCAL is HDFS with a file:/// defaultFS
        mkdir -p "${resource_local_path:-/data/dolphinscheduler/resource}"
        chown -R ${run_user}:${run_group} "${resource_local_path:-/data/dolphinscheduler/resource}" 2>/dev/null
        Properties_Set "${prop}" "resource.storage.upload.base.path" "${resource_local_path:-/data/dolphinscheduler/resource}"
        Properties_Set "${prop}" "resource.hdfs.fs.defaultFS" "file:///"
        ;;
      HDFS)
        Properties_Set "${prop}" "resource.storage.upload.base.path" "${hdfs_root_path:-/dolphinscheduler}"
        Properties_Set "${prop}" "resource.hdfs.fs.defaultFS" "${hdfs_defaultfs}"
        Properties_Set "${prop}" "resource.hdfs.root.user" "${hdfs_root_user:-hdfs}"
        ;;
      S3)
        Properties_Set "${prop}" "resource.storage.upload.base.path" "${hdfs_root_path:-/dolphinscheduler}"
        Properties_Set "${prop}" "resource.aws.s3.endpoint" "${s3_endpoint}"
        Properties_Set "${prop}" "resource.aws.access.key.id" "${s3_access_key}"
        Properties_Set "${prop}" "resource.aws.secret.access.key" "${s3_secret_key}"
        Properties_Set "${prop}" "resource.aws.region" "${s3_region}"
        Properties_Set "${prop}" "resource.aws.s3.bucket.name" "${s3_bucket}"
        ;;
    esac

    # Registry address selection
    if [ -n "${network_interface_preferred}" ]; then
      Properties_Set "${prop}" "dolphin.scheduler.network.interface.preferred" "${network_interface_preferred}"
    fi
    Properties_Set "${prop}" "dolphin.scheduler.network.interface.restrict" "${network_interface_restrict:-docker0}"
    Properties_Set "${prop}" "dolphin.scheduler.network.priority.strategy" "${network_priority_strategy:-default}"
  done

  echo "${CSUCCESS}common.properties configured (storage=${storage}).${CEND}"
}

# Register the worker groups declared in 'workers' into t_ds_worker_group.
# Only needed for DolphinScheduler 3.2.x, where the group is a database
# mapping from group name to a list of <ip>:<worker listen port>.
# Runs once, on the node that initializes the shared schema.
Register_Worker_Groups_DB() {
  local ds_ver=$1

  Version_Ge "${ds_ver}" "3.3" && return 0

  # Build "group -> addr list" from workers=ip:group,...
  local entry ip group groups="" addrs
  declare -A group_addrs=()
  for entry in ${workers//,/ }; do
    ip=${entry%%:*}
    group=${entry#*:}
    [ "${group}" == "${entry}" ] && group="default"
    # 'default' is implicit in 3.2.x: it matches every registered worker
    [ "${group}" == "default" ] && continue
    if [ -z "${group_addrs[${group}]:-}" ]; then
      group_addrs[${group}]="${ip}:${worker_rpc_port:-1234}"
      groups="${groups} ${group}"
    else
      group_addrs[${group}]="${group_addrs[${group}]},${ip}:${worker_rpc_port:-1234}"
    fi
  done

  [ -z "${groups}" ] && return 0

  echo "${CMSG}Registering worker groups in t_ds_worker_group:${groups}${CEND}"

  local sql=""
  for group in ${groups}; do
    addrs="${group_addrs[${group}]}"
    if [ "${db_type}" == "mysql" ]; then
      sql="${sql} INSERT INTO t_ds_worker_group (name, addr_list, create_time, update_time, description) VALUES ('${group}', '${addrs}', NOW(), NOW(), 'created by DolphinSchedulerStack') ON DUPLICATE KEY UPDATE addr_list='${addrs}', update_time=NOW();"
    else
      sql="${sql} INSERT INTO t_ds_worker_group (name, addr_list, create_time, update_time, description) VALUES ('${group}', '${addrs}', NOW(), NOW(), 'created by DolphinSchedulerStack') ON CONFLICT (name) DO UPDATE SET addr_list='${addrs}', update_time=NOW();"
    fi
  done

  local rc=0
  if [ "${db_type}" == "mysql" ]; then
    mysql -h${db_host} -P${db_port} -u${db_user} -p"${db_password}" ${db_name} -e "${sql}" || rc=1
  else
    PGPASSWORD="${db_password}" psql -h ${db_host} -p ${db_port} -U ${db_user} -d ${db_name} -c "${sql}" || rc=1
  fi

  if [ ${rc} -ne 0 ]; then
    echo "${CWARNING}Failed to register worker groups. Create them manually in${CEND}"
    echo "${CWARNING}Security -> Worker Group Manage, otherwise tasks bound to${CEND}"
    echo "${CWARNING}these groups will never be dispatched (empty host).${CEND}"
    return 1
  fi

  echo "${CSUCCESS}Worker groups registered.${CEND}"
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
