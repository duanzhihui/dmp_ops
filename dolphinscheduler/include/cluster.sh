#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Cluster deployment functions

# Deploy Cluster mode
Deploy_Cluster() {
  local ds_ver=$1
  local ds_pkg=$(Get_DolphinScheduler_Pkg "${ds_ver}")

  echo "${CMSG}Deploying DolphinScheduler ${ds_ver} (Cluster mode)...${CEND}"

  # Validate cluster configuration
  if [ -z "${ips}" ] || [ "${ips}" == "localhost" ]; then
    echo "${CFAILURE}Cluster mode requires multiple nodes. Please configure 'ips' in options.conf.${CEND}"
    return 1
  fi

  # Check SSH connectivity to all nodes
  Check_SSH_Connectivity

  # Install on each node
  local ips_array=(${ips//,/ })
  for ip in "${ips_array[@]}"; do
    echo "${CMSG}Deploying to node: ${ip}${CEND}"
    Deploy_To_Node "${ip}" "${ds_ver}"
  done

  echo "${CSUCCESS}Cluster deployment completed!${CEND}"
}

# Check SSH connectivity to all nodes
Check_SSH_Connectivity() {
  echo "${CMSG}Checking SSH connectivity to all nodes...${CEND}"

  local ips_array=(${ips//,/ })
  for ip in "${ips_array[@]}"; do
    if [ "${ip}" == "localhost" ] || [ "${ip}" == "127.0.0.1" ]; then
      continue
    fi

    echo "Testing SSH to ${ip}..."
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p ${ssh_port} ${run_user}@${ip} "echo ok" > /dev/null 2>&1; then
      echo "${CFAILURE}SSH connection to ${ip} failed!${CEND}"
      echo "${CFAILURE}Please configure SSH key-based authentication first.${CEND}"
      return 1
    fi
    echo "${CSUCCESS}SSH to ${ip} OK${CEND}"
  done

  echo "${CSUCCESS}All nodes are reachable via SSH.${CEND}"
}

# Deploy to a single node
Deploy_To_Node() {
  local target_ip=$1
  local ds_ver=$2

  if [ "${target_ip}" == "localhost" ] || [ "${target_ip}" == "127.0.0.1" ] || [ "${target_ip}" == "${local_ip}" ]; then
    # Local deployment
    echo "${CMSG}Deploying locally...${CEND}"
    Install_DolphinScheduler_PseudoCluster "${ds_ver}"
  else
    # Remote deployment
    echo "${CMSG}Deploying to remote node ${target_ip}...${CEND}"

    # Copy package to remote node
    local ds_pkg=$(Get_DolphinScheduler_Pkg "${ds_ver}")
    scp -P ${ssh_port} ${ds_dir}/src/${ds_pkg} ${run_user}@${target_ip}:/tmp/

    # Copy scripts to remote node
    scp -P ${ssh_port} -r ${ds_dir} ${run_user}@${target_ip}:/tmp/dolphinscheduler-deploy/

    # Execute installation on remote node
    ssh -p ${ssh_port} ${run_user}@${target_ip} "cd /tmp/dolphinscheduler-deploy && sudo bash install.sh --deploy_mode pseudo-cluster --version ${ds_ver} --quiet"
  fi
}

# Start all cluster services
Start_Cluster() {
  echo "${CMSG}Starting DolphinScheduler cluster services...${CEND}"

  local ips_array=(${ips//,/ })
  for ip in "${ips_array[@]}"; do
    echo "${CMSG}Starting services on ${ip}...${CEND}"

    if [ "${ip}" == "localhost" ] || [ "${ip}" == "127.0.0.1" ] || [ "${ip}" == "${local_ip}" ]; then
      Start_PseudoCluster
    else
      ssh -p ${ssh_port} ${run_user}@${ip} "sudo systemctl start dolphinscheduler-master dolphinscheduler-worker dolphinscheduler-api dolphinscheduler-alert"
    fi
  done

  echo "${CSUCCESS}Cluster services started!${CEND}"
}

# Stop all cluster services
Stop_Cluster() {
  echo "${CMSG}Stopping DolphinScheduler cluster services...${CEND}"

  local ips_array=(${ips//,/ })
  for ip in "${ips_array[@]}"; do
    echo "${CMSG}Stopping services on ${ip}...${CEND}"

    if [ "${ip}" == "localhost" ] || [ "${ip}" == "127.0.0.1" ] || [ "${ip}" == "${local_ip}" ]; then
      systemctl stop dolphinscheduler-master dolphinscheduler-worker dolphinscheduler-api dolphinscheduler-alert 2>/dev/null
    else
      ssh -p ${ssh_port} ${run_user}@${ip} "sudo systemctl stop dolphinscheduler-master dolphinscheduler-worker dolphinscheduler-api dolphinscheduler-alert" 2>/dev/null
    fi
  done

  echo "${CSUCCESS}Cluster services stopped!${CEND}"
}

# Show cluster status
Show_Cluster_Status_Full() {
  echo ""
  echo "${CMSG}========== DolphinScheduler Cluster Status ==========${CEND}"
  echo ""

  local ips_array=(${ips//,/ })
  for ip in "${ips_array[@]}"; do
    echo "${CMSG}Node: ${ip}${CEND}"

    if [ "${ip}" == "localhost" ] || [ "${ip}" == "127.0.0.1" ] || [ "${ip}" == "${local_ip}" ]; then
      # Local node
      for service in standalone master worker api alert; do
        if systemctl is-active --quiet dolphinscheduler-${service} 2>/dev/null; then
          echo "  ${CSUCCESS}[RUNNING]${CEND} ${service}-server"
        elif [ -f "/lib/systemd/system/dolphinscheduler-${service}.service" ]; then
          echo "  ${CFAILURE}[STOPPED]${CEND} ${service}-server"
        fi
      done
    else
      # Remote node
      for service in standalone master worker api alert; do
        local status=$(ssh -p ${ssh_port} ${run_user}@${ip} "systemctl is-active dolphinscheduler-${service}" 2>/dev/null)
        if [ "${status}" == "active" ]; then
          echo "  ${CSUCCESS}[RUNNING]${CEND} ${service}-server"
        elif ssh -p ${ssh_port} ${run_user}@${ip} "test -f /lib/systemd/system/dolphinscheduler-${service}.service" 2>/dev/null; then
          echo "  ${CFAILURE}[STOPPED]${CEND} ${service}-server"
        fi
      done
    fi
    echo ""
  done
}
