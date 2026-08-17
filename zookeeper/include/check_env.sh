#!/bin/bash
# 环境检测
# 项目: oneinstack/zookeeper

# 检测 JDK
Check_JDK() {
  local required_ver=${1:-8}
  
  # 检测 JAVA_HOME
  if [ -z "${JAVA_HOME}" ] || [ ! -x "${JAVA_HOME}/bin/java" ]; then
    # 尝试自动检测
    if command -v java &> /dev/null; then
      local java_bin=$(readlink -f $(which java))
      # java_bin 可能是 /usr/lib/jvm/java-17-openjdk-amd64/bin/java
      JAVA_HOME=$(dirname $(dirname "${java_bin}"))
      export JAVA_HOME
    fi
  fi
  
  if [ ! -x "${JAVA_HOME}/bin/java" ]; then
    echo "${CFAILURE}[ERROR] JDK not found!${CEND}"
    echo "Please install JDK and set JAVA_HOME environment variable."
    echo "For ZooKeeper 3.9+, JDK 11+ is required."
    echo "For ZooKeeper 3.7/3.8, JDK 8+ is required."
    return 1
  fi
  
  # 获取 Java 版本
  local java_ver_full=$(${JAVA_HOME}/bin/java -version 2>&1 | head -1 | awk -F'"' '{print $2}')
  local java_ver_major
  
  # 处理版本号格式 (1.8.x 或 11.x.x)
  if [[ "${java_ver_full}" == 1.* ]]; then
    java_ver_major=$(echo "${java_ver_full}" | awk -F'.' '{print $2}')
  else
    java_ver_major=$(echo "${java_ver_full}" | awk -F'.' '{print $1}')
  fi
  
  echo "${CMSG}JDK Detection:${CEND}"
  echo "  JAVA_HOME: ${JAVA_HOME}"
  echo "  Java Version: ${java_ver_full} (major: ${java_ver_major})"
  
  # 版本检查
  if [ "${java_ver_major}" -lt "${required_ver}" ]; then
    echo "${CFAILURE}[ERROR] JDK ${required_ver}+ is required, current: ${java_ver_major}${CEND}"
    return 1
  fi
  
  echo "${CSUCCESS}[OK] JDK version check passed${CEND}"
  return 0
}

# 检测 ZooKeeper 版本对应的 JDK 要求
Check_JDK_For_ZK() {
  local zk_ver=$1
  local zk_major=$(echo "${zk_ver}" | awk -F'.' '{print $1}')
  local zk_minor=$(echo "${zk_ver}" | awk -F'.' '{print $2}')
  
  # ZooKeeper 3.9+ 需要 JDK 11+
  if [ "${zk_major}" -ge 3 ] && [ "${zk_minor}" -ge 9 ]; then
    Check_JDK 11
  else
    Check_JDK 8
  fi
  return $?
}

# 检测 netcat
Check_Netcat() {
  if command -v nc &> /dev/null; then
    echo "${CSUCCESS}[OK] netcat is installed${CEND}"
    return 0
  else
    echo "${CWARNING}[WARNING] netcat (nc) is not installed${CEND}"
    echo "Installing netcat for health check..."
    
    case "${Family}" in
      rhel)
        ${PM} -y install nc nmap-ncat 2>/dev/null || ${PM} -y install nmap-ncat
        ;;
      debian|ubuntu)
        ${PM} -y install netcat-openbsd
        ;;
    esac
    
    if command -v nc &> /dev/null; then
      echo "${CSUCCESS}[OK] netcat installed successfully${CEND}"
      return 0
    else
      echo "${CFAILURE}[ERROR] Failed to install netcat${CEND}"
      return 1
    fi
  fi
}

# 检测所有依赖
Check_Dependencies() {
  local zk_ver=${1:-${zk_ver}}
  
  echo "${CMSG}=== Checking Dependencies ===${CEND}"
  
  Check_JDK_For_ZK "${zk_ver}" || return 1
  Check_Netcat || return 1
  
  echo "${CSUCCESS}=== All dependencies satisfied ===${CEND}"
  return 0
}
