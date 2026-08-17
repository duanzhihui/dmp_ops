#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Java Environment Detection
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

Check_Java() {
  # Check if JAVA_HOME is set
  if [ -n "${JAVA_HOME}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    echo "${CMSG}JAVA_HOME is set to: ${JAVA_HOME}${CEND}"
    return 0
  fi

  # Try to find java in common locations
  local java_paths=(
    "/usr/lib/jvm/java-11-openjdk"
    "/usr/lib/jvm/java-11-openjdk-amd64"
    "/usr/lib/jvm/java-11-openjdk-arm64"
    "/usr/lib/jvm/java-8-openjdk"
    "/usr/lib/jvm/java-8-openjdk-amd64"
    "/usr/lib/jvm/java-8-openjdk-arm64"
    "/usr/lib/jvm/temurin-11-jdk-amd64"
    "/usr/lib/jvm/temurin-11-jdk-arm64"
    "/usr/java/latest"
    "/opt/java"
  )

  for path in "${java_paths[@]}"; do
    if [ -x "${path}/bin/java" ]; then
      export JAVA_HOME="${path}"
      echo "${CMSG}Found JAVA_HOME: ${JAVA_HOME}${CEND}"
      return 0
    fi
  done

  # Try to find java in PATH
  if command -v java > /dev/null 2>&1; then
    local java_bin=$(which java)
    local java_real=$(readlink -f "${java_bin}")
    export JAVA_HOME=$(dirname $(dirname "${java_real}"))
    echo "${CMSG}Found JAVA_HOME from PATH: ${JAVA_HOME}${CEND}"
    return 0
  fi

  echo "${CWARNING}Java not found!${CEND}"
  return 1
}

Verify_Java_Version() {
  if [ -z "${JAVA_HOME}" ] || [ ! -x "${JAVA_HOME}/bin/java" ]; then
    echo "${CFAILURE}JAVA_HOME is not set or invalid!${CEND}"
    return 1
  fi

  local java_version=$(${JAVA_HOME}/bin/java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
  local major_version=$(echo "${java_version}" | awk -F. '{print $1}')
  
  # Handle Java 1.x version format (e.g., 1.8.0)
  if [ "${major_version}" == "1" ]; then
    major_version=$(echo "${java_version}" | awk -F. '{print $2}')
  fi

  echo "${CMSG}Java version: ${java_version} (major: ${major_version})${CEND}"

  # SeaTunnel requires Java 8+
  if [ "${major_version}" -ge 8 ]; then
    echo "${CSUCCESS}Java version ${major_version} is supported!${CEND}"
    return 0
  else
    echo "${CWARNING}SeaTunnel requires Java 8+, current version: ${major_version}${CEND}"
    return 1
  fi
}

Install_Java() {
  local java_ver=${1:-11}
  
  echo "${CMSG}Installing OpenJDK ${java_ver}...${CEND}"
  
  if [ "${Family}" == 'rhel' ]; then
    yum -y install java-${java_ver}-openjdk-devel
    JAVA_HOME=/usr/lib/jvm/java-${java_ver}-openjdk
  elif [ "${Family}" == 'debian' ]; then
    apt-get update
    apt-get --no-install-recommends -y install openjdk-${java_ver}-jdk
    JAVA_HOME=/usr/lib/jvm/java-${java_ver}-openjdk-${SYS_ARCH}
  elif [ "${Family}" == 'ubuntu' ]; then
    apt-get update
    apt-get --no-install-recommends -y install openjdk-${java_ver}-jdk
    JAVA_HOME=/usr/lib/jvm/java-${java_ver}-openjdk-${SYS_ARCH}
  fi

  if [ -e "${JAVA_HOME}/bin/java" ]; then
    cat > /etc/profile.d/java.sh << EOF
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    . /etc/profile.d/java.sh
    echo "${CSUCCESS}OpenJDK ${java_ver} installed successfully!${CEND}"
    return 0
  else
    echo "${CFAILURE}OpenJDK ${java_ver} install failed!${CEND}"
    return 1
  fi
}

Ensure_Java() {
  # Check if Java is available
  if ! Check_Java; then
    echo "${CMSG}Java not found, installing OpenJDK 11...${CEND}"
    Install_Java 11
  fi

  # Verify Java version
  if ! Verify_Java_Version; then
    echo "${CWARNING}Current Java version is not supported.${CEND}"
    read -e -p "Do you want to install OpenJDK 11? [y/n]: " install_java
    if [[ "${install_java}" =~ ^[Yy]$ ]]; then
      Install_Java 11
    else
      echo "${CFAILURE}SeaTunnel requires Java 8+. Please install manually.${CEND}"
      return 1
    fi
  fi

  # Export JAVA_HOME to options.conf
  if [ -n "${JAVA_HOME}" ]; then
    sed -i "s@^java_home=.*@java_home=${JAVA_HOME}@" ${seatunnel_dir}/options.conf 2>/dev/null
  fi

  return 0
}
