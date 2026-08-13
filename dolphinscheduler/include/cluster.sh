#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Cluster deployment functions
#
# Cluster deployment is role aware: every node only gets the services that are
# assigned to it through masters / workers / alert_server / api_servers in
# options.conf. The metadata schema is shared, so it is initialized exactly once
# (on the first node of the ips list).
#
# Remote nodes are reached as ${remote_ssh_user} (default: root), because the
# deploy user does not necessarily exist on a fresh node yet.

# Staging directory used on remote nodes
remote_stage_dir="/tmp/dolphinscheduler-deploy"

# Return 0 if the given address refers to this machine
Is_Local_Node() {
  local ip=$1

  [ "${ip}" == "localhost" ] && return 0
  [ "${ip}" == "127.0.0.1" ] && return 0
  [ "${ip}" == "${local_ip}" ] && return 0
  [ "${ip}" == "$(hostname)" ] && return 0

  local addr
  for addr in $(hostname -I 2>/dev/null); do
    [ "${ip}" == "${addr}" ] && return 0
  done

  return 1
}

# Return 0 if ${1} appears in the comma separated list ${2}
# Entries may carry a suffix after ':' (workers use the "ip:group" format)
In_Node_List() {
  local ip=$1
  local entry
  for entry in ${2//,/ }; do
    [ "${entry%%:*}" == "${ip}" ] && return 0
  done
  return 1
}

# Resolve the roles of a node into a comma separated list
Get_Node_Roles() {
  local ip=$1
  local roles=""

  In_Node_List "${ip}" "${masters}"     && roles="${roles},master"
  In_Node_List "${ip}" "${workers}"     && roles="${roles},worker"
  In_Node_List "${ip}" "${api_servers}" && roles="${roles},api"
  In_Node_List "${ip}" "${alert_server}" && roles="${roles},alert"

  echo "${roles#,}"
}

# Build the ssh/scp target for a node
Remote_Target() {
  echo "${remote_ssh_user:-root}@$1"
}

# Wrap a remote command with sudo when not connecting as root
Remote_Cmd() {
  if [ "${remote_ssh_user:-root}" == "root" ]; then
    echo "$1"
  else
    echo "sudo -n bash -c '$1'"
  fi
}

# Deploy Cluster mode
Deploy_Cluster() {
  local ds_ver=$1

  echo "${CMSG}Deploying DolphinScheduler ${ds_ver} (Cluster mode)...${CEND}"

  # Validate cluster configuration
  if [ -z "${ips}" ] || [ "${ips}" == "localhost" ]; then
    echo "${CFAILURE}Cluster mode requires multiple nodes. Please configure 'ips' in options.conf.${CEND}"
    return 1
  fi

  local ips_array=(${ips//,/ })

  # Every node must have at least one role, otherwise the config is inconsistent
  local ip roles
  for ip in "${ips_array[@]}"; do
    roles=$(Get_Node_Roles "${ip}")
    if [ -z "${roles}" ]; then
      echo "${CFAILURE}Node ${ip} is listed in 'ips' but has no role assigned!${CEND}"
      echo "${CFAILURE}Add it to masters / workers / api_servers / alert_server in options.conf.${CEND}"
      return 1
    fi
    echo "  ${ip} -> ${roles}"
  done

  # Check SSH connectivity to all remote nodes - abort if unreachable
  Check_SSH_Connectivity || return 1

  # Install on each node; the first node initializes the shared schema
  local first_node=y
  for ip in "${ips_array[@]}"; do
    roles=$(Get_Node_Roles "${ip}")
    echo ""
    echo "${CMSG}Deploying to node ${ip} (roles: ${roles})...${CEND}"

    if [ "${first_node}" == "y" ]; then
      skip_db_init=n
    else
      skip_db_init=y
    fi

    if ! Deploy_To_Node "${ip}" "${ds_ver}" "${roles}"; then
      echo "${CFAILURE}Deployment to node ${ip} failed! Aborting cluster deployment.${CEND}"
      return 1
    fi
    first_node=n
  done

  echo "${CSUCCESS}Cluster deployment completed!${CEND}"
}

# Check SSH connectivity to all remote nodes, distributing the key if needed
Check_SSH_Connectivity() {
  echo "${CMSG}Checking SSH connectivity to all nodes...${CEND}"

  local ips_array=(${ips//,/ })
  local ip has_error=0

  for ip in "${ips_array[@]}"; do
    # The local node is configured directly, no SSH involved
    if Is_Local_Node "${ip}"; then
      echo "${CMSG}${ip} is the local node, skipping SSH check.${CEND}"
      continue
    fi

    if Test_SSH "${ip}"; then
      echo "${CSUCCESS}SSH to ${ip} OK${CEND}"
      continue
    fi

    echo "${CWARNING}Passwordless SSH to $(Remote_Target ${ip}) not available, trying to set it up...${CEND}"
    if Distribute_SSH_Key "${ip}" && Test_SSH "${ip}"; then
      echo "${CSUCCESS}SSH to ${ip} OK${CEND}"
    else
      echo "${CFAILURE}SSH connection to $(Remote_Target ${ip}) failed!${CEND}"
      has_error=1
    fi
  done

  if [ ${has_error} -eq 1 ]; then
    echo ""
    echo "${CFAILURE}Passwordless SSH is required for cluster deployment.${CEND}"
    echo "${CFAILURE}Either set 'ssh_password' in options.conf (used once, needs sshpass),${CEND}"
    echo "${CFAILURE}or run manually for each node:${CEND}"
    echo "  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa   # once on this node"
    echo "  ssh-copy-id -p ${ssh_port} ${remote_ssh_user:-root}@<node-ip>"
    return 1
  fi

  echo "${CSUCCESS}All nodes are reachable via SSH.${CEND}"
  return 0
}

# Test passwordless SSH to a node
Test_SSH() {
  local ip=$1
  ssh -o BatchMode=yes ${SSH_OPTS} -p ${ssh_port} "$(Remote_Target ${ip})" "echo ok" > /dev/null 2>&1
}

# Copy the local root SSH key to a node (one-time bootstrap)
Distribute_SSH_Key() {
  local ip=$1
  local target=$(Remote_Target ${ip})

  # Make sure we have a key to distribute
  if [ ! -f /root/.ssh/id_rsa.pub ]; then
    echo "${CMSG}Generating SSH key for root...${CEND}"
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    ssh-keygen -t rsa -P '' -f /root/.ssh/id_rsa -q || return 1
  fi

  if [ -n "${ssh_password}" ]; then
    if ! command -v sshpass > /dev/null 2>&1; then
      echo "${CFAILURE}ssh_password is set but sshpass is not installed.${CEND}"
      return 1
    fi
    echo "${CMSG}Copying SSH key to ${target} using ssh_password...${CEND}"
    sshpass -p "${ssh_password}" ssh-copy-id -o StrictHostKeyChecking=accept-new \
      -p ${ssh_port} -i /root/.ssh/id_rsa.pub "${target}" > /dev/null 2>&1
    return $?
  fi

  # No stored password: only possible interactively
  if [ -t 0 ]; then
    echo "${CMSG}Copying SSH key to ${target} (password required once)...${CEND}"
    ssh-copy-id -o StrictHostKeyChecking=accept-new -p ${ssh_port} -i /root/.ssh/id_rsa.pub "${target}"
    return $?
  fi

  echo "${CFAILURE}Cannot set up passwordless SSH to ${target} non-interactively.${CEND}"
  return 1
}

# Deploy to a single node
# $1 = ip, $2 = version, $3 = roles for that node
Deploy_To_Node() {
  local target_ip=$1
  local ds_ver=$2
  local roles=$3

  if Is_Local_Node "${target_ip}"; then
    echo "${CMSG}Deploying locally (roles: ${roles})...${CEND}"
    node_roles="${roles}"
    Check_Ports "node" || return 1
    Install_DolphinScheduler_PseudoCluster "${ds_ver}" || return 1
    return 0
  fi

  echo "${CMSG}Deploying to remote node ${target_ip} (roles: ${roles})...${CEND}"

  local target=$(Remote_Target ${target_ip})
  local skip_flag=""
  [ "${skip_db_init}" == "y" ] && skip_flag="--skip_db_init"

  # Stage a clean copy of this toolkit (including the downloaded packages)
  if ! ssh ${SSH_OPTS} -p ${ssh_port} "${target}" \
      "$(Remote_Cmd "rm -rf ${remote_stage_dir} && mkdir -p ${remote_stage_dir}")"; then
    echo "${CFAILURE}Failed to prepare ${remote_stage_dir} on ${target_ip}!${CEND}"
    return 1
  fi

  if ! scp ${SSH_OPTS} -P ${ssh_port} -r ${ds_dir}/. "${target}:${remote_stage_dir}/"; then
    echo "${CFAILURE}Failed to copy deployment files to ${target_ip}!${CEND}"
    return 1
  fi

  # Execute installation on remote node ("node" mode installs without starting)
  local remote_install="cd ${remote_stage_dir} && bash install.sh --deploy_mode node --ds_ver ${ds_ver} --roles ${roles} ${skip_flag} --quiet"
  if ! ssh ${SSH_OPTS} -p ${ssh_port} "${target}" "$(Remote_Cmd "${remote_install}")"; then
    echo "${CFAILURE}Remote installation on ${target_ip} failed!${CEND}"
    return 1
  fi

  return 0
}

# Run systemctl for the given roles on a node
# $1 = ip, $2 = roles, $3 = action (start|stop|restart)
Systemctl_On_Node() {
  local ip=$1
  local roles=$2
  local action=$3

  local units="" role
  for role in ${roles//,/ }; do
    units="${units} dolphinscheduler-${role}"
  done
  [ -z "${units}" ] && return 0

  if Is_Local_Node "${ip}"; then
    systemctl ${action} ${units}
  else
    ssh ${SSH_OPTS} -p ${ssh_port} "$(Remote_Target ${ip})" "$(Remote_Cmd "systemctl ${action} ${units}")"
  fi
}

# Start all cluster services
Start_Cluster() {
  echo "${CMSG}Starting DolphinScheduler cluster services...${CEND}"

  local ips_array=(${ips//,/ })
  local ip roles has_error=0

  # Masters and workers first, then api/alert
  for ip in "${ips_array[@]}"; do
    roles=$(Get_Node_Roles "${ip}")
    echo "${CMSG}Starting ${roles} on ${ip}...${CEND}"

    if Is_Local_Node "${ip}"; then
      node_roles="${roles}"
      Start_PseudoCluster || has_error=1
    else
      Systemctl_On_Node "${ip}" "${roles}" start || has_error=1
    fi
  done

  if [ ${has_error} -eq 1 ]; then
    echo "${CFAILURE}Some services failed to start! Check the logs above.${CEND}"
    return 1
  fi

  echo "${CSUCCESS}Cluster services started!${CEND}"
}

# Stop all cluster services
Stop_Cluster() {
  echo "${CMSG}Stopping DolphinScheduler cluster services...${CEND}"

  local ips_array=(${ips//,/ })
  local ip roles

  for ip in "${ips_array[@]}"; do
    roles=$(Get_Node_Roles "${ip}")
    echo "${CMSG}Stopping ${roles} on ${ip}...${CEND}"
    Systemctl_On_Node "${ip}" "${roles}" stop 2>/dev/null
  done

  echo "${CSUCCESS}Cluster services stopped!${CEND}"
}

# Show cluster status
Show_Cluster_Status_Full() {
  echo ""
  echo "${CMSG}========== DolphinScheduler Cluster Status ==========${CEND}"
  echo ""

  local ips_array=(${ips//,/ })
  local ip roles role status

  for ip in "${ips_array[@]}"; do
    roles=$(Get_Node_Roles "${ip}")
    echo "${CMSG}Node: ${ip} (${roles:-no role})${CEND}"

    for role in ${roles//,/ }; do
      if Is_Local_Node "${ip}"; then
        status=$(systemctl is-active dolphinscheduler-${role} 2>/dev/null)
      else
        status=$(ssh -o BatchMode=yes ${SSH_OPTS} -p ${ssh_port} "$(Remote_Target ${ip})" \
          "systemctl is-active dolphinscheduler-${role}" 2>/dev/null)
      fi

      if [ "${status}" == "active" ]; then
        echo "  ${CSUCCESS}[RUNNING]${CEND} ${role}-server"
      elif [ -z "${status}" ]; then
        echo "  ${CWARNING}[UNKNOWN]${CEND} ${role}-server (node unreachable)"
      else
        echo "  ${CFAILURE}[${status}]${CEND} ${role}-server"
      fi
    done
    echo ""
  done
}
