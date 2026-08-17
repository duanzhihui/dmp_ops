#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Cluster deployment functions
#
# Supports:
#   integrated  - 存算一体集群 (FE + BE)
#   separated   - 存算分离集群 (FDB + MS + FE + BE + Storage Vault, 3.x+)

# ========================================================================
# 存算一体 (Integrated Storage-Compute) Cluster Deployment
# ========================================================================
Deploy_Integrated_Cluster() {
  local doris_ver=$1

  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Deploying 存算一体 Cluster ${doris_ver}${CEND}"
  echo "${CMSG}============================================${CEND}"

  # Parse FE nodes
  IFS=',' read -ra FE_ARRAY <<< "${fe_nodes}"
  if [ ${#FE_ARRAY[@]} -eq 0 ]; then
    echo "${CFAILURE}No FE nodes configured! Please set fe_nodes in options.conf${CEND}"
    return 1
  fi

  # Parse BE nodes
  IFS=',' read -ra BE_ARRAY <<< "${be_nodes}"
  if [ ${#BE_ARRAY[@]} -eq 0 ]; then
    echo "${CFAILURE}No BE nodes configured! Please set be_nodes in options.conf${CEND}"
    return 1
  fi

  local master_fe_host=$(echo ${FE_ARRAY[0]} | awk -F: '{print $1}')
  local master_fe_port=$(echo ${FE_ARRAY[0]} | awk -F: '{print $2}')
  master_fe_port=${master_fe_port:-${fe_edit_log_port}}

  echo "${CMSG}FE Master: ${master_fe_host}:${master_fe_port}${CEND}"
  echo "${CMSG}FE nodes: ${#FE_ARRAY[@]}${CEND}"
  echo "${CMSG}BE nodes: ${#BE_ARRAY[@]}${CEND}"

  local failed_nodes=""

  # Step 1: Deploy FE Master
  echo ""
  echo "${CMSG}[Step 1/4] Deploying FE Master on ${master_fe_host}...${CEND}"
  Remote_Deploy_FE "${master_fe_host}" "${doris_ver}" "" || {
    echo "${CFAILURE}FE Master deployment failed, aborting cluster deployment.${CEND}"
    return 1
  }

  # Wait for FE Master to start
  Wait_FE_Ready "${master_fe_host}" || return 1

  # Step 2: Deploy FE Followers (must be registered on Master before they start)
  if [ ${#FE_ARRAY[@]} -gt 1 ]; then
    echo ""
    echo "${CMSG}[Step 2/4] Deploying FE Follower nodes...${CEND}"
    for ((i=1; i<${#FE_ARRAY[@]}; i++)); do
      local fe_host=$(echo ${FE_ARRAY[$i]} | awk -F: '{print $1}')
      local fe_port=$(echo ${FE_ARRAY[$i]} | awk -F: '{print $2}')
      fe_port=${fe_port:-${fe_edit_log_port}}

      echo "${CMSG}  Registering FE Follower: ${fe_host}:${fe_port}${CEND}"
      if ! Register_FE_Follower "${master_fe_host}" "${fe_host}" "${fe_port}"; then
        failed_nodes="${failed_nodes} FE:${fe_host}"
        continue
      fi
      Remote_Deploy_FE "${fe_host}" "${doris_ver}" "${master_fe_host}:${master_fe_port}" \
        || failed_nodes="${failed_nodes} FE:${fe_host}"
    done
  else
    echo ""
    echo "${CMSG}[Step 2/4] Skipped (single FE node)${CEND}"
  fi

  # Step 3: Deploy BE nodes (install first, register afterwards)
  echo ""
  echo "${CMSG}[Step 3/4] Deploying BE nodes...${CEND}"
  for be_node in "${BE_ARRAY[@]}"; do
    local be_host=$(echo ${be_node} | awk -F: '{print $1}')
    local be_port=$(echo ${be_node} | awk -F: '{print $2}')
    be_port=${be_port:-${be_heartbeat_service_port}}

    if ! Remote_Deploy_BE "${be_host}" "${doris_ver}"; then
      failed_nodes="${failed_nodes} BE:${be_host}"
      continue
    fi
    echo "${CMSG}  Registering BE: ${be_host}:${be_port}${CEND}"
    Register_BE "${master_fe_host}" "${be_host}" "${be_port}" \
      || failed_nodes="${failed_nodes} BE:${be_host}"
  done

  if [ -n "${failed_nodes}" ]; then
    echo ""
    echo "${CFAILURE}Some nodes failed to deploy:${failed_nodes}${CEND}"
  fi

  # Step 4: Verify cluster
  echo ""
  echo "${CMSG}[Step 4/4] Verifying cluster...${CEND}"
  Wait_Nodes_Alive "${master_fe_host}" "${#FE_ARRAY[@]}" "${#BE_ARRAY[@]}"
  Verify_Cluster "${master_fe_host}"

  Print_Cluster_Summary "${master_fe_host}" "integrated"
}

# ========================================================================
# 存算分离 (Separating Storage-Compute) Cluster Deployment
# ========================================================================
Deploy_Separated_Cluster() {
  local doris_ver=$1
  local major_ver=${doris_ver%%.*}

  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Deploying 存算分离 Cluster ${doris_ver}${CEND}"
  echo "${CMSG}============================================${CEND}"

  # Version check
  if [ "${major_ver}" -lt 3 ]; then
    echo "${CFAILURE}Doris ${doris_ver} does not support 存算分离 mode!${CEND}"
    echo "${CFAILURE}Separating storage-compute requires Doris 3.x+${CEND}"
    return 1
  fi

  # Parse nodes
  IFS=',' read -ra FE_ARRAY <<< "${fe_nodes}"
  IFS=',' read -ra BE_ARRAY <<< "${be_nodes}"
  IFS=',' read -ra FDB_ARRAY <<< "${fdb_nodes}"
  IFS=',' read -ra MS_ARRAY <<< "${ms_nodes}"

  if [ ${#FE_ARRAY[@]} -eq 0 ]; then
    echo "${CFAILURE}No FE nodes configured!${CEND}"; return 1
  fi
  if [ ${#BE_ARRAY[@]} -eq 0 ]; then
    echo "${CFAILURE}No BE nodes configured!${CEND}"; return 1
  fi
  if [ ${#FDB_ARRAY[@]} -eq 0 ]; then
    echo "${CFAILURE}No FDB nodes configured! Required for 存算分离 mode.${CEND}"; return 1
  fi
  if [ ${#MS_ARRAY[@]} -eq 0 ]; then
    echo "${CFAILURE}No MS nodes configured! Required for 存算分离 mode.${CEND}"; return 1
  fi

  local total_steps=8
  local master_fe_host=$(echo ${FE_ARRAY[0]} | awk -F: '{print $1}')
  local master_fe_port=$(echo ${FE_ARRAY[0]} | awk -F: '{print $2}')
  master_fe_port=${master_fe_port:-${fe_edit_log_port}}

  echo "${CMSG}Architecture: 存算分离 (Separating Storage-Compute)${CEND}"
  echo "${CMSG}FDB nodes: ${#FDB_ARRAY[@]}${CEND}"
  echo "${CMSG}MS  nodes: ${#MS_ARRAY[@]}${CEND}"
  echo "${CMSG}FE  nodes: ${#FE_ARRAY[@]}${CEND}"
  echo "${CMSG}BE  nodes: ${#BE_ARRAY[@]}${CEND}"

  # Step 1: Deploy FoundationDB
  echo ""
  echo "${CMSG}[Step 1/${total_steps}] Deploying FoundationDB...${CEND}"
  Deploy_FDB_With_Scripts "${doris_ver}"
  if [ -z "${fdb_cluster}" ]; then
    echo "${CFAILURE}FDB deployment failed or cluster string not available!${CEND}"
    return 1
  fi

  # Step 2: (Optional) S3/HDFS - just validate config
  echo ""
  echo "${CMSG}[Step 2/${total_steps}] Checking storage backend...${CEND}"
  if [ "${storage_vault_type}" == "S3" ] && [ -n "${s3_endpoint}" ]; then
    echo "${CSUCCESS}S3 storage configured: ${s3_endpoint}/${s3_bucket}${CEND}"
  elif [ "${storage_vault_type}" == "HDFS" ] && [ -n "${hdfs_defaultfs}" ]; then
    echo "${CSUCCESS}HDFS storage configured: ${hdfs_defaultfs}${CEND}"
  else
    echo "${CWARNING}Storage Vault not pre-configured. You can configure it after deployment.${CEND}"
  fi

  # Generate the cloud cluster id ONCE, so every FE node shares the same value
  if [ -z "${cloud_cluster_id}" ]; then
    cloud_cluster_id=$(echo $(($((RANDOM << 15)) | $RANDOM)))
    echo "${CMSG}Generated cloud cluster_id: ${cloud_cluster_id}${CEND}"
  fi

  local failed_nodes=""

  # Step 3: Deploy Meta Service
  echo ""
  echo "${CMSG}[Step 3/${total_steps}] Deploying Meta Service...${CEND}"
  for ms_node in "${MS_ARRAY[@]}"; do
    local ms_host=$(echo ${ms_node} | awk -F: '{print $1}')
    Remote_Deploy_MS "${ms_host}" "${doris_ver}" || {
      echo "${CFAILURE}Meta Service deployment failed on ${ms_host}, aborting.${CEND}"
      return 1
    }
  done

  # Step 4: (Optional) Data recycling - skip for now
  echo ""
  echo "${CMSG}[Step 4/${total_steps}] Data recycling (skipped, uses MS default)${CEND}"

  # Step 5: Deploy FE Master
  echo ""
  echo "${CMSG}[Step 5/${total_steps}] Deploying FE Master on ${master_fe_host}...${CEND}"
  Remote_Deploy_FE "${master_fe_host}" "${doris_ver}" "" || {
    echo "${CFAILURE}FE Master deployment failed, aborting cluster deployment.${CEND}"
    return 1
  }

  Wait_FE_Ready "${master_fe_host}" || return 1

  # Step 6: Deploy FE Followers (must be registered on Master before they start)
  if [ ${#FE_ARRAY[@]} -gt 1 ]; then
    echo ""
    echo "${CMSG}[Step 6/${total_steps}] Deploying FE Follower nodes...${CEND}"
    for ((i=1; i<${#FE_ARRAY[@]}; i++)); do
      local fe_host=$(echo ${FE_ARRAY[$i]} | awk -F: '{print $1}')
      local fe_port=$(echo ${FE_ARRAY[$i]} | awk -F: '{print $2}')
      fe_port=${fe_port:-${fe_edit_log_port}}

      if ! Register_FE_Follower "${master_fe_host}" "${fe_host}" "${fe_port}"; then
        failed_nodes="${failed_nodes} FE:${fe_host}"
        continue
      fi
      Remote_Deploy_FE "${fe_host}" "${doris_ver}" "${master_fe_host}:${master_fe_port}" \
        || failed_nodes="${failed_nodes} FE:${fe_host}"
    done
  else
    echo ""
    echo "${CMSG}[Step 6/${total_steps}] Skipped (single FE node)${CEND}"
  fi

  # Step 7: Deploy BE nodes (install first, register afterwards)
  echo ""
  echo "${CMSG}[Step 7/${total_steps}] Deploying BE nodes...${CEND}"
  for be_node in "${BE_ARRAY[@]}"; do
    local be_host=$(echo ${be_node} | awk -F: '{print $1}')
    local be_port=$(echo ${be_node} | awk -F: '{print $2}')
    be_port=${be_port:-${be_heartbeat_service_port}}

    if ! Remote_Deploy_BE "${be_host}" "${doris_ver}"; then
      failed_nodes="${failed_nodes} BE:${be_host}"
      continue
    fi
    Register_BE "${master_fe_host}" "${be_host}" "${be_port}" \
      || failed_nodes="${failed_nodes} BE:${be_host}"
  done

  if [ -n "${failed_nodes}" ]; then
    echo ""
    echo "${CFAILURE}Some nodes failed to deploy:${failed_nodes}${CEND}"
  fi

  # Step 8: Create Storage Vault
  echo ""
  echo "${CMSG}[Step 8/${total_steps}] Configuring Storage Vault...${CEND}"
  Create_Storage_Vault "${master_fe_host}"

  # Verify
  Wait_Nodes_Alive "${master_fe_host}" "${#FE_ARRAY[@]}" "${#BE_ARRAY[@]}"
  Verify_Cluster "${master_fe_host}"

  Print_Cluster_Summary "${master_fe_host}" "separated"
}

# ========================================================================
# Storage Vault creation (for 存算分离 mode)
# ========================================================================
Create_Storage_Vault() {
  local fe_ip=$1

  if [ "${storage_vault_type}" == "S3" ] && [ -n "${s3_endpoint}" ]; then
    echo "${CMSG}Creating S3 Storage Vault...${CEND}"
    mysql -uroot -P${fe_query_port} -h${fe_ip} << EOF
CREATE STORAGE VAULT IF NOT EXISTS s3_vault
    PROPERTIES (
    "type"="S3",
    "s3.endpoint"="${s3_endpoint}",
    "s3.access_key" = "${s3_access_key}",
    "s3.secret_key" = "${s3_secret_key}",
    "s3.region" = "${s3_region}",
    "s3.root.path" = "${s3_root_path}",
    "s3.bucket" = "${s3_bucket}",
    "provider" = "${s3_provider}");
SET s3_vault AS DEFAULT STORAGE VAULT;
EOF
    if [ $? -eq 0 ]; then
      echo "${CSUCCESS}S3 Storage Vault created and set as default!${CEND}"
    else
      echo "${CWARNING}Failed to create S3 Storage Vault. Please configure manually.${CEND}"
    fi

  elif [ "${storage_vault_type}" == "HDFS" ] && [ -n "${hdfs_defaultfs}" ]; then
    echo "${CMSG}Creating HDFS Storage Vault...${CEND}"
    mysql -uroot -P${fe_query_port} -h${fe_ip} << EOF
CREATE STORAGE VAULT IF NOT EXISTS hdfs_vault
    PROPERTIES (
    "type"="hdfs",
    "fs.defaultFS"="${hdfs_defaultfs}");
SET hdfs_vault AS DEFAULT STORAGE VAULT;
EOF
    if [ $? -eq 0 ]; then
      echo "${CSUCCESS}HDFS Storage Vault created and set as default!${CEND}"
    else
      echo "${CWARNING}Failed to create HDFS Storage Vault. Please configure manually.${CEND}"
    fi
  else
    echo "${CWARNING}Storage Vault not configured. Please create one manually:${CEND}"
    echo "  mysql -uroot -P${fe_query_port} -h${fe_ip}"
    echo '  CREATE STORAGE VAULT IF NOT EXISTS my_vault PROPERTIES ("type"="S3", ...);'
    echo '  SET my_vault AS DEFAULT STORAGE VAULT;'
  fi
}

# ========================================================================
# Common helper functions
# ========================================================================
Wait_FE_Ready() {
  local fe_host=$1
  echo "${CMSG}Waiting for FE Master to be ready...${CEND}"
  local retry=0
  while [ ${retry} -lt 30 ]; do
    if mysql -uroot -P${fe_query_port} -h${fe_host} -e "show frontends" > /dev/null 2>&1; then
      echo "${CSUCCESS}FE Master is ready!${CEND}"
      return 0
    fi
    sleep 5
    retry=$((retry + 1))
  done
  echo "${CFAILURE}FE Master failed to start within timeout!${CEND}"
  return 1
}

# Wait until all FE/BE nodes report Alive, so validation does not run too early
Wait_Nodes_Alive() {
  local fe_ip=$1
  local fe_expected=$2
  local be_expected=$3
  local retry=0
  local fe_alive=0
  local be_alive=0

  echo "${CMSG}Waiting for cluster nodes to come online...${CEND}"
  while [ ${retry} -lt 36 ]; do
    fe_alive=$(mysql -uroot -P${fe_query_port} -h${fe_ip} -e "show frontends\G" 2>/dev/null | grep -c "Alive: true")
    be_alive=$(mysql -uroot -P${fe_query_port} -h${fe_ip} -e "show backends\G" 2>/dev/null | grep -c "Alive: true")
    if [ "${fe_alive}" -ge "${fe_expected}" ] && [ "${be_alive}" -ge "${be_expected}" ]; then
      echo "${CSUCCESS}All nodes are alive (FE: ${fe_alive}/${fe_expected}, BE: ${be_alive}/${be_expected})${CEND}"
      return 0
    fi
    sleep 5
    retry=$((retry + 1))
  done

  echo "${CWARNING}Not all nodes are alive yet (FE: ${fe_alive}/${fe_expected}, BE: ${be_alive}/${be_expected})${CEND}"
  return 1
}

Is_Local_Host() {
  local host=$1
  [ "${host}" == "127.0.0.1" ] || [ "${host}" == "localhost" ] && return 0
  hostname -I | tr ' ' '\n' | grep -qx "${host}" && return 0
  return 1
}

# Start the whole FE cluster in order: master first, then followers.
# This guarantees the original master stays master after a restart and
# avoids the "all followers, no master" + meta divergence problem that
# happens when every FE boots simultaneously with `start_fe.sh --daemon`.
# Each follower's systemd unit already carries `--helper <master:port>`,
# so once the master is up they resync from it.
Start_FE_Cluster() {
  if [ -z "${fe_nodes}" ]; then
    echo "${CFAILURE}fe_nodes not configured in options.conf${CEND}"
    return 1
  fi

  IFS=',' read -ra FE_ARRAY <<< "${fe_nodes}"
  local master_fe_host=$(echo ${FE_ARRAY[0]} | awk -F: '{print $1}')
  local master_fe_port=$(echo ${FE_ARRAY[0]} | awk -F: '{print $2}')
  master_fe_port=${master_fe_port:-${fe_edit_log_port}}

  Build_SSH_Opts

  # 1. Start master node first
  echo "${CMSG}[1] Starting FE Master on ${master_fe_host}...${CEND}"
  if Is_Local_Host "${master_fe_host}"; then
    systemctl start doris-fe
  else
    ssh ${ssh_opts} ${ssh_user}@${master_fe_host} "systemctl start doris-fe"
  fi
  if [ $? -ne 0 ]; then
    echo "${CFAILURE}Failed to start FE Master on ${master_fe_host}!${CEND}"
    return 1
  fi

  # 2. Wait for master to be ready (MySQL port reachable)
  echo "${CMSG}[2] Waiting for FE Master to be ready...${CEND}"
  local retry=0
  while [ ${retry} -lt 30 ]; do
    if mysql -uroot -P${fe_query_port} -h${master_fe_host} -e "show frontends" > /dev/null 2>&1; then
      echo "${CSUCCESS}FE Master is ready!${CEND}"
      break
    fi
    sleep 5
    retry=$((retry + 1))
  done
  if [ ${retry} -ge 30 ]; then
    echo "${CFAILURE}FE Master failed to become ready within timeout!${CEND}"
    echo "${CFAILURE}Aborting follower startup to avoid meta divergence.${CEND}"
    return 1
  fi

  # 3. Start follower nodes one by one
  local idx=0
  for ((i=1; i<${#FE_ARRAY[@]}; i++)); do
    local fe_host=$(echo ${FE_ARRAY[$i]} | awk -F: '{print $1}')
    idx=$((idx + 1))
    echo "${CMSG}[$((2 + idx))] Starting FE Follower on ${fe_host}...${CEND}"
    if Is_Local_Host "${fe_host}"; then
      systemctl start doris-fe
    else
      ssh ${ssh_opts} ${ssh_user}@${fe_host} "systemctl start doris-fe"
    fi
    if [ $? -ne 0 ]; then
      echo "${CWARNING}Failed to start FE Follower on ${fe_host}${CEND}"
    fi
  done

  echo "${CSUCCESS}FE cluster start sequence completed.${CEND}"
}

# Stop the whole FE cluster in reverse order: followers first, master last.
Stop_FE_Cluster() {
  if [ -z "${fe_nodes}" ]; then
    echo "${CFAILURE}fe_nodes not configured in options.conf${CEND}"
    return 1
  fi

  IFS=',' read -ra FE_ARRAY <<< "${fe_nodes}"
  local master_fe_host=$(echo ${FE_ARRAY[0]} | awk -F: '{print $1}')

  Build_SSH_Opts

  # 1. Stop follower nodes first
  for ((i=${#FE_ARRAY[@]} - 1; i >= 1; i--)); do
    local fe_host=$(echo ${FE_ARRAY[$i]} | awk -F: '{print $1}')
    echo "${CMSG}Stopping FE Follower on ${fe_host}...${CEND}"
    if Is_Local_Host "${fe_host}"; then
      systemctl stop doris-fe
    else
      ssh ${ssh_opts} ${ssh_user}@${fe_host} "systemctl stop doris-fe"
    fi
  done

  # 2. Stop master last
  echo "${CMSG}Stopping FE Master on ${master_fe_host}...${CEND}"
  if Is_Local_Host "${master_fe_host}"; then
    systemctl stop doris-fe
  else
    ssh ${ssh_opts} ${ssh_user}@${master_fe_host} "systemctl stop doris-fe"
  fi

  echo "${CSUCCESS}FE cluster stop sequence completed.${CEND}"
}

# Build ssh/scp option strings.
# NOTE: ssh uses -p for the port, scp uses -P (scp's -p means "preserve times").
Build_SSH_Opts() {
  ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -p ${ssh_port}"
  scp_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -P ${ssh_port}"
  if [ -n "${ssh_key_file}" ]; then
    ssh_opts="${ssh_opts} -i ${ssh_key_file}"
    scp_opts="${scp_opts} -i ${ssh_key_file}"
  fi
}

# Runtime values that cannot be read from options.conf on the remote node
# (auto-detected or generated during this deployment).
Write_Deploy_Env() {
  local env_file=$1
  cat > ${env_file} << EOF
# Auto-generated by DorisStack, do not edit. Sourced after options.conf.
deploy_mode=${deploy_mode}
fe_nodes=${fe_nodes}
be_nodes=${be_nodes}
ms_nodes=${ms_nodes}
fdb_nodes=${fdb_nodes}
fdb_cluster=${fdb_cluster}
cloud_cluster_id=${cloud_cluster_id}
EOF
}

Sync_Deploy_Files() {
  local host=$1
  local doris_ver=$2
  local base=$(basename ${doris_dir})
  local remote_dir="/tmp/doris_deploy/${base}"
  local doris_pkg=$(Get_Doris_Pkg "${doris_ver}")

  if ! ssh ${ssh_opts} ${ssh_user}@${host} "mkdir -p ${remote_dir}/src"; then
    echo "${CFAILURE}  Cannot connect to ${ssh_user}@${host}:${ssh_port}!${CEND}"
    return 1
  fi

  # Scripts and configs only (the package is handled separately, it is several GB)
  echo "${CMSG}  Syncing deployment scripts to ${host}...${CEND}"
  if ! tar czf - -C "$(dirname ${doris_dir})" --exclude="${base}/src" "${base}" \
      | ssh ${ssh_opts} ${ssh_user}@${host} "tar xzf - -C /tmp/doris_deploy"; then
    echo "${CFAILURE}  Failed to copy deployment files to ${host}!${CEND}"
    return 1
  fi

  # Copy the package only when it is missing or incomplete on the remote node
  if [ -f "${doris_dir}/src/${doris_pkg}" ]; then
    local local_size=$(stat -c %s "${doris_dir}/src/${doris_pkg}")
    local remote_size=$(ssh ${ssh_opts} ${ssh_user}@${host} \
      "stat -c %s ${remote_dir}/src/${doris_pkg} 2>/dev/null || echo 0")
    if [ "${local_size}" == "${remote_size}" ]; then
      echo "${CMSG}  Package already present on ${host}, skipping copy.${CEND}"
    else
      echo "${CMSG}  Copying package to ${host}...${CEND}"
      if ! scp ${scp_opts} "${doris_dir}/src/${doris_pkg}" ${ssh_user}@${host}:${remote_dir}/src/; then
        echo "${CFAILURE}  Failed to copy package to ${host}!${CEND}"
        return 1
      fi
    fi
  fi

  local env_file=$(mktemp)
  Write_Deploy_Env "${env_file}"
  if ! scp ${scp_opts} ${env_file} ${ssh_user}@${host}:${remote_dir}/.deploy_env; then
    rm -f ${env_file}
    echo "${CFAILURE}  Failed to copy deployment context to ${host}!${CEND}"
    return 1
  fi
  rm -f ${env_file}
  return 0
}

Remote_Deploy_Component() {
  local host=$1
  local doris_ver=$2
  local component=$3
  local extra_args=$4
  local remote_dir="/tmp/doris_deploy/$(basename ${doris_dir})"

  Build_SSH_Opts
  Sync_Deploy_Files "${host}" "${doris_ver}" || return 1

  echo "${CMSG}  Installing ${component^^} on ${host}...${CEND}"
  if ! ssh ${ssh_opts} ${ssh_user}@${host} "cd ${remote_dir} && bash install.sh --${component}_only --doris_ver ${doris_ver} ${extra_args} --quiet"; then
    echo "${CFAILURE}  ${component^^} installation failed on ${host}!${CEND}"
    return 1
  fi
  return 0
}

Remote_Deploy_FE() {
  local host=$1
  local doris_ver=$2
  local helper_node=$3

  if Is_Local_Host "${host}"; then
    Install_FE "${doris_ver}" "${helper_node}"
    Start_FE "${helper_node}" || return 1
  else
    local extra_args=""
    [ -n "${helper_node}" ] && extra_args="--helper ${helper_node}"
    Remote_Deploy_Component "${host}" "${doris_ver}" "fe" "${extra_args}" || return 1
  fi
}

Remote_Deploy_BE() {
  local host=$1
  local doris_ver=$2

  if Is_Local_Host "${host}"; then
    Install_BE "${doris_ver}"
    Start_BE || return 1
  else
    Remote_Deploy_Component "${host}" "${doris_ver}" "be" "" || return 1
  fi
}

Remote_Deploy_MS() {
  local host=$1
  local doris_ver=$2

  if Is_Local_Host "${host}"; then
    Install_MS "${doris_ver}"
    Start_MS || return 1
  else
    Remote_Deploy_Component "${host}" "${doris_ver}" "ms" "" || return 1
  fi
}

Verify_Cluster() {
  local fe_ip=$1

  echo "${CMSG}Checking FE status...${CEND}"
  mysql -uroot -P${fe_query_port} -h${fe_ip} -e "show frontends\G"

  echo ""
  echo "${CMSG}Checking BE status...${CEND}"
  mysql -uroot -P${fe_query_port} -h${fe_ip} -e "show backends\G"

  # Simple write/read test (needs at least one live BE)
  echo ""
  local be_alive=$(mysql -uroot -P${fe_query_port} -h${fe_ip} -e "show backends\G" 2>/dev/null | grep -c "Alive: true")
  if [ "${be_alive}" -lt 1 ]; then
    echo "${CFAILURE}No live BE node, skipping validation test.${CEND}"
    echo "${CFAILURE}Check BE logs on the backend nodes: ${be_log_dir}/be.INFO${CEND}"
    return 1
  fi

  echo "${CMSG}Running cluster validation test...${CEND}"
  mysql -uroot -P${fe_query_port} -h${fe_ip} << EOF
CREATE DATABASE IF NOT EXISTS doris_test;
USE doris_test;
CREATE TABLE IF NOT EXISTS test_table (
    id INT,
    name VARCHAR(50),
    ts DATETIME
) DISTRIBUTED BY HASH(id) BUCKETS 3
PROPERTIES ("replication_num" = "1");
INSERT INTO test_table VALUES (1, 'doris_test', NOW());
SELECT * FROM test_table;
DROP TABLE test_table;
DROP DATABASE doris_test;
EOF

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Cluster validation passed!${CEND}"
  else
    echo "${CFAILURE}Cluster validation failed! Please check cluster status.${CEND}"
    return 1
  fi
}

Print_Cluster_Summary() {
  local fe_ip=$1
  local mode=$2

  echo ""
  echo "${CSUCCESS}============================================${CEND}"
  echo "${CSUCCESS}  Doris Cluster Deployment Completed!${CEND}"
  echo "${CSUCCESS}  Mode: ${mode}${CEND}"
  echo "${CSUCCESS}============================================${CEND}"
  echo ""
  echo "  FE Master:  ${fe_ip}:${fe_query_port}"
  echo "  FE Web UI:  http://${fe_ip}:${fe_http_port}"
  echo "  Connect:    mysql -uroot -P${fe_query_port} -h${fe_ip}"
  if [ "${mode}" == "separated" ]; then
    echo ""
    echo "  存算分离 components:"
    echo "    FDB cluster: ${fdb_cluster:-N/A}"
    echo "    MS nodes:    ${ms_nodes}"
    echo "    Storage:     ${storage_vault_type}"
  fi
  echo ""
}

Show_Cluster_Status() {
  local fe_ip=${1:-$(hostname -I | awk '{print $1}')}

  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Doris Cluster Status${CEND}"
  echo "${CMSG}============================================${CEND}"

  # Local process status
  echo ""
  echo "${CMSG}Local Process Status:${CEND}"
  Check_FE_Status 2>/dev/null
  Check_BE_Status 2>/dev/null
  if type Check_MS_Status &>/dev/null; then
    Check_MS_Status 2>/dev/null
  fi

  echo ""
  echo "${CMSG}FE Nodes:${CEND}"
  mysql -uroot -P${fe_query_port} -h${fe_ip} -e "show frontends" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "${CFAILURE}Cannot connect to FE at ${fe_ip}:${fe_query_port}${CEND}"
    return 1
  fi

  echo ""
  echo "${CMSG}BE Nodes:${CEND}"
  mysql -uroot -P${fe_query_port} -h${fe_ip} -e "show backends" 2>/dev/null

  echo ""
  echo "${CMSG}Cluster Version:${CEND}"
  mysql -uroot -P${fe_query_port} -h${fe_ip} -e "select version()" 2>/dev/null

  # Show Storage Vault info if in separated mode
  if [ "${deploy_mode}" == "separated" ]; then
    echo ""
    echo "${CMSG}Storage Vaults:${CEND}"
    mysql -uroot -P${fe_query_port} -h${fe_ip} -e "SHOW STORAGE VAULTS" 2>/dev/null
  fi
}
