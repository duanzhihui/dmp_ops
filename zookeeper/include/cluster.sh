#!/bin/bash
# ZooKeeper 集群管理模块
# 项目: oneinstack/zookeeper

# 部署集群配置
Deploy_Cluster() {
  echo "${CMSG}=== Deploying ZooKeeper Cluster Configuration ===${CEND}"
  
  if [ -z "${cluster_nodes}" ]; then
    echo "${CFAILURE}cluster_nodes is not configured!${CEND}"
    echo "Please set cluster_nodes in options.conf"
    echo "Format: \"1:192.168.1.10 2:192.168.1.11 3:192.168.1.12\""
    return 1
  fi
  
  if [ -z "${myid}" ]; then
    echo "${CFAILURE}myid is not configured!${CEND}"
    return 1
  fi
  
  # 验证节点数量
  local node_count=$(echo "${cluster_nodes}" | wc -w)
  if [ $((node_count % 2)) -eq 0 ]; then
    echo "${CWARNING}Warning: Cluster should have odd number of nodes (current: ${node_count})${CEND}"
  fi
  
  if [ "${node_count}" -lt 3 ]; then
    echo "${CFAILURE}Cluster requires at least 3 nodes (current: ${node_count})${CEND}"
    return 1
  fi
  
  echo "Cluster nodes:"
  for node in ${cluster_nodes}; do
    local node_id="${node%%:*}"
    local node_host="${node#*:}"
    echo "  server.${node_id} = ${node_host}:${zk_peer_port}:${zk_election_port}"
  done
  echo "This node myid: ${myid}"
  
  # 更新配置
  Generate_ZK_Config
  
  echo "${CSUCCESS}Cluster configuration deployed${CEND}"
  echo "Please restart ZooKeeper: systemctl restart zookeeper"
}

# 检查集群状态
Check_Cluster_Status() {
  echo "${CMSG}=== ZooKeeper Cluster Status ===${CEND}"
  
  if [ -z "${cluster_nodes}" ]; then
    echo "Running in standalone mode"
    Check_Node_Status "127.0.0.1" "${zk_client_port}"
    return 0
  fi
  
  local leader_found=0
  local healthy_nodes=0
  local total_nodes=0
  
  for node in ${cluster_nodes}; do
    local node_id="${node%%:*}"
    local node_host="${node#*:}"
    total_nodes=$((total_nodes + 1))
    
    echo ""
    echo "--- Node ${node_id}: ${node_host} ---"
    
    local status=$(echo "srvr" | nc -w 2 ${node_host} ${zk_client_port} 2>/dev/null)
    
    if [ -n "${status}" ]; then
      local mode=$(echo "${status}" | grep "Mode:" | awk '{print $2}')
      local connections=$(echo "${status}" | grep "Connections:" | awk '{print $2}')
      local znode_count=$(echo "${status}" | grep "Node count:" | awk '{print $3}')
      
      echo "  Status: ${CSUCCESS}ONLINE${CEND}"
      echo "  Mode: ${mode}"
      echo "  Connections: ${connections}"
      echo "  ZNode Count: ${znode_count}"
      
      healthy_nodes=$((healthy_nodes + 1))
      
      if [ "${mode}" == "leader" ]; then
        leader_found=1
        echo "  ${CSUCCESS}★ LEADER${CEND}"
      fi
    else
      echo "  Status: ${CFAILURE}OFFLINE${CEND}"
    fi
  done
  
  echo ""
  echo "${CMSG}=== Cluster Summary ===${CEND}"
  echo "  Total Nodes: ${total_nodes}"
  echo "  Healthy Nodes: ${healthy_nodes}"
  
  if [ "${leader_found}" -eq 1 ]; then
    echo "  Leader: ${CSUCCESS}ELECTED${CEND}"
  else
    echo "  Leader: ${CFAILURE}NOT FOUND${CEND}"
  fi
  
  # 判断集群健康状态
  local quorum=$((total_nodes / 2 + 1))
  if [ "${healthy_nodes}" -ge "${quorum}" ] && [ "${leader_found}" -eq 1 ]; then
    echo "  Cluster: ${CSUCCESS}HEALTHY${CEND}"
    return 0
  else
    echo "  Cluster: ${CFAILURE}UNHEALTHY${CEND}"
    return 1
  fi
}

# 检查单个节点状态
Check_Node_Status() {
  local host=$1
  local port=$2
  
  local status=$(echo "srvr" | nc -w 2 ${host} ${port} 2>/dev/null)
  
  if [ -n "${status}" ]; then
    echo "${status}"
    return 0
  else
    echo "${CFAILURE}Node unreachable: ${host}:${port}${CEND}"
    return 1
  fi
}

# 添加节点（动态配置）
Add_Node() {
  local node_id=$1
  local node_host=$2
  
  if [ -z "${node_id}" ] || [ -z "${node_host}" ]; then
    echo "Usage: Add_Node <node_id> <node_host>"
    echo "Example: Add_Node 4 192.168.1.13"
    return 1
  fi
  
  echo "${CMSG}Adding node: server.${node_id}=${node_host}:${zk_peer_port}:${zk_election_port}${CEND}"
  
  # 检查是否已存在
  if grep -q "server.${node_id}=" "${zk_install_dir}/conf/zoo.cfg"; then
    echo "${CWARNING}Node ${node_id} already exists in configuration${CEND}"
    return 1
  fi
  
  # 添加到配置文件
  echo "server.${node_id}=${node_host}:${zk_peer_port}:${zk_election_port}" >> "${zk_install_dir}/conf/zoo.cfg"
  
  # 更新 options.conf
  if [ -n "${cluster_nodes}" ]; then
    cluster_nodes="${cluster_nodes} ${node_id}:${node_host}"
  else
    cluster_nodes="${node_id}:${node_host}"
  fi
  sed -i "s@^cluster_nodes=.*@cluster_nodes=${cluster_nodes}@" "${script_dir}/options.conf"
  
  echo "${CSUCCESS}Node added to configuration${CEND}"
  echo "Please restart ZooKeeper on all nodes: systemctl restart zookeeper"
}

# 移除节点
Remove_Node() {
  local node_id=$1
  
  if [ -z "${node_id}" ]; then
    echo "Usage: Remove_Node <node_id>"
    return 1
  fi
  
  echo "${CMSG}Removing node: server.${node_id}${CEND}"
  
  # 从配置文件移除
  sed -i "/^server.${node_id}=/d" "${zk_install_dir}/conf/zoo.cfg"
  
  # 更新 options.conf
  cluster_nodes=$(echo "${cluster_nodes}" | sed "s/${node_id}:[^ ]*//g" | tr -s ' ')
  sed -i "s@^cluster_nodes=.*@cluster_nodes=${cluster_nodes}@" "${script_dir}/options.conf"
  
  echo "${CSUCCESS}Node removed from configuration${CEND}"
  echo "Please restart ZooKeeper on all nodes: systemctl restart zookeeper"
}

# 生成集群部署脚本
Generate_Cluster_Deploy_Script() {
  local output_dir=${1:-/tmp/zk_cluster_deploy}
  
  if [ -z "${cluster_nodes}" ]; then
    echo "${CFAILURE}cluster_nodes is not configured!${CEND}"
    return 1
  fi
  
  mkdir -p "${output_dir}"
  
  echo "${CMSG}Generating cluster deployment scripts...${CEND}"
  
  for node in ${cluster_nodes}; do
    local node_id="${node%%:*}"
    local node_host="${node#*:}"
    
    cat > "${output_dir}/deploy_node_${node_id}.sh" << EOF
#!/bin/bash
# ZooKeeper Node ${node_id} Deployment Script
# Target Host: ${node_host}

cd \$(dirname \$0)/../

# 设置节点 ID
sed -i "s@^myid=.*@myid=${node_id}@" options.conf
sed -i "s@^deploy_mode=.*@deploy_mode=cluster@" options.conf

# 安装
./install.sh --cluster --myid ${node_id}
EOF
    
    chmod +x "${output_dir}/deploy_node_${node_id}.sh"
    echo "Generated: ${output_dir}/deploy_node_${node_id}.sh"
  done
  
  echo "${CSUCCESS}Cluster deployment scripts generated in: ${output_dir}${CEND}"
}
