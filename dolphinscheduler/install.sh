#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Main installation script
#
# Supports: DolphinScheduler 3.2.2, 3.3.2, 3.4.1
# Package:  apache-dolphinscheduler-<ver>-bin.tar.gz
#
# Deployment modes:
#   standalone     - All services in one process (for testing)
#   pseudo-cluster - All services on single node, separate processes
#   cluster        - Multi-node deployment for production
#
# Reference:
#   https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1/guide/installation/standalone
#   https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1/guide/installation/pseudo-cluster
#   https://dolphinscheduler.apache.org/zh-cn/docs/3.4.1/guide/installation/cluster

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear
printf "
#######################################################################
#    DolphinSchedulerStack - Apache DolphinScheduler Deployment Tool  #
#    Supports: DolphinScheduler 3.2.2 / 3.3.2 / 3.4.1                 #
#    Modes:    standalone / pseudo-cluster / cluster                  #
#    For more information: https://dolphinscheduler.apache.org        #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

ds_dir=$(dirname "$(readlink -f $0)")
pushd ${ds_dir} > /dev/null
. ./versions.txt
. ./options.conf
. ./include/color.sh
. ./include/check_os.sh
. ./include/download.sh
. ./include/check_env.sh
. ./include/dolphinscheduler.sh
. ./include/cluster.sh

version() {
  echo "version: 1.0.0"
  echo "updated date: 2026-05-27"
}

Show_Help() {
  version
  echo "Usage: $0 command ...[parameters]....
  --help, -h                  Show this help message
  --version, -v               Show version info
  --ds_ver [1-3]              DolphinScheduler version: 1) ${dolphinscheduler32_ver}  2) ${dolphinscheduler33_ver}  3) ${dolphinscheduler34_ver}
  --deploy_mode [mode]        Deploy mode: standalone, pseudo-cluster, cluster
  --download_only             Download packages only, do not install
  --quiet, -q                 Non-interactive mode
  --status                    Show cluster status

  Internal options (used when the cluster deployment drives a single node):
  --roles [list]              Comma separated roles: master,worker,api,alert
  --skip_db_init              Do not initialize the shared metadata schema
  "
}

ARG_NUM=$#
TEMP=$(getopt -o hvVq --long help,version,ds_ver:,deploy_mode:,roles:,skip_db_init,download_only,quiet,status -- "$@" 2>/dev/null)
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"

quiet_flag=n
download_only_flag=n
ds_ver_option=""
deploy_mode_from_cli=n
node_roles=""
skip_db_init=n

while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -v|-V|--version)
      version; exit 0
      ;;
    --ds_ver)
      ds_ver_option=$2; shift 2
      ;;
    --deploy_mode)
      deploy_mode=$2; deploy_mode_from_cli=y; shift 2
      ;;
    --roles)
      node_roles=$2; shift 2
      ;;
    --skip_db_init)
      skip_db_init=y; shift 1
      ;;
    --download_only)
      download_only_flag=y; shift 1
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    --status)
      Detect_Network
      if [ "${deploy_mode}" == "cluster" ]; then
        Show_Cluster_Status_Full
      else
        Show_Cluster_Status
      fi
      exit 0
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

# Interactive version selection
Select_Version() {
  # Support both number (1-3) and version string (e.g. 3.4.1)
  if [ -n "${ds_ver_option}" ]; then
    case "${ds_ver_option}" in
      1|${dolphinscheduler32_ver}) ds_ver=${dolphinscheduler32_ver} ;;
      2|${dolphinscheduler33_ver}) ds_ver=${dolphinscheduler33_ver} ;;
      3|${dolphinscheduler34_ver}) ds_ver=${dolphinscheduler34_ver} ;;
      *)
        echo "${CWARNING}Invalid ds_ver: ${ds_ver_option}${CEND}"
        echo "Valid: 1(${dolphinscheduler32_ver}), 2(${dolphinscheduler33_ver}), 3(${dolphinscheduler34_ver})"
        exit 1
        ;;
    esac
  else
    while :; do
      echo
      echo 'Please select Apache DolphinScheduler version:'
      echo -e "\t${CMSG}1${CEND}. DolphinScheduler ${dolphinscheduler32_ver}"
      echo -e "\t${CMSG}2${CEND}. DolphinScheduler ${dolphinscheduler33_ver}"
      echo -e "\t${CMSG}3${CEND}. DolphinScheduler ${dolphinscheduler34_ver} (Latest)"
      read -e -p "Please input a number:(Default 3 press Enter) " ds_ver_option
      ds_ver_option=${ds_ver_option:-3}
      if [[ ! ${ds_ver_option} =~ ^[1-3]$ ]]; then
        echo "${CWARNING}input error! Please only input number 1~3${CEND}"
      else
        break
      fi
    done

    case "${ds_ver_option}" in
      1) ds_ver=${dolphinscheduler32_ver} ;;
      2) ds_ver=${dolphinscheduler33_ver} ;;
      3) ds_ver=${dolphinscheduler34_ver} ;;
    esac
  fi

  echo "${CMSG}Selected DolphinScheduler version: ${ds_ver}${CEND}"
}

# Interactive deployment mode selection
Select_Deploy_Mode() {
  # If deploy_mode explicitly set via command line
  if [ "${deploy_mode_from_cli}" == "y" ]; then
    case "${deploy_mode}" in
      standalone|pseudo-cluster|cluster|node) ;;
      *)
        echo "${CFAILURE}Invalid deploy_mode: ${deploy_mode}${CEND}"
        echo "Valid: standalone, pseudo-cluster, cluster"
        exit 1
        ;;
    esac
    return
  fi

  if [ "${quiet_flag}" != "y" ]; then
    while :; do
      echo
      echo 'Please select deployment mode:'
      echo -e "\t${CMSG}1${CEND}. Standalone (All services in one process, for testing)"
      echo -e "\t${CMSG}2${CEND}. Pseudo-Cluster (Single node, separate processes)"
      echo -e "\t${CMSG}3${CEND}. Cluster (Multi-node deployment for production)"
      read -e -p "Please input a number:(Default 1 press Enter) " deploy_option
      deploy_option=${deploy_option:-1}
      if [[ ! ${deploy_option} =~ ^[1-3]$ ]]; then
        echo "${CWARNING}input error! Please only input number 1~3${CEND}"
      else
        break
      fi
    done

    case "${deploy_option}" in
      1) deploy_mode="standalone" ;;
      2) deploy_mode="pseudo-cluster" ;;
      3) deploy_mode="cluster" ;;
    esac
  else
    deploy_mode=${deploy_mode:-standalone}
  fi

  echo "${CMSG}Deployment mode: ${deploy_mode}${CEND}"
}

# Interactive database configuration
Configure_Database_Interactive() {
  echo ""
  echo "${CMSG}========== Database Configuration ==========${CEND}"
  echo ""

  # Select database type
  while :; do
    echo "Please select database type:"
    echo -e "\t${CMSG}1${CEND}. MySQL (recommended)"
    echo -e "\t${CMSG}2${CEND}. PostgreSQL"
    read -e -p "Please input a number:(Default 1 press Enter) " db_type_option
    db_type_option=${db_type_option:-1}
    if [[ ! ${db_type_option} =~ ^[1-2]$ ]]; then
      echo "${CWARNING}input error! Please only input 1 or 2${CEND}"
    else
      break
    fi
  done

  case "${db_type_option}" in
    1) db_type="mysql"; db_port=${db_port:-3306} ;;
    2) db_type="postgresql"; db_port=${db_port:-5432} ;;
  esac

  # Database host
  read -e -p "Database host (default: ${db_host:-localhost}): " input_db_host
  db_host=${input_db_host:-${db_host:-localhost}}

  # Database port
  local default_port=3306
  [ "${db_type}" == "postgresql" ] && default_port=5432
  read -e -p "Database port (default: ${db_port:-${default_port}}): " input_db_port
  db_port=${input_db_port:-${db_port:-${default_port}}}

  # Database name
  read -e -p "Database name (default: ${db_name:-dolphinscheduler}): " input_db_name
  db_name=${input_db_name:-${db_name:-dolphinscheduler}}

  # Database user
  read -e -p "Database user (default: ${db_user:-root}): " input_db_user
  db_user=${input_db_user:-${db_user:-root}}

  # Database password
  while :; do
    read -e -s -p "Database password: " input_db_password
    echo ""
    if [ -z "${input_db_password}" ]; then
      echo "${CWARNING}Password cannot be empty!${CEND}"
    else
      read -e -s -p "Confirm password: " confirm_db_password
      echo ""
      if [ "${input_db_password}" != "${confirm_db_password}" ]; then
        echo "${CWARNING}Passwords do not match!${CEND}"
      else
        db_password="${input_db_password}"
        break
      fi
    fi
  done

  echo ""
  echo "${CMSG}Database configuration:${CEND}"
  echo "  Type:     ${db_type}"
  echo "  Host:     ${db_host}"
  echo "  Port:     ${db_port}"
  echo "  Database: ${db_name}"
  echo "  User:     ${db_user}"
  echo ""
}

# Interactive ZooKeeper configuration
Configure_ZooKeeper_Interactive() {
  echo ""
  echo "${CMSG}========== ZooKeeper Configuration ==========${CEND}"
  echo ""

  read -e -p "ZooKeeper hosts (default: ${zk_hosts:-localhost:2181}): " input_zk_hosts
  zk_hosts=${input_zk_hosts:-${zk_hosts:-localhost:2181}}

  echo "${CMSG}ZooKeeper hosts: ${zk_hosts}${CEND}"
}

# Interactive cluster configuration
Configure_Cluster_Interactive() {
  echo ""
  echo "${CMSG}========== Cluster Configuration ==========${CEND}"
  echo ""

  # All node IPs
  echo "Enter all cluster node IPs (comma separated)"
  echo "Example: 192.168.1.1,192.168.1.2,192.168.1.3"
  read -e -p "Node IPs (default: ${ips:-localhost}): " input_ips
  ips=${input_ips:-${ips:-localhost}}

  # SSH port
  read -e -p "SSH port (default: ${ssh_port:-22}): " input_ssh_port
  ssh_port=${input_ssh_port:-${ssh_port:-22}}

  # Master nodes
  echo ""
  echo "Enter Master node IPs (comma separated)"
  echo "Example: 192.168.1.1,192.168.1.2"
  read -e -p "Master nodes (default: ${masters:-localhost}): " input_masters
  masters=${input_masters:-${masters:-localhost}}

  # Worker nodes
  echo ""
  echo "Enter Worker node IPs with group (comma separated, format: ip:group)"
  echo "Example: 192.168.1.3:default,192.168.1.4:default"
  read -e -p "Worker nodes (default: ${workers:-localhost:default}): " input_workers
  workers=${input_workers:-${workers:-localhost:default}}

  # Alert server
  read -e -p "Alert server (default: ${alert_server:-localhost}): " input_alert_server
  alert_server=${input_alert_server:-${alert_server:-localhost}}

  # API servers
  echo ""
  echo "Enter API server IPs (comma separated)"
  read -e -p "API servers (default: ${api_servers:-localhost}): " input_api_servers
  api_servers=${input_api_servers:-${api_servers:-localhost}}

  echo ""
  echo "${CMSG}Cluster configuration:${CEND}"
  echo "  All nodes:     ${ips}"
  echo "  SSH port:      ${ssh_port}"
  echo "  Masters:       ${masters}"
  echo "  Workers:       ${workers}"
  echo "  Alert server:  ${alert_server}"
  echo "  API servers:   ${api_servers}"
  echo ""
}

# Interactive port configuration
Configure_Ports_Interactive() {
  echo ""
  echo "${CMSG}========== Port Configuration ==========${CEND}"
  echo ""

  if [ "${deploy_mode}" == "standalone" ]; then
    read -e -p "Web UI port (default: ${web_port:-12345}): " input_web_port
    web_port=${input_web_port:-${web_port:-12345}}
  else
    read -e -p "API Server port (default: ${api_port:-25333}): " input_api_port
    api_port=${input_api_port:-${api_port:-25333}}

    # Each server needs an RPC port plus a web port for actuator/metrics
    read -e -p "Master RPC port (default: ${master_rpc_port:-5678}): " input_master_port
    master_rpc_port=${input_master_port:-${master_rpc_port:-5678}}
    read -e -p "Master web port (default: ${master_web_port:-$((master_rpc_port + 1))}): " input_master_web_port
    master_web_port=${input_master_web_port:-${master_web_port:-$((master_rpc_port + 1))}}

    read -e -p "Worker RPC port (default: ${worker_rpc_port:-1234}): " input_worker_port
    worker_rpc_port=${input_worker_port:-${worker_rpc_port:-1234}}
    read -e -p "Worker web port (default: ${worker_web_port:-$((worker_rpc_port + 1))}): " input_worker_web_port
    worker_web_port=${input_worker_web_port:-${worker_web_port:-$((worker_rpc_port + 1))}}

    read -e -p "Alert RPC port (default: ${alert_rpc_port:-50052}): " input_alert_port
    alert_rpc_port=${input_alert_port:-${alert_rpc_port:-50052}}
    read -e -p "Alert web port (default: ${alert_web_port:-$((alert_rpc_port + 1))}): " input_alert_web_port
    alert_web_port=${input_alert_web_port:-${alert_web_port:-$((alert_rpc_port + 1))}}
  fi

  echo "${CSUCCESS}Port configuration completed.${CEND}"
}

# Interactive resource storage configuration
Configure_Storage_Interactive() {
  echo ""
  echo "${CMSG}========== Resource Storage Configuration ==========${CEND}"
  echo ""

  while :; do
    echo "Please select resource storage type:"
    echo -e "\t${CMSG}1${CEND}. LOCAL (Local filesystem)"
    echo -e "\t${CMSG}2${CEND}. HDFS"
    echo -e "\t${CMSG}3${CEND}. S3"
    echo -e "\t${CMSG}4${CEND}. NONE (Disable resource storage)"
    read -e -p "Please input a number:(Default 1 press Enter) " storage_option
    storage_option=${storage_option:-1}
    if [[ ! ${storage_option} =~ ^[1-4]$ ]]; then
      echo "${CWARNING}input error! Please only input 1~4${CEND}"
    else
      break
    fi
  done

  case "${storage_option}" in
    1)
      resource_storage_type="LOCAL"
      read -e -p "Local storage path (default: ${resource_local_path:-/data/dolphinscheduler/resource}): " input_local_path
      resource_local_path=${input_local_path:-${resource_local_path:-/data/dolphinscheduler/resource}}
      ;;
    2)
      resource_storage_type="HDFS"
      read -e -p "HDFS defaultFS (e.g. hdfs://namenode:8020): " hdfs_defaultfs
      read -e -p "HDFS root path (default: /dolphinscheduler): " input_hdfs_root
      hdfs_root_path=${input_hdfs_root:-/dolphinscheduler}
      ;;
    3)
      resource_storage_type="S3"
      read -e -p "S3 endpoint: " s3_endpoint
      read -e -p "S3 access key: " s3_access_key
      read -e -s -p "S3 secret key: " s3_secret_key
      echo ""
      read -e -p "S3 region: " s3_region
      read -e -p "S3 bucket: " s3_bucket
      ;;
    4)
      resource_storage_type="NONE"
      ;;
  esac

  echo "${CSUCCESS}Resource storage: ${resource_storage_type}${CEND}"
}

# Save configuration to options.conf
Save_Configuration() {
  echo ""
  echo "${CMSG}Saving configuration to options.conf...${CEND}"

  # Update options.conf
  sed -i "s|^deploy_mode=.*|deploy_mode=${deploy_mode}|" ${ds_dir}/options.conf

  # Database configuration
  sed -i "s|^db_type=.*|db_type=${db_type}|" ${ds_dir}/options.conf
  sed -i "s|^db_host=.*|db_host=${db_host}|" ${ds_dir}/options.conf
  sed -i "s|^db_port=.*|db_port=${db_port}|" ${ds_dir}/options.conf
  sed -i "s|^db_name=.*|db_name=${db_name}|" ${ds_dir}/options.conf
  sed -i "s|^db_user=.*|db_user=${db_user}|" ${ds_dir}/options.conf
  sed -i "s|^db_password=.*|db_password=${db_password}|" ${ds_dir}/options.conf

  # ZooKeeper configuration
  sed -i "s|^zk_hosts=.*|zk_hosts=${zk_hosts}|" ${ds_dir}/options.conf

  # Cluster configuration
  sed -i "s|^ips=.*|ips=${ips}|" ${ds_dir}/options.conf
  sed -i "s|^ssh_port=.*|ssh_port=${ssh_port}|" ${ds_dir}/options.conf
  sed -i "s|^masters=.*|masters=${masters}|" ${ds_dir}/options.conf
  sed -i "s|^workers=.*|workers=${workers}|" ${ds_dir}/options.conf
  sed -i "s|^alert_server=.*|alert_server=${alert_server}|" ${ds_dir}/options.conf
  sed -i "s|^api_servers=.*|api_servers=${api_servers}|" ${ds_dir}/options.conf

  # Port configuration
  sed -i "s|^web_port=.*|web_port=${web_port}|" ${ds_dir}/options.conf
  sed -i "s|^api_port=.*|api_port=${api_port}|" ${ds_dir}/options.conf
  sed -i "s|^master_rpc_port=.*|master_rpc_port=${master_rpc_port}|" ${ds_dir}/options.conf
  sed -i "s|^master_web_port=.*|master_web_port=${master_web_port}|" ${ds_dir}/options.conf
  sed -i "s|^worker_rpc_port=.*|worker_rpc_port=${worker_rpc_port}|" ${ds_dir}/options.conf
  sed -i "s|^worker_web_port=.*|worker_web_port=${worker_web_port}|" ${ds_dir}/options.conf
  sed -i "s|^alert_rpc_port=.*|alert_rpc_port=${alert_rpc_port}|" ${ds_dir}/options.conf
  sed -i "s|^alert_web_port=.*|alert_web_port=${alert_web_port}|" ${ds_dir}/options.conf

  # Resource storage configuration
  sed -i "s|^resource_storage_type=.*|resource_storage_type=${resource_storage_type}|" ${ds_dir}/options.conf
  sed -i "s|^resource_local_path=.*|resource_local_path=${resource_local_path}|" ${ds_dir}/options.conf
  [ -n "${hdfs_defaultfs}" ] && sed -i "s|^hdfs_defaultfs=.*|hdfs_defaultfs=${hdfs_defaultfs}|" ${ds_dir}/options.conf
  [ -n "${hdfs_root_path}" ] && sed -i "s|^hdfs_root_path=.*|hdfs_root_path=${hdfs_root_path}|" ${ds_dir}/options.conf
  [ -n "${s3_endpoint}" ] && sed -i "s|^s3_endpoint=.*|s3_endpoint=${s3_endpoint}|" ${ds_dir}/options.conf
  [ -n "${s3_access_key}" ] && sed -i "s|^s3_access_key=.*|s3_access_key=${s3_access_key}|" ${ds_dir}/options.conf
  [ -n "${s3_secret_key}" ] && sed -i "s|^s3_secret_key=.*|s3_secret_key=${s3_secret_key}|" ${ds_dir}/options.conf
  [ -n "${s3_region}" ] && sed -i "s|^s3_region=.*|s3_region=${s3_region}|" ${ds_dir}/options.conf
  [ -n "${s3_bucket}" ] && sed -i "s|^s3_bucket=.*|s3_bucket=${s3_bucket}|" ${ds_dir}/options.conf

  echo "${CSUCCESS}Configuration saved to options.conf${CEND}"
}

# Show configuration summary
Show_Config_Summary() {
  echo ""
  echo "${CMSG}========== Configuration Summary ==========${CEND}"
  echo ""
  echo "  DolphinScheduler Version: ${ds_ver}"
  echo "  Deployment Mode:          ${deploy_mode}"
  echo ""

  if [ "${deploy_mode}" != "standalone" ]; then
    echo "  Database:"
    echo "    Type:     ${db_type}"
    echo "    Host:     ${db_host}:${db_port}"
    echo "    Database: ${db_name}"
    echo "    User:     ${db_user}"
    echo ""
    echo "  ZooKeeper:  ${zk_hosts}"
    echo ""
  fi

  if [ "${deploy_mode}" == "standalone" ]; then
    echo "  Ports:"
    echo "    Web UI:   ${web_port}"
  else
    echo "  Ports:"
    echo "    API:      ${api_port}"
    echo "    Master:   ${master_rpc_port} (rpc) / ${master_web_port} (web)"
    echo "    Worker:   ${worker_rpc_port} (rpc) / ${worker_web_port} (web)"
    echo "    Alert:    ${alert_rpc_port} (rpc) / ${alert_web_port} (web)"
  fi

  if [ "${deploy_mode}" == "cluster" ]; then
    echo ""
    echo "  Cluster Nodes:"
    echo "    All:      ${ips}"
    echo "    Masters:  ${masters}"
    echo "    Workers:  ${workers}"
    echo "    API:      ${api_servers}"
    echo "    Alert:    ${alert_server}"
    echo "    SSH as:   ${remote_ssh_user:-root}"
  fi
  echo ""
}

# Confirm configuration before installation
Confirm_Installation() {
  Show_Config_Summary

  while :; do
    read -e -p "Proceed with installation? [y/n]: " confirm
    if [[ ! ${confirm} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done

  if [ "${confirm}" != "y" ]; then
    echo "Installation cancelled."
    exit 0
  fi
}

# Main installation flow
Main() {
  # Select version
  Select_Version

  # Select deployment mode
  Select_Deploy_Mode

  # Roles: only meaningful for multi-process modes. An empty value means
  # "all roles on this node", which is what pseudo-cluster does.
  if [ "${deploy_mode}" == "pseudo-cluster" ]; then
    node_roles="master,worker,api,alert"
  fi
  if [ "${deploy_mode}" == "node" ] && [ -z "${node_roles}" ]; then
    echo "${CFAILURE}--roles is required when deploy_mode is 'node'.${CEND}"
    exit 1
  fi

  # Check environment
  echo ""
  echo "${CMSG}[1/6] Checking environment...${CEND}"
  Check_Deps
  Create_User
  Detect_Network

  # Configure sudo for the multi-process modes
  if [ "${deploy_mode}" != "standalone" ]; then
    Configure_Sudo || exit 1
    Configure_SSH
  fi

  # Check Java
  echo ""
  echo "${CMSG}[2/6] Checking Java environment...${CEND}"
  if ! Check_Java; then
    if [ "${quiet_flag}" == "y" ]; then
      Install_Java
    else
      while :; do
        read -e -p "Java not found. Install OpenJDK 8? [y/n]: " install_java_flag
        if [[ ! ${install_java_flag} =~ ^[y,n]$ ]]; then
          echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
        else
          break
        fi
      done
      [ "${install_java_flag}" == 'y' ] && Install_Java
    fi
    if ! Check_Java; then
      echo "${CFAILURE}Java is required for DolphinScheduler. Please install JDK 8+ manually.${CEND}"
      exit 1
    fi
  fi

  # Interactive configuration for pseudo-cluster and cluster modes
  # ('node' is driven by the cluster deployment and never asks anything)
  if [ "${deploy_mode}" != "standalone" ] && [ "${deploy_mode}" != "node" ] && [ "${quiet_flag}" != "y" ]; then
    echo ""
    echo "${CMSG}[2.5/6] Configuring external dependencies...${CEND}"

    # Database configuration
    Configure_Database_Interactive

    # ZooKeeper configuration
    Configure_ZooKeeper_Interactive

    # Cluster configuration (only for cluster mode)
    if [ "${deploy_mode}" == "cluster" ]; then
      Configure_Cluster_Interactive
    fi

    # Port configuration
    Configure_Ports_Interactive

    # Resource storage configuration
    Configure_Storage_Interactive

    # Save configuration
    Save_Configuration

    # Confirm installation
    Confirm_Installation
  fi

  # Check dependencies for pseudo-cluster and cluster modes
  if [ "${deploy_mode}" != "standalone" ]; then
    echo ""
    echo "${CMSG}[3/6] Checking external dependencies...${CEND}"

    # Check ZooKeeper
    if ! Check_ZooKeeper; then
      echo "${CFAILURE}ZooKeeper is required for ${deploy_mode} mode.${CEND}"
      echo "${CFAILURE}Please install and start ZooKeeper first.${CEND}"
      exit 1
    fi

    # Check database connection. A database that cannot be reached from this node
    # makes the whole installation useless, so this is a hard failure.
    if [ -z "${db_password}" ]; then
      echo "${CFAILURE}Database password not configured!${CEND}"
      exit 1
    fi

    if ! Check_Database; then
      echo "${CWARNING}Attempting to create database '${db_name}'...${CEND}"
      if ! Create_Database || ! Check_Database; then
        Print_DB_Access_Hint
        echo "${CFAILURE}Database is not usable from this node (${local_ip}). Aborting.${CEND}"
        exit 1
      fi
    fi
  fi

  # Download packages
  echo ""
  echo "${CMSG}[4/6] Downloading DolphinScheduler ${ds_ver} package...${CEND}"
  mkdir -p ${ds_dir}/src
  Download_DolphinScheduler "${ds_ver}"

  # Download MySQL JDBC driver for pseudo-cluster and cluster modes
  if [ "${deploy_mode}" != "standalone" ] && [ "${db_type}" == "mysql" ]; then
    echo "${CMSG}Downloading MySQL JDBC driver...${CEND}"
    Download_MySQL_JDBC
  fi

  if [ "${download_only_flag}" == "y" ]; then
    echo "${CSUCCESS}Download completed! Package saved to ${ds_dir}/src/${CEND}"
    exit 0
  fi

  # Check ports (in cluster mode this is done per node during deployment)
  if [ "${deploy_mode}" != "cluster" ]; then
    echo ""
    echo "${CMSG}[5/6] Checking ports...${CEND}"
    Check_Ports "${deploy_mode}" || exit 1
  fi

  # Install
  echo ""
  echo "${CMSG}[6/6] Installing DolphinScheduler ${ds_ver} (mode: ${deploy_mode})...${CEND}"

  case "${deploy_mode}" in
    standalone)
      Install_DolphinScheduler_Standalone "${ds_ver}" || exit 1
      Start_Standalone || exit 1
      ;;

    pseudo-cluster)
      Install_DolphinScheduler_PseudoCluster "${ds_ver}" || exit 1
      Start_PseudoCluster || exit 1
      ;;

    cluster)
      Deploy_Cluster "${ds_ver}" || exit 1
      Start_Cluster || exit 1
      ;;

    node)
      # Single node of a cluster: install and enable, the control node starts it
      Install_DolphinScheduler_PseudoCluster "${ds_ver}" || exit 1
      echo "${CSUCCESS}Node prepared (roles: ${node_roles}). Services will be started by the control node.${CEND}"
      exit 0
      ;;
  esac

  # Print summary
  echo ""
  echo "${CSUCCESS}============================================${CEND}"
  echo "${CSUCCESS}  Installation Completed!${CEND}"
  echo "${CSUCCESS}============================================${CEND}"
  echo ""

  if [ "${deploy_mode}" == "standalone" ]; then
    echo "  Web UI:     http://${local_ip}:${web_port}/dolphinscheduler/ui"
    echo "  Username:   admin"
    echo "  Password:   dolphinscheduler123"
    echo ""
    echo "  Service Management:"
    echo "    systemctl {start|stop|restart|status} dolphinscheduler-standalone"
  else
    # The UI lives on the API server(s)
    local ui_host="${local_ip}"
    if [ "${deploy_mode}" == "cluster" ]; then
      ui_host="${api_servers%%,*}"
    fi
    echo "  Web UI:     http://${ui_host}:${api_port}/dolphinscheduler/ui"
    echo "  Username:   admin"
    echo "  Password:   dolphinscheduler123"
    echo ""

    if [ "${deploy_mode}" == "cluster" ]; then
      echo "  Node roles:"
      for ip in ${ips//,/ }; do
        echo "    ${ip}: $(Get_Node_Roles ${ip})"
      done
      echo ""
      echo "  Cluster Management (from this node):"
      echo "    ./install.sh --status"
      echo ""
    fi

    echo "  Service Management (on each node, for its own roles):"
    echo "    systemctl {start|stop|restart|status} dolphinscheduler-{master|worker|api|alert}"
  fi
  echo ""
}

Main
popd > /dev/null
