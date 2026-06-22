#!/bin/bash
# ZooKeeper 升级模块
# 项目: oneinstack/zookeeper

# 升级 ZooKeeper
Upgrade_ZooKeeper() {
  local new_ver=${1:-}
  
  # 1. 检测当前版本
  if [ ! -e "${zk_install_dir}/bin/zkServer.sh" ]; then
    echo "${CFAILURE}ZooKeeper is not installed!${CEND}"
    return 1
  fi
  
  # 获取当前版本
  local old_ver
  if [ -f "${zk_install_dir}/zookeeper-version.txt" ]; then
    old_ver=$(cat "${zk_install_dir}/zookeeper-version.txt")
  else
    old_ver=$(ls "${zk_install_dir}/lib/zookeeper-"*.jar 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
  fi
  
  if [ -z "${old_ver}" ]; then
    echo "${CFAILURE}Cannot detect current ZooKeeper version!${CEND}"
    return 1
  fi
  
  echo "${CMSG}=== ZooKeeper Upgrade ===${CEND}"
  echo "Current Version: ${CMSG}${old_ver}${CEND}"
  
  # 2. 获取目标版本
  if [ -z "${new_ver}" ]; then
    echo ""
    echo "Available versions:"
    echo "  1) 3.9.5 (latest, requires JDK 11+)"
    echo "  2) 3.8.6 (stable, requires JDK 8+)"
    echo "  3) 3.7.2 (legacy, requires JDK 8+)"
    echo ""
    read -e -p "Please input upgrade version (e.g., 3.9.5): " new_ver
  fi
  
  if [ -z "${new_ver}" ]; then
    echo "${CFAILURE}No version specified!${CEND}"
    return 1
  fi
  
  # 3. 版本校验
  if [ "${new_ver}" == "${old_ver}" ]; then
    echo "${CWARNING}Same version, skip upgrade${CEND}"
    return 0
  fi
  
  # 主版本校验
  local old_major="${old_ver%%.*}"
  local new_major="${new_ver%%.*}"
  
  if [ "${old_major}" != "${new_major}" ]; then
    echo "${CWARNING}Cross major version upgrade detected: ${old_major}.x -> ${new_major}.x${CEND}"
    read -e -p "This may cause compatibility issues. Continue? [y/n]: " confirm
    [ "${confirm}" != "y" ] && return 0
  fi
  
  # 检测 JDK 版本
  Check_JDK_For_ZK "${new_ver}" || return 1
  
  # 4. 升级前备份
  echo "${CMSG}Backing up current installation...${CEND}"
  local backup_dir="${zk_install_dir}_backup_$(date +%Y%m%d%H%M)"
  cp -a "${zk_install_dir}" "${backup_dir}"
  echo "Backup created: ${backup_dir}"
  
  # 备份配置文件
  cp "${zk_install_dir}/conf/zoo.cfg" "${zk_install_dir}/conf/zoo.cfg.bak"
  [ -f "${zk_install_dir}/conf/java.env" ] && cp "${zk_install_dir}/conf/java.env" "${zk_install_dir}/conf/java.env.bak"
  
  # 5. 下载新版本
  echo "${CMSG}Downloading ZooKeeper ${new_ver}...${CEND}"
  src_url="https://archive.apache.org/dist/zookeeper/zookeeper-${new_ver}/apache-zookeeper-${new_ver}-bin.tar.gz"
  Download_src || {
    echo "${CFAILURE}Download failed!${CEND}"
    return 1
  }
  
  # 6. 停止服务
  echo "${CMSG}Stopping ZooKeeper service...${CEND}"
  systemctl stop zookeeper
  sleep 2
  
  # 7. 解压新版本
  echo "${CMSG}Extracting new version...${CEND}"
  tar xzf "${src_dir}/apache-zookeeper-${new_ver}-bin.tar.gz" -C /tmp/
  
  if [ ! -d "/tmp/apache-zookeeper-${new_ver}-bin" ]; then
    echo "${CFAILURE}Extract failed! Rolling back...${CEND}"
    Rollback_Upgrade "${backup_dir}"
    return 1
  fi
  
  # 8. 替换文件（保留配置）
  echo "${CMSG}Replacing files...${CEND}"
  rm -rf "${zk_install_dir}/lib" "${zk_install_dir}/bin"
  cp -a /tmp/apache-zookeeper-${new_ver}-bin/lib "${zk_install_dir}/"
  cp -a /tmp/apache-zookeeper-${new_ver}-bin/bin "${zk_install_dir}/"
  
  # 更新其他目录（保留 conf）
  for dir in docs recipes contrib; do
    [ -d "/tmp/apache-zookeeper-${new_ver}-bin/${dir}" ] && {
      rm -rf "${zk_install_dir}/${dir}"
      cp -a "/tmp/apache-zookeeper-${new_ver}-bin/${dir}" "${zk_install_dir}/"
    }
  done
  
  # 恢复配置文件
  cp "${zk_install_dir}/conf/zoo.cfg.bak" "${zk_install_dir}/conf/zoo.cfg"
  [ -f "${zk_install_dir}/conf/java.env.bak" ] && cp "${zk_install_dir}/conf/java.env.bak" "${zk_install_dir}/conf/java.env"
  
  # 记录新版本
  echo "${new_ver}" > "${zk_install_dir}/zookeeper-version.txt"
  
  # 清理临时文件
  rm -rf /tmp/apache-zookeeper-${new_ver}-bin
  
  # 9. 设置权限
  chown -R zookeeper:zookeeper "${zk_install_dir}"
  
  # 10. 启动服务
  echo "${CMSG}Starting ZooKeeper service...${CEND}"
  systemctl start zookeeper
  sleep 3
  
  # 11. 验证升级
  local response=$(echo "ruok" | nc -w 2 127.0.0.1 ${zk_client_port} 2>/dev/null)
  
  if [ "${response}" == "imok" ]; then
    echo "${CSUCCESS}=== Upgrade successful! ===${CEND}"
    echo "  Old Version: ${old_ver}"
    echo "  New Version: ${new_ver}"
    echo ""
    echo "Backup location: ${backup_dir}"
    echo "You can remove it after verifying the upgrade."
    return 0
  else
    echo "${CFAILURE}Upgrade verification failed! Rolling back...${CEND}"
    Rollback_Upgrade "${backup_dir}"
    return 1
  fi
}

# 回滚升级
Rollback_Upgrade() {
  local backup_dir=$1
  
  echo "${CMSG}Rolling back to previous version...${CEND}"
  
  systemctl stop zookeeper 2>/dev/null
  
  if [ -d "${backup_dir}" ]; then
    rm -rf "${zk_install_dir}"
    mv "${backup_dir}" "${zk_install_dir}"
    chown -R zookeeper:zookeeper "${zk_install_dir}"
    systemctl start zookeeper
    
    sleep 3
    local response=$(echo "ruok" | nc -w 2 127.0.0.1 ${zk_client_port} 2>/dev/null)
    
    if [ "${response}" == "imok" ]; then
      echo "${CSUCCESS}Rollback successful${CEND}"
    else
      echo "${CFAILURE}Rollback failed! Manual intervention required.${CEND}"
    fi
  else
    echo "${CFAILURE}Backup not found: ${backup_dir}${CEND}"
  fi
}

# 滚动升级（集群模式）
Rolling_Upgrade() {
  local new_ver=$1
  
  if [ "${deploy_mode}" != "cluster" ]; then
    echo "${CWARNING}Rolling upgrade is only for cluster mode${CEND}"
    Upgrade_ZooKeeper "${new_ver}"
    return $?
  fi
  
  echo "${CMSG}=== Rolling Upgrade ===${CEND}"
  echo "This will upgrade the current node only."
  echo "Please run this on each node one by one."
  echo ""
  
  # 检查当前节点角色
  local mode=$(echo "srvr" | nc -w 2 127.0.0.1 ${zk_client_port} 2>/dev/null | grep "Mode:" | awk '{print $2}')
  echo "Current node mode: ${mode}"
  
  if [ "${mode}" == "leader" ]; then
    echo "${CWARNING}This node is the LEADER.${CEND}"
    echo "It's recommended to upgrade followers first."
    read -e -p "Continue anyway? [y/n]: " confirm
    [ "${confirm}" != "y" ] && return 0
  fi
  
  Upgrade_ZooKeeper "${new_ver}"
}
