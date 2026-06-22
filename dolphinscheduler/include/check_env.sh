#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# Environment check and setup functions

# Check and install dependencies
Check_Deps() {
  echo "${CMSG}Checking system dependencies...${CEND}"

  local deps_to_install=""

  if [ "${Family}" == "rhel" ]; then
    # Check psmisc (for pstree)
    if ! rpm -q psmisc > /dev/null 2>&1; then
      deps_to_install="${deps_to_install} psmisc"
    fi
    # Check wget
    if ! command -v wget > /dev/null 2>&1; then
      deps_to_install="${deps_to_install} wget"
    fi
    # Check tar
    if ! command -v tar > /dev/null 2>&1; then
      deps_to_install="${deps_to_install} tar"
    fi

    if [ -n "${deps_to_install}" ]; then
      echo "${CMSG}Installing dependencies:${deps_to_install}${CEND}"
      yum install -y ${deps_to_install}
    fi
  else
    # Debian/Ubuntu
    if ! dpkg -l psmisc > /dev/null 2>&1; then
      deps_to_install="${deps_to_install} psmisc"
    fi
    if ! command -v wget > /dev/null 2>&1; then
      deps_to_install="${deps_to_install} wget"
    fi
    if ! command -v tar > /dev/null 2>&1; then
      deps_to_install="${deps_to_install} tar"
    fi

    if [ -n "${deps_to_install}" ]; then
      echo "${CMSG}Installing dependencies:${deps_to_install}${CEND}"
      apt-get update
      apt-get install -y ${deps_to_install}
    fi
  fi

  echo "${CSUCCESS}Dependencies check completed.${CEND}"
}

# Create DolphinScheduler user
Create_User() {
  echo "${CMSG}Creating user ${run_user}...${CEND}"

  if ! id -u ${run_user} > /dev/null 2>&1; then
    groupadd ${run_group} 2>/dev/null
    useradd -g ${run_group} -M -s /bin/bash ${run_user}
    echo "${CSUCCESS}User ${run_user} created.${CEND}"
  else
    echo "${CMSG}User ${run_user} already exists.${CEND}"
  fi
}

# Configure sudo privileges for DolphinScheduler user
Configure_Sudo() {
  echo "${CMSG}Configuring sudo privileges for ${run_user}...${CEND}"

  # Add sudo privileges
  if ! grep -q "^${run_user}" /etc/sudoers; then
    echo "${run_user} ALL=(ALL) NOPASSWD: NOPASSWD: ALL" >> /etc/sudoers
  fi

  # Comment out requiretty if present
  if grep -q "^Defaults.*requiretty" /etc/sudoers; then
    sed -i 's/^Defaults.*requiretty/#&/' /etc/sudoers
  fi

  echo "${CSUCCESS}Sudo privileges configured.${CEND}"
}

# Configure SSH key-based authentication
Configure_SSH() {
  local target_user=${1:-${run_user}}
  local target_home=$(eval echo ~${target_user})

  echo "${CMSG}Configuring SSH for ${target_user}...${CEND}"

  # Create .ssh directory with correct ownership first
  mkdir -p ${target_home}/.ssh
  chown ${target_user}:${run_group} ${target_home}/.ssh
  chmod 700 ${target_home}/.ssh

  # Generate SSH key if not exists
  if [ ! -f "${target_home}/.ssh/id_rsa" ]; then
    # Run ssh-keygen as target user with proper environment
    su - ${target_user} -c "ssh-keygen -t rsa -P '' -f ${target_home}/.ssh/id_rsa -q" 2>/dev/null
    if [ $? -ne 0 ]; then
      # Fallback: generate as root and fix ownership
      ssh-keygen -t rsa -P '' -f ${target_home}/.ssh/id_rsa -q 2>/dev/null
      chown ${target_user}:${run_group} ${target_home}/.ssh/id_rsa ${target_home}/.ssh/id_rsa.pub 2>/dev/null
    fi
  fi

  # Add to authorized_keys
  if [ -f "${target_home}/.ssh/id_rsa.pub" ]; then
    cat ${target_home}/.ssh/id_rsa.pub >> ${target_home}/.ssh/authorized_keys
    chmod 600 ${target_home}/.ssh/authorized_keys
    chown -R ${target_user}:${run_group} ${target_home}/.ssh
  fi

  # Ensure correct permissions on all files
  chmod 600 ${target_home}/.ssh/id_rsa 2>/dev/null
  chmod 644 ${target_home}/.ssh/id_rsa.pub 2>/dev/null

  echo "${CSUCCESS}SSH configured for ${target_user}.${CEND}"
}

# Check Java environment
Check_Java() {
  echo "${CMSG}Checking Java environment...${CEND}"

  # Check JAVA_HOME from options.conf
  if [ -n "${JAVA_HOME}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    local java_ver=$(${JAVA_HOME}/bin/java -version 2>&1 | head -1 | awk -F'"' '{print $2}')
    echo "${CSUCCESS}Found Java: ${java_ver} (JAVA_HOME=${JAVA_HOME})${CEND}"
    return 0
  fi

  # Try to detect Java
  if command -v java > /dev/null 2>&1; then
    local java_path=$(which java)
    local java_real=$(readlink -f ${java_path})
    JAVA_HOME=${java_real%/bin/java}

    local java_ver=$(java -version 2>&1 | head -1 | awk -F'"' '{print $2}')
    echo "${CSUCCESS}Found Java: ${java_ver} (JAVA_HOME=${JAVA_HOME})${CEND}"
    return 0
  fi

  echo "${CWARNING}Java not found!${CEND}"
  return 1
}

# Install OpenJDK 8
Install_Java() {
  echo "${CMSG}Installing OpenJDK 8...${CEND}"

  if [ "${Family}" == "rhel" ]; then
    yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
    JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
  else
    apt-get update
    apt-get install -y openjdk-8-jdk
    JAVA_HOME=/usr/lib/jvm/java-8-openjdk-${SYS_ARCH}
    if [ ! -d "${JAVA_HOME}" ]; then
      JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    fi
  fi

  # Set JAVA_HOME in profile
  if [ -d "${JAVA_HOME}" ]; then
    cat > /etc/profile.d/java.sh << EOF
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    source /etc/profile.d/java.sh
    echo "${CSUCCESS}OpenJDK 8 installed. JAVA_HOME=${JAVA_HOME}${CEND}"
  else
    echo "${CFAILURE}Failed to install Java!${CEND}"
    return 1
  fi
}

# Check database connection
Check_Database() {
  local db_type=${db_type:-mysql}
  local db_host=${db_host:-localhost}
  local db_port=${db_port:-3306}
  local db_user=${db_user:-root}
  local db_password=${db_password}

  echo "${CMSG}Checking ${db_type} database connection...${CEND}"

  if [ "${db_type}" == "mysql" ]; then
    if command -v mysql > /dev/null 2>&1; then
      if mysql -h${db_host} -P${db_port} -u${db_user} -p"${db_password}" -e "SELECT 1" > /dev/null 2>&1; then
        echo "${CSUCCESS}MySQL connection successful.${CEND}"
        # Check if database exists
        if mysql -h${db_host} -P${db_port} -u${db_user} -p"${db_password}" -e "USE ${db_name}" > /dev/null 2>&1; then
          echo "${CSUCCESS}Database '${db_name}' exists.${CEND}"
        else
          echo "${CWARNING}Database '${db_name}' does not exist.${CEND}"
          return 1
        fi
        return 0
      else
        echo "${CWARNING}MySQL connection failed!${CEND}"
        return 1
      fi
    else
      echo "${CWARNING}MySQL client not found. Skipping connection check.${CEND}"
      return 0
    fi
  elif [ "${db_type}" == "postgresql" ]; then
    if command -v psql > /dev/null 2>&1; then
      if PGPASSWORD="${db_password}" psql -h ${db_host} -p ${db_port} -U ${db_user} -c "SELECT 1" > /dev/null 2>&1; then
        echo "${CSUCCESS}PostgreSQL connection successful.${CEND}"
        # Check if database exists
        if PGPASSWORD="${db_password}" psql -h ${db_host} -p ${db_port} -U ${db_user} -d ${db_name} -c "SELECT 1" > /dev/null 2>&1; then
          echo "${CSUCCESS}Database '${db_name}' exists.${CEND}"
        else
          echo "${CWARNING}Database '${db_name}' does not exist.${CEND}"
          return 1
        fi
        return 0
      else
        echo "${CWARNING}PostgreSQL connection failed!${CEND}"
        return 1
      fi
    else
      echo "${CWARNING}PostgreSQL client not found. Skipping connection check.${CEND}"
      return 0
    fi
  fi
}

# Create database if not exists
Create_Database() {
  local db_type=${db_type:-mysql}
  local db_host=${db_host:-localhost}
  local db_port=${db_port:-3306}
  local db_user=${db_user:-root}
  local db_password=${db_password}
  local db_name=${db_name:-dolphinscheduler}

  echo "${CMSG}Creating database '${db_name}'...${CEND}"

  if [ "${db_type}" == "mysql" ]; then
    if command -v mysql > /dev/null 2>&1; then
      mysql -h${db_host} -P${db_port} -u${db_user} -p"${db_password}" -e "CREATE DATABASE IF NOT EXISTS ${db_name} DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_general_ci;" 2>/dev/null
      if [ $? -eq 0 ]; then
        echo "${CSUCCESS}Database '${db_name}' created successfully.${CEND}"
        return 0
      else
        echo "${CFAILURE}Failed to create database '${db_name}'!${CEND}"
        return 1
      fi
    else
      echo "${CFAILURE}MySQL client not found!${CEND}"
      return 1
    fi
  elif [ "${db_type}" == "postgresql" ]; then
    if command -v psql > /dev/null 2>&1; then
      PGPASSWORD="${db_password}" psql -h ${db_host} -p ${db_port} -U ${db_user} -c "CREATE DATABASE ${db_name} ENCODING 'UTF8';" 2>/dev/null
      if [ $? -eq 0 ]; then
        echo "${CSUCCESS}Database '${db_name}' created successfully.${CEND}"
        return 0
      else
        echo "${CFAILURE}Failed to create database '${db_name}'!${CEND}"
        return 1
      fi
    else
      echo "${CFAILURE}PostgreSQL client not found!${CEND}"
      return 1
    fi
  fi
}

# Check ZooKeeper connection
Check_ZooKeeper() {
  local zk_hosts=${zk_hosts:-localhost:2181}
  local zk_host=${zk_hosts%%:*}
  local zk_port=${zk_hosts##*:}

  echo "${CMSG}Checking ZooKeeper connection (${zk_hosts})...${CEND}"

  # Try to connect using nc or telnet
  if command -v nc > /dev/null 2>&1; then
    if echo "ruok" | nc -w 2 ${zk_host} ${zk_port} 2>/dev/null | grep -q "imok"; then
      echo "${CSUCCESS}ZooKeeper connection successful.${CEND}"
      return 0
    fi
  fi

  # Try using bash /dev/tcp
  if (echo > /dev/tcp/${zk_host}/${zk_port}) 2>/dev/null; then
    echo "${CSUCCESS}ZooKeeper port ${zk_port} is reachable.${CEND}"
    return 0
  fi

  echo "${CWARNING}ZooKeeper connection failed or not reachable!${CEND}"
  return 1
}

# Check port availability
Check_Port() {
  local port=$1
  local service_name=${2:-"Service"}

  if ss -tlnp | grep -q ":${port} "; then
    echo "${CWARNING}Port ${port} (${service_name}) is already in use!${CEND}"
    return 1
  fi
  return 0
}

# Check all required ports
Check_Ports() {
  local mode=${1:-all}
  local has_conflict=0

  echo "${CMSG}Checking port availability...${CEND}"

  case "${mode}" in
    standalone)
      Check_Port ${web_port} "Web UI" || has_conflict=1
      ;;
    pseudo-cluster|cluster)
      Check_Port ${api_port} "API Server" || has_conflict=1
      Check_Port ${master_port} "Master Server" || has_conflict=1
      Check_Port ${worker_port} "Worker Server" || has_conflict=1
      Check_Port ${alert_port} "Alert Server" || has_conflict=1
      ;;
    all)
      Check_Port ${web_port} "Web UI" || has_conflict=1
      Check_Port ${api_port} "API Server" || has_conflict=1
      Check_Port ${master_port} "Master Server" || has_conflict=1
      Check_Port ${worker_port} "Worker Server" || has_conflict=1
      Check_Port ${alert_port} "Alert Server" || has_conflict=1
      ;;
  esac

  if [ ${has_conflict} -eq 1 ]; then
    echo "${CFAILURE}Port conflict detected! Please check and modify options.conf.${CEND}"
    return 1
  fi

  echo "${CSUCCESS}All ports are available.${CEND}"
  return 0
}

# Detect local IP
Detect_Network() {
  local_ip=$(hostname -I | awk '{print $1}')
  if [ -z "${local_ip}" ]; then
    local_ip="127.0.0.1"
  fi
  echo "${CMSG}Detected local IP: ${local_ip}${CEND}"
}

# Show cluster status
Show_Cluster_Status() {
  echo ""
  echo "${CMSG}========== DolphinScheduler Cluster Status ==========${CEND}"
  echo ""

  # Check standalone-server
  if systemctl is-active --quiet dolphinscheduler-standalone 2>/dev/null; then
    echo "${CSUCCESS}[RUNNING]${CEND} Standalone Server"
    echo "  Web UI: http://${local_ip:-localhost}:${web_port}/dolphinscheduler/ui"
  elif [ -f "/lib/systemd/system/dolphinscheduler-standalone.service" ]; then
    echo "${CFAILURE}[STOPPED]${CEND} Standalone Server"
  fi

  # Check master-server
  if systemctl is-active --quiet dolphinscheduler-master 2>/dev/null; then
    echo "${CSUCCESS}[RUNNING]${CEND} Master Server"
  elif [ -f "/lib/systemd/system/dolphinscheduler-master.service" ]; then
    echo "${CFAILURE}[STOPPED]${CEND} Master Server"
  fi

  # Check worker-server
  if systemctl is-active --quiet dolphinscheduler-worker 2>/dev/null; then
    echo "${CSUCCESS}[RUNNING]${CEND} Worker Server"
  elif [ -f "/lib/systemd/system/dolphinscheduler-worker.service" ]; then
    echo "${CFAILURE}[STOPPED]${CEND} Worker Server"
  fi

  # Check api-server
  if systemctl is-active --quiet dolphinscheduler-api 2>/dev/null; then
    echo "${CSUCCESS}[RUNNING]${CEND} API Server"
  elif [ -f "/lib/systemd/system/dolphinscheduler-api.service" ]; then
    echo "${CFAILURE}[STOPPED]${CEND} API Server"
  fi

  # Check alert-server
  if systemctl is-active --quiet dolphinscheduler-alert 2>/dev/null; then
    echo "${CSUCCESS}[RUNNING]${CEND} Alert Server"
  elif [ -f "/lib/systemd/system/dolphinscheduler-alert.service" ]; then
    echo "${CFAILURE}[STOPPED]${CEND} Alert Server"
  fi

  echo ""
}
