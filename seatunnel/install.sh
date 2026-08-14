#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Install Script
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

# Create src directory
mkdir -p ${seatunnel_dir}/src

# Source configuration and modules
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${seatunnel_dir}"
. ./options.conf
. ./versions.txt
. ./include/color.sh
. ./include/check_os.sh
. ./include/check_java.sh
. ./include/download.sh
. ./include/get_char.sh
. ./include/seatunnel_config.sh
. ./include/seatunnel.sh

# Version
SCRIPT_VERSION="1.0.0"

# Help message
Show_Help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -h, --help                  Show this help message"
  echo "  -v, --version               Show version"
  echo "  -q, --quiet                 Quiet mode, skip confirmations"
  echo "  --deploy_mode MODE          Deploy mode: local, hybrid, separated (default: hybrid)"
  echo "  --cluster_name NAME         Cluster name (default: seatunnel)"
  echo "  --cluster_members IPs       Cluster members, comma-separated (default: 127.0.0.1)"
  echo "  --node_role ROLE            Node role for separated mode: master, worker"
  echo "  --connectors LIST           Connectors to install, comma-separated"
  echo "  --jvm_heap SIZE             JVM heap size (default: 2g)"
  echo
  echo "Examples:"
  echo "  $0                                    # Interactive mode"
  echo "  $0 --deploy_mode local                # Install for local mode"
  echo "  $0 --deploy_mode hybrid -q            # Install hybrid mode quietly"
  echo "  $0 --deploy_mode separated --node_role master"
  echo
}

# Parse arguments
ARG_NUM=$#
TEMP=$(getopt -o hvq --long help,version,quiet,deploy_mode:,cluster_name:,cluster_members:,node_role:,connectors:,jvm_heap: -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "Invalid options"; Show_Help; exit 1; }
eval set -- "${TEMP}"

quiet_mode=false
while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    -v|--version)
      echo "SeaTunnel Ops Code v${SCRIPT_VERSION}"
      exit 0
      ;;
    -q|--quiet)
      quiet_mode=true
      shift
      ;;
    --deploy_mode)
      deploy_mode=$2
      shift 2
      ;;
    --cluster_name)
      cluster_name=$2
      shift 2
      ;;
    --cluster_members)
      cluster_members=$2
      shift 2
      ;;
    --node_role)
      node_role=$2
      shift 2
      ;;
    --connectors)
      connectors=$2
      shift 2
      ;;
    --jvm_heap)
      jvm_heap_size=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1"
      Show_Help
      exit 1
      ;;
  esac
done

# Interactive menu
Show_Menu() {
  echo
  echo "+----------------------------------------------------------------------+"
  echo "|        SeaTunnel Installation Script v${SCRIPT_VERSION}                        |"
  echo "+----------------------------------------------------------------------+"
  echo "|        A high-performance distributed data integration platform      |"
  echo "+----------------------------------------------------------------------+"
  echo

  # Select deploy mode
  echo "${CMSG}Select deployment mode:${CEND}"
  echo "  1. local     - Single machine, each job runs in separate process"
  echo "  2. hybrid    - Cluster mode, Master and Worker in same process"
  echo "  3. separated - Cluster mode, Master and Worker separated (Recommended for production)"
  echo
  
  while true; do
    read -e -p "Enter choice [1-3] (default: 2): " mode_choice
    mode_choice=${mode_choice:-2}
    case "${mode_choice}" in
      1)
        deploy_mode=local
        break
        ;;
      2)
        deploy_mode=hybrid
        break
        ;;
      3)
        deploy_mode=separated
        break
        ;;
      *)
        echo "${CWARNING}Invalid choice, please enter 1, 2, or 3${CEND}"
        ;;
    esac
  done

  # Cluster configuration (for hybrid and separated modes)
  if [ "${deploy_mode}" != "local" ]; then
    echo
    echo "${CMSG}Cluster Configuration:${CEND}"
    
    read -e -p "Cluster name (default: ${cluster_name}): " input_cluster_name
    cluster_name=${input_cluster_name:-${cluster_name}}
    
    read -e -p "Cluster members (comma-separated IPs, default: ${cluster_members}): " input_members
    cluster_members=${input_members:-${cluster_members}}

    if [ "${deploy_mode}" == "separated" ]; then
      echo
      echo "${CMSG}Node role for this machine:${CEND}"
      echo "  1. master - Job scheduling, REST API, task submission"
      echo "  2. worker - Task execution"
      echo
      while true; do
        read -e -p "Enter choice [1-2] (default: 1): " role_choice
        role_choice=${role_choice:-1}
        case "${role_choice}" in
          1)
            node_role=master
            break
            ;;
          2)
            node_role=worker
            break
            ;;
          *)
            echo "${CWARNING}Invalid choice, please enter 1 or 2${CEND}"
            ;;
        esac
      done
    fi
  fi

  # JVM configuration
  echo
  echo "${CMSG}JVM Configuration:${CEND}"
  read -e -p "JVM heap size (default: ${jvm_heap_size}): " input_heap
  jvm_heap_size=${input_heap:-${jvm_heap_size}}

  # Connectors configuration
  echo
  echo "${CMSG}Connector Plugins:${CEND}"
  echo "Common connectors: connector-fake, connector-console, connector-jdbc,"
  echo "                   connector-kafka, connector-cdc-mysql, connector-doris"
  read -e -p "Connectors to install (comma-separated, default: ${connectors}): " input_connectors
  connectors=${input_connectors:-${connectors}}
  # Remove spaces from connector list to prevent shell parsing issues
  connectors=$(echo "${connectors}" | tr -d ' ')

  # Summary
  echo
  echo "=========================================="
  echo "${CMSG}Installation Summary${CEND}"
  echo "=========================================="
  echo "SeaTunnel Version: ${seatunnel_ver}"
  echo "Deploy Mode:       ${deploy_mode}"
  if [ "${deploy_mode}" != "local" ]; then
    echo "Cluster Name:      ${cluster_name}"
    echo "Cluster Members:   ${cluster_members}"
    if [ "${deploy_mode}" == "separated" ]; then
      echo "Node Role:         ${node_role}"
    fi
  fi
  echo "Install Directory: ${seatunnel_install_dir}"
  echo "JVM Heap Size:     ${jvm_heap_size}"
  echo "Connectors:        ${connectors}"
  echo "=========================================="
  echo
}

# Main installation
Do_Install() {
  # Update options.conf with user selections
  sed -i "s@^deploy_mode=.*@deploy_mode=${deploy_mode}@" ${seatunnel_dir}/options.conf
  sed -i "s@^cluster_name=.*@cluster_name=${cluster_name}@" ${seatunnel_dir}/options.conf
  sed -i "s@^cluster_members=.*@cluster_members=${cluster_members}@" ${seatunnel_dir}/options.conf
  sed -i "s@^node_role=.*@node_role=${node_role}@" ${seatunnel_dir}/options.conf
  sed -i "s@^jvm_heap_size=.*@jvm_heap_size=${jvm_heap_size}@" ${seatunnel_dir}/options.conf
  sed -i "s@^connectors=.*@connectors=${connectors}@" ${seatunnel_dir}/options.conf

  # Install SeaTunnel
  Install_SeaTunnel
}

# Main logic
if [ ${ARG_NUM} -eq 0 ]; then
  # Interactive mode
  Show_Menu
  
  if [ "${quiet_mode}" != "true" ]; then
    read -e -p "Do you want to proceed with installation? [y/n]: " proceed
    if [[ ! "${proceed}" =~ ^[Yy]$ ]]; then
      echo "${CMSG}Installation cancelled.${CEND}"
      exit 0
    fi
  fi
  
  Do_Install
else
  # Command line mode
  if [ "${quiet_mode}" != "true" ]; then
    echo
    echo "${CMSG}Installing SeaTunnel with the following configuration:${CEND}"
    echo "  Deploy Mode:     ${deploy_mode}"
    echo "  Cluster Name:    ${cluster_name}"
    echo "  Cluster Members: ${cluster_members}"
    if [ "${deploy_mode}" == "separated" ]; then
      echo "  Node Role:       ${node_role}"
    fi
    echo "  JVM Heap:        ${jvm_heap_size}"
    echo "  Connectors:      ${connectors}"
    echo
    
    read -e -p "Do you want to proceed? [y/n]: " proceed
    if [[ ! "${proceed}" =~ ^[Yy]$ ]]; then
      echo "${CMSG}Installation cancelled.${CEND}"
      exit 0
    fi
  fi
  
  Do_Install
fi

popd > /dev/null
