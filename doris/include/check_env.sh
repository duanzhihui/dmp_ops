#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Environment check and preparation

Check_Java() {
  # Check JAVA_HOME
  if [ -n "${JAVA_HOME}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    JAVA_VER=$(${JAVA_HOME}/bin/java -version 2>&1 | head -1 | awk -F '"' '{print $2}')
    echo "${CSUCCESS}JAVA_HOME is set to: ${JAVA_HOME}${CEND}"
    echo "${CSUCCESS}Java version: ${JAVA_VER}${CEND}"
  elif command -v java > /dev/null 2>&1; then
    # Try to detect Java
    JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    JAVA_VER=$(java -version 2>&1 | head -1 | awk -F '"' '{print $2}')
    echo "${CSUCCESS}Auto-detected JAVA_HOME: ${JAVA_HOME}${CEND}"
    echo "${CSUCCESS}Java version: ${JAVA_VER}${CEND}"
  else
    echo "${CFAILURE}Java not found! Doris requires JDK 8 or JDK 17.${CEND}"
    return 1
  fi

  # Validate JDK version compatibility with Doris version
  if [ -n "${doris_major_ver}" ] && [ -n "${JAVA_VER}" ]; then
    local java_major=$(echo ${JAVA_VER} | awk -F. '{if($1=="1") print $2; else print $1}')
    if [ "${doris_major_ver}" -ge 3 ] && [ "${java_major:-0}" -lt 17 ]; then
      echo "${CWARNING}Doris ${doris_major_ver}.x requires JDK 17+, but JDK ${java_major} detected.${CEND}"
      return 1
    elif [ "${doris_major_ver}" -lt 3 ] && [ "${java_major:-0}" -ge 17 ]; then
      echo "${CWARNING}Doris 2.x recommends JDK 8, but JDK ${java_major} detected. May still work.${CEND}"
    fi
  fi

  return 0
}

Install_Java() {
  # Determine required JDK version based on doris_major_ver
  local jdk_ver=8
  [ "${doris_major_ver:-0}" -ge 3 ] && jdk_ver=17

  echo "${CMSG}Installing OpenJDK ${jdk_ver}...${CEND}"
  if [ ${jdk_ver} -ge 17 ]; then
    if [ "${Family}" == "rhel" ]; then
      yum install -y java-17-openjdk java-17-openjdk-devel
    elif [ "${Family}" == "debian" ] || [ "${Family}" == "ubuntu" ]; then
      apt-get update
      apt-get install -y openjdk-17-jdk
    fi
  else
    if [ "${Family}" == "rhel" ]; then
      yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
    elif [ "${Family}" == "debian" ] || [ "${Family}" == "ubuntu" ]; then
      apt-get update
      apt-get install -y openjdk-8-jdk
    fi
  fi

  # Set JAVA_HOME
  JAVA_HOME=""
  if [ ${jdk_ver} -ge 17 ]; then
    for jvm_path in /usr/lib/jvm/java-17-openjdk /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/java-17-openjdk-arm64 /usr/lib/jvm/java-17; do
      if [ -d "${jvm_path}" ] && [ -x "${jvm_path}/bin/java" ]; then
        JAVA_HOME=${jvm_path}
        break
      fi
    done
  else
    for jvm_path in /usr/lib/jvm/java-1.8.0-openjdk /usr/lib/jvm/java-8-openjdk-amd64 /usr/lib/jvm/java-8-openjdk-arm64; do
      if [ -d "${jvm_path}" ] && [ -x "${jvm_path}/bin/java" ]; then
        JAVA_HOME=${jvm_path}
        break
      fi
    done
  fi

  if [ -n "${JAVA_HOME}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    echo "${CSUCCESS}Java installed successfully: ${JAVA_HOME}${CEND}"
    return 0
  else
    echo "${CFAILURE}Java installation failed!${CEND}"
    return 1
  fi
}

Check_Deps() {
  echo "${CMSG}Checking system dependencies...${CEND}"

  local deps_missing=0

  # Check required commands
  for cmd in wget curl mysql tar; do
    if ! command -v ${cmd} > /dev/null 2>&1; then
      echo "${CWARNING}${cmd} not found, installing...${CEND}"
      if [ "${Family}" == "rhel" ]; then
        if [ "${cmd}" == "mysql" ]; then
          yum install -y mysql || yum install -y mariadb
        else
          yum install -y ${cmd}
        fi
      elif [ "${Family}" == "debian" ] || [ "${Family}" == "ubuntu" ]; then
        apt-get update
        if [ "${cmd}" == "mysql" ]; then
          apt-get install -y mysql-client || apt-get install -y mariadb-client
        else
          apt-get install -y ${cmd}
        fi
      fi
    fi
  done

  # Check system limits
  local nofile_limit=$(ulimit -n)
  if [ ${nofile_limit} -lt 65535 ]; then
    echo "${CWARNING}Current open file limit (${nofile_limit}) is too low, setting to 65535...${CEND}"
    if ! grep -q "^${run_user}.*soft.*nofile" /etc/security/limits.conf 2>/dev/null; then
      cat >> /etc/security/limits.conf << EOF
${run_user} soft nofile 65535
${run_user} hard nofile 65535
${run_user} soft nproc 65535
${run_user} hard nproc 65535
EOF
    fi
  fi

  # Check and disable swap (required for Doris BE)
  local swap_total=$(free -m | grep Swap | awk '{print $2}')
  if [ ${swap_total} -gt 0 ]; then
    echo "${CWARNING}Swap is enabled (${swap_total}MB). Disabling swap for Doris...${CEND}"
    swapoff -a
    # Comment out swap entries in fstab to persist across reboot
    sed -i '/\bswap\b/s/^/#/' /etc/fstab
    local swap_after=$(free -m | grep Swap | awk '{print $2}')
    if [ ${swap_after} -gt 0 ]; then
      echo "${CWARNING}Warning: swap could not be fully disabled (${swap_after}MB remaining).${CEND}"
    else
      echo "${CSUCCESS}Swap disabled successfully.${CEND}"
    fi
  fi

  # Check vm.max_map_count
  local max_map_count=$(sysctl -n vm.max_map_count 2>/dev/null)
  if [ -n "${max_map_count}" ] && [ ${max_map_count} -lt 2000000 ]; then
    echo "${CWARNING}vm.max_map_count (${max_map_count}) is too low, setting to 2000000...${CEND}"
    sysctl -w vm.max_map_count=2000000
    if ! grep -q "^vm.max_map_count" /etc/sysctl.conf 2>/dev/null; then
      echo "vm.max_map_count=2000000" >> /etc/sysctl.conf
    else
      sed -i "s|^vm.max_map_count.*|vm.max_map_count=2000000|" /etc/sysctl.conf
    fi
  fi

  # Disable transparent huge pages
  if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag
  fi

  echo "${CSUCCESS}System dependencies check completed.${CEND}"
}

Check_Ports() {
  local node_type=$1
  local ports_in_use=""

  if [ "${node_type}" == "fe" ] || [ "${node_type}" == "all" ]; then
    for port in ${fe_http_port} ${fe_rpc_port} ${fe_query_port} ${fe_edit_log_port}; do
      if ss -tlnp | grep -q ":${port} "; then
        ports_in_use="${ports_in_use} ${port}"
      fi
    done
  fi

  if [ "${node_type}" == "be" ] || [ "${node_type}" == "all" ]; then
    for port in ${be_webserver_port} ${be_heartbeat_service_port} ${be_brpc_port}; do
      if ss -tlnp | grep -q ":${port} "; then
        ports_in_use="${ports_in_use} ${port}"
      fi
    done
  fi

  if [ -n "${ports_in_use}" ]; then
    echo "${CFAILURE}The following ports are already in use:${ports_in_use}${CEND}"
    echo "${CFAILURE}Please check or modify ports in options.conf${CEND}"
    return 1
  fi

  return 0
}

Create_User() {
  if ! id -u ${run_user} > /dev/null 2>&1; then
    echo "${CMSG}Creating user: ${run_user}${CEND}"
    groupadd ${run_group} 2>/dev/null
    useradd -g ${run_group} -s /sbin/nologin -m -d /home/${run_user} ${run_user}
  fi
}

Detect_Network() {
  # Auto-detect priority_networks if not set
  if [ -z "${priority_networks}" ]; then
    local ip_addr=$(hostname -I | awk '{print $1}')
    if [ -n "${ip_addr}" ]; then
      local ip_prefix=$(echo ${ip_addr} | awk -F. '{print $1"."$2"."$3}')
      priority_networks="${ip_prefix}.0/24"
      echo "${CMSG}Auto-detected priority_networks: ${priority_networks}${CEND}"
    fi
  fi
}
