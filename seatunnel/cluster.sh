#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Cluster Management Script
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear

# Check root
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# Get script directory
seatunnel_dir=$(dirname $(readlink -f $0))
pushd ${seatunnel_dir} > /dev/null

# Source configuration and modules
. ./options.conf
. ./versions.txt
. ./include/color.sh
. ./include/check_os.sh
. ./include/get_char.sh

# Help message
Show_Help() {
  echo "Usage: $0 [COMMAND] [OPTIONS]"
  echo
  echo "Commands:"
  echo "  deploy-hybrid      Deploy hybrid mode cluster"
  echo "  deploy-separated   Deploy separated mode cluster"
  echo "  add-node           Add a node to the cluster"
  echo "  remove-node        Remove a node from the cluster"
  echo "  scale-workers      Scale worker nodes"
  echo "  status             Show cluster status"
  echo
  echo "Options:"
  echo "  -h, --help         Show this help message"
  echo "  --nodes IPs        Node IPs (comma-separated)"
  echo "  --role ROLE        Node role: master, worker"
  echo
  echo "Examples:"
  echo "  $0 deploy-hybrid --nodes 192.168.1.1,192.168.1.2,192.168.1.3"
  echo "  $0 deploy-separated --nodes 192.168.1.1,192.168.1.2 --role master"
  echo "  $0 add-node --nodes 192.168.1.4 --role worker"
  echo
}

# SSH command wrapper
SSH_Exec() {
  local host=$1
  local cmd=$2
  local user=${3:-root}
  
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${user}@${host} "${cmd}"
}

# SCP file to remote
SCP_File() {
  local src=$1
  local host=$2
  local dest=$3
  local user=${4:-root}
  
  scp -o StrictHostKeyChecking=no ${src} ${user}@${host}:${dest}
}

# Deploy to single node
Deploy_To_Node() {
  local host=$1
  local role=$2
  local mode=$3
  
  echo "${CMSG}Deploying to ${host} (role: ${role})...${CEND}"
  
  # Create remote directory
  SSH_Exec ${host} "mkdir -p /tmp/seatunnel_deploy"
  
  # Copy installation files
  echo "  Copying installation files..."
  SCP_File "${seatunnel_dir}" ${host} "/tmp/seatunnel_deploy/" "-r"
  
  # Run installation
  echo "  Running installation..."
  SSH_Exec ${host} "cd /tmp/seatunnel_deploy/seatunnel && chmod +x install.sh && ./install.sh --deploy_mode ${mode} --node_role ${role} --cluster_name ${cluster_name} --cluster_members ${cluster_members} -q"
  
  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}  Deployment to ${host} completed!${CEND}"
    return 0
  else
    echo "${CFAILURE}  Deployment to ${host} failed!${CEND}"
    return 1
  fi
}

# Deploy hybrid cluster
Deploy_Hybrid_Cluster() {
  local nodes=$1
  
  echo
  echo "${CMSG}Deploying Hybrid Mode Cluster${CEND}"
  echo "Nodes: ${nodes}"
  echo
  
  # Update cluster_members
  cluster_members=${nodes}
  
  local failed=0
  IFS=',' read -ra NODE_ARRAY <<< "${nodes}"
  for node in "${NODE_ARRAY[@]}"; do
    Deploy_To_Node ${node} "hybrid" "hybrid"
    [ $? -ne 0 ] && ((failed++))
  done
  
  echo
  if [ ${failed} -eq 0 ]; then
    echo "${CSUCCESS}Hybrid cluster deployment completed!${CEND}"
    echo
    echo "Start the cluster on each node:"
    echo "  systemctl start seatunnel"
  else
    echo "${CWARNING}Deployment completed with ${failed} failures${CEND}"
  fi
}

# Deploy separated cluster
Deploy_Separated_Cluster() {
  local master_nodes=$1
  local worker_nodes=$2
  
  echo
  echo "${CMSG}Deploying Separated Mode Cluster${CEND}"
  echo "Master nodes: ${master_nodes}"
  echo "Worker nodes: ${worker_nodes}"
  echo
  
  # Update cluster_members (all nodes)
  cluster_members="${master_nodes},${worker_nodes}"
  
  local failed=0
  
  # Deploy masters
  echo "${CMSG}Deploying Master nodes...${CEND}"
  IFS=',' read -ra MASTER_ARRAY <<< "${master_nodes}"
  for node in "${MASTER_ARRAY[@]}"; do
    Deploy_To_Node ${node} "master" "separated"
    [ $? -ne 0 ] && ((failed++))
  done
  
  # Deploy workers
  echo
  echo "${CMSG}Deploying Worker nodes...${CEND}"
  IFS=',' read -ra WORKER_ARRAY <<< "${worker_nodes}"
  for node in "${WORKER_ARRAY[@]}"; do
    Deploy_To_Node ${node} "worker" "separated"
    [ $? -ne 0 ] && ((failed++))
  done
  
  echo
  if [ ${failed} -eq 0 ]; then
    echo "${CSUCCESS}Separated cluster deployment completed!${CEND}"
    echo
    echo "Start the cluster:"
    echo "  On master nodes: systemctl start seatunnel-master"
    echo "  On worker nodes: systemctl start seatunnel-worker"
  else
    echo "${CWARNING}Deployment completed with ${failed} failures${CEND}"
  fi
}

# Add node to cluster
Add_Node() {
  local nodes=$1
  local role=$2
  
  echo
  echo "${CMSG}Adding node(s) to cluster${CEND}"
  echo "Nodes: ${nodes}"
  echo "Role: ${role}"
  echo
  
  # Update cluster_members
  if [ -n "${cluster_members}" ]; then
    cluster_members="${cluster_members},${nodes}"
  else
    cluster_members="${nodes}"
  fi
  
  # Deploy to new nodes
  local failed=0
  IFS=',' read -ra NODE_ARRAY <<< "${nodes}"
  for node in "${NODE_ARRAY[@]}"; do
    Deploy_To_Node ${node} ${role} ${deploy_mode}
    [ $? -ne 0 ] && ((failed++))
  done
  
  # Update existing nodes' configuration
  echo
  echo "${CMSG}Updating existing nodes' configuration...${CEND}"
  IFS=',' read -ra EXISTING_ARRAY <<< "${cluster_members}"
  for node in "${EXISTING_ARRAY[@]}"; do
    if [[ ! "${nodes}" == *"${node}"* ]]; then
      echo "  Updating ${node}..."
      SSH_Exec ${node} "sed -i 's@^cluster_members=.*@cluster_members=${cluster_members}@' ${seatunnel_install_dir}/../seatunnel/options.conf 2>/dev/null"
    fi
  done
  
  echo
  if [ ${failed} -eq 0 ]; then
    echo "${CSUCCESS}Node(s) added successfully!${CEND}"
    echo
    echo "Note: You may need to restart the cluster for changes to take effect."
  else
    echo "${CWARNING}Some nodes failed to add${CEND}"
  fi
}

# Remove node from cluster
Remove_Node() {
  local nodes=$1
  
  echo
  echo "${CMSG}Removing node(s) from cluster${CEND}"
  echo "Nodes: ${nodes}"
  echo
  
  # Stop services on nodes to remove
  IFS=',' read -ra NODE_ARRAY <<< "${nodes}"
  for node in "${NODE_ARRAY[@]}"; do
    echo "  Stopping services on ${node}..."
    SSH_Exec ${node} "systemctl stop seatunnel seatunnel-master seatunnel-worker 2>/dev/null"
  done
  
  # Update cluster_members
  local new_members=""
  IFS=',' read -ra EXISTING_ARRAY <<< "${cluster_members}"
  for member in "${EXISTING_ARRAY[@]}"; do
    local keep=true
    for remove in "${NODE_ARRAY[@]}"; do
      if [ "${member}" == "${remove}" ]; then
        keep=false
        break
      fi
    done
    if [ "${keep}" == "true" ]; then
      if [ -n "${new_members}" ]; then
        new_members="${new_members},${member}"
      else
        new_members="${member}"
      fi
    fi
  done
  
  cluster_members=${new_members}
  
  # Update remaining nodes' configuration
  echo
  echo "${CMSG}Updating remaining nodes' configuration...${CEND}"
  IFS=',' read -ra REMAINING_ARRAY <<< "${cluster_members}"
  for node in "${REMAINING_ARRAY[@]}"; do
    echo "  Updating ${node}..."
    SSH_Exec ${node} "sed -i 's@^cluster_members=.*@cluster_members=${cluster_members}@' ${seatunnel_install_dir}/../seatunnel/options.conf 2>/dev/null"
  done
  
  echo
  echo "${CSUCCESS}Node(s) removed successfully!${CEND}"
  echo
  echo "Note: You may need to restart the cluster for changes to take effect."
}

# Scale workers
Scale_Workers() {
  local count=$1
  local action=$2  # up or down
  
  echo
  echo "${CMSG}Scaling workers ${action} by ${count}${CEND}"
  echo
  
  if [ "${action}" == "up" ]; then
    echo "To scale up, please use: $0 add-node --nodes <new_worker_ips> --role worker"
  elif [ "${action}" == "down" ]; then
    echo "To scale down, please use: $0 remove-node --nodes <worker_ips_to_remove>"
  fi
}

# Show cluster status
Show_Cluster_Status() {
  echo
  echo "${CMSG}Cluster Status${CEND}"
  echo "=========================================="
  echo "Cluster Name: ${cluster_name}"
  echo "Deploy Mode:  ${deploy_mode}"
  echo "Members:      ${cluster_members}"
  echo "=========================================="
  echo
  
  echo "${CMSG}Node Status:${CEND}"
  IFS=',' read -ra NODE_ARRAY <<< "${cluster_members}"
  for node in "${NODE_ARRAY[@]}"; do
    echo -n "  ${node}: "
    if ping -c 1 -W 2 ${node} > /dev/null 2>&1; then
      # Check if SeaTunnel is running
      local status=$(SSH_Exec ${node} "systemctl is-active seatunnel seatunnel-master seatunnel-worker 2>/dev/null | grep -v inactive | head -1")
      if [ -n "${status}" ]; then
        echo "${CSUCCESS}${status}${CEND}"
      else
        echo "${CWARNING}installed but not running${CEND}"
      fi
    else
      echo "${CFAILURE}unreachable${CEND}"
    fi
  done
  echo
}

# Parse arguments
if [ $# -eq 0 ]; then
  Show_Help
  exit 0
fi

command=$1
shift

TEMP=$(getopt -o h --long help,nodes:,role:,masters:,workers: -- "$@" 2>/dev/null)
eval set -- "${TEMP}"

nodes=""
role=""
masters=""
workers=""

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    --nodes)
      nodes=$2
      shift 2
      ;;
    --role)
      role=$2
      shift 2
      ;;
    --masters)
      masters=$2
      shift 2
      ;;
    --workers)
      workers=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

# Execute command
case "${command}" in
  deploy-hybrid)
    if [ -z "${nodes}" ]; then
      echo "${CFAILURE}Please specify nodes with --nodes${CEND}"
      exit 1
    fi
    Deploy_Hybrid_Cluster "${nodes}"
    ;;
  deploy-separated)
    if [ -z "${masters}" ] || [ -z "${workers}" ]; then
      echo "${CFAILURE}Please specify --masters and --workers${CEND}"
      exit 1
    fi
    Deploy_Separated_Cluster "${masters}" "${workers}"
    ;;
  add-node)
    if [ -z "${nodes}" ] || [ -z "${role}" ]; then
      echo "${CFAILURE}Please specify --nodes and --role${CEND}"
      exit 1
    fi
    Add_Node "${nodes}" "${role}"
    ;;
  remove-node)
    if [ -z "${nodes}" ]; then
      echo "${CFAILURE}Please specify nodes with --nodes${CEND}"
      exit 1
    fi
    Remove_Node "${nodes}"
    ;;
  scale-workers)
    echo "Use add-node or remove-node to scale workers"
    ;;
  status)
    Show_Cluster_Status
    ;;
  *)
    echo "${CFAILURE}Unknown command: ${command}${CEND}"
    Show_Help
    exit 1
    ;;
esac

popd > /dev/null
