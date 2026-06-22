#!/bin/bash
# ZooKeeper 安装主入口
# 项目: oneinstack/zookeeper
# 用法: ./install.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本目录
script_dir=$(cd "$(dirname "$0")" && pwd)
src_dir="${script_dir}/src"

# Root 检查
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# 加载配置和公共库
. "${script_dir}/options.conf"
. "${script_dir}/versions.txt"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/check_os.sh"
. "${script_dir}/include/check_env.sh"
. "${script_dir}/include/download.sh"
. "${script_dir}/include/zookeeper.sh"
. "${script_dir}/include/cluster.sh"

# 显示帮助
Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

ZooKeeper Installation Script

Options:
  -h, --help              Show this help message
  -v, --version           Show version information
  -q, --quiet             Quiet mode, skip confirmations
  
  --standalone            Install in standalone mode (default)
  --cluster               Install in cluster mode
  
  --zk_ver VERSION        Specify ZooKeeper version (default: ${zk_ver})
  --myid ID               Specify node ID for cluster mode
  --nodes "ID:HOST ..."   Specify cluster nodes
  
Examples:
  # Standalone installation
  $0 --standalone --zk_ver 3.9.5
  
  # Cluster installation
  $0 --cluster --zk_ver 3.9.5 --myid 1 --nodes "1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"

EOF
}

# 显示版本
Show_Version() {
  echo "ZooKeeper Installation Script"
  echo "Available versions: ${zk39_ver}, ${zk38_ver}, ${zk37_ver}"
  echo "Default version: ${zk_ver}"
}

# 交互式菜单
Show_Menu() {
  clear
  echo ""
  echo "${CMSG}#######################################################################${CEND}"
  echo "${CMSG}#                  ZooKeeper Installation Script                     #${CEND}"
  echo "${CMSG}#                    https://zookeeper.apache.org                    #${CEND}"
  echo "${CMSG}#######################################################################${CEND}"
  echo ""
  
  # 检测操作系统
  Check_OS
  echo ""
  
  # 选择版本
  echo "${CMSG}Please select ZooKeeper version:${CEND}"
  echo "  1) ${zk39_ver} (latest, requires JDK 11+)"
  echo "  2) ${zk38_ver} (stable, requires JDK 8+)"
  echo "  3) ${zk37_ver} (legacy, requires JDK 8+)"
  echo ""
  
  while :; do
    read -e -p "Enter your choice [1-3, default: 1]: " ver_choice
    ver_choice=${ver_choice:-1}
    case "${ver_choice}" in
      1)
        zk_ver="${zk39_ver}"
        break
        ;;
      2)
        zk_ver="${zk38_ver}"
        break
        ;;
      3)
        zk_ver="${zk37_ver}"
        break
        ;;
      *)
        echo "${CWARNING}Invalid choice, please try again${CEND}"
        ;;
    esac
  done
  
  echo ""
  echo "Selected version: ${CMSG}${zk_ver}${CEND}"
  echo ""
  
  # 选择部署模式
  echo "${CMSG}Please select deployment mode:${CEND}"
  echo "  1) Standalone (single node, for development/testing)"
  echo "  2) Cluster (multiple nodes, for production)"
  echo ""
  
  while :; do
    read -e -p "Enter your choice [1-2, default: 1]: " mode_choice
    mode_choice=${mode_choice:-1}
    case "${mode_choice}" in
      1)
        deploy_mode="standalone"
        break
        ;;
      2)
        deploy_mode="cluster"
        break
        ;;
      *)
        echo "${CWARNING}Invalid choice, please try again${CEND}"
        ;;
    esac
  done
  
  echo ""
  echo "Selected mode: ${CMSG}${deploy_mode}${CEND}"
  
  # 集群模式配置
  if [ "${deploy_mode}" == "cluster" ]; then
    echo ""
    echo "${CMSG}Cluster Configuration:${CEND}"
    
    read -e -p "Enter this node's ID [1-255]: " myid
    myid=${myid:-1}
    
    echo ""
    echo "Enter cluster nodes (format: ID:HOST, space separated)"
    echo "Example: 1:192.168.1.10 2:192.168.1.11 3:192.168.1.12"
    read -e -p "Nodes: " cluster_nodes
    
    if [ -z "${cluster_nodes}" ]; then
      echo "${CFAILURE}Cluster nodes cannot be empty!${CEND}"
      exit 1
    fi
  fi
  
  echo ""
  echo "${CMSG}=== Installation Summary ===${CEND}"
  echo "  Version: ${zk_ver}"
  echo "  Mode: ${deploy_mode}"
  echo "  Install Dir: ${zk_install_dir}"
  echo "  Data Dir: ${zk_data_dir}"
  echo "  Client Port: ${zk_client_port}"
  [ "${deploy_mode}" == "cluster" ] && {
    echo "  MyID: ${myid}"
    echo "  Nodes: ${cluster_nodes}"
  }
  echo ""
  
  read -e -p "Continue with installation? [y/n]: " confirm
  [ "${confirm}" != "y" ] && exit 0
}

# 解析参数
ARG_NUM=$#
quiet_mode=0

TEMP=$(getopt -o hvq --long help,version,quiet,standalone,cluster,zk_ver:,myid:,nodes: -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }

eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    -v|--version)
      Show_Version
      exit 0
      ;;
    -q|--quiet)
      quiet_mode=1
      shift
      ;;
    --standalone)
      deploy_mode="standalone"
      shift
      ;;
    --cluster)
      deploy_mode="cluster"
      shift
      ;;
    --zk_ver)
      zk_ver="$2"
      shift 2
      ;;
    --myid)
      myid="$2"
      shift 2
      ;;
    --nodes)
      cluster_nodes="$2"
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

# 主逻辑
main() {
  # 无参数时显示交互菜单
  if [ ${ARG_NUM} -eq 0 ]; then
    Show_Menu
  else
    # 检测操作系统
    Check_OS
  fi
  
  # 更新配置文件
  sed -i "s@^zk_ver=.*@zk_ver=${zk_ver}@" "${script_dir}/versions.txt"
  sed -i "s@^deploy_mode=.*@deploy_mode=${deploy_mode}@" "${script_dir}/options.conf"
  sed -i "s@^myid=.*@myid=${myid}@" "${script_dir}/options.conf"
  sed -i "s@^cluster_nodes=.*@cluster_nodes=${cluster_nodes}@" "${script_dir}/options.conf"
  
  # 执行安装
  Install_ZooKeeper
  
  exit $?
}

main
