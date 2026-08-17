#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# FoundationDB (FDB) deployment for 存算分离 mode
#
# FDB is required for Meta Service in separating storage-compute architecture
# Default FDB version: 7.1.x series
# Reference: https://doris.apache.org/zh-CN/docs/4.x/install/deploy-manually/separating-storage-compute-deploy-manually

Install_FDB() {
  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Installing FoundationDB ${fdb_ver}${CEND}"
  echo "${CMSG}============================================${CEND}"

  # Check if FDB already installed
  if command -v fdbcli > /dev/null 2>&1; then
    local installed_ver=$(fdbcli --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
    echo "${CWARNING}FoundationDB ${installed_ver} already installed.${CEND}"
    # Verify version is 7.1.x
    if [[ ! "${installed_ver}" =~ ^7\.1\. ]]; then
      echo "${CFAILURE}WARNING: Doris requires FDB 7.1.x, but ${installed_ver} is installed!${CEND}"
      echo "${CFAILURE}Meta Service may fail to start with incompatible FDB version.${CEND}"
    fi
    return 0
  fi

  # Create directories
  mkdir -p ${fdb_home}

  # Install FDB based on OS
  if [ "${Family}" == "rhel" ]; then
    echo "${CMSG}Installing FDB via RPM...${CEND}"
    local fdb_base_url="https://github.com/apple/foundationdb/releases/download/${fdb_ver}"
    wget -q "${fdb_base_url}/foundationdb-clients-${fdb_ver}-1.el7.x86_64.rpm" -O /tmp/fdb-clients.rpm
    wget -q "${fdb_base_url}/foundationdb-server-${fdb_ver}-1.el7.x86_64.rpm" -O /tmp/fdb-server.rpm
    rpm -ivh /tmp/fdb-clients.rpm /tmp/fdb-server.rpm
    rm -f /tmp/fdb-clients.rpm /tmp/fdb-server.rpm
  elif [ "${Family}" == "debian" ] || [ "${Family}" == "ubuntu" ]; then
    echo "${CMSG}Installing FDB via DEB...${CEND}"
    local fdb_base_url="https://github.com/apple/foundationdb/releases/download/${fdb_ver}"
    wget -q "${fdb_base_url}/foundationdb-clients_${fdb_ver}-1_amd64.deb" -O /tmp/fdb-clients.deb
    wget -q "${fdb_base_url}/foundationdb-server_${fdb_ver}-1_amd64.deb" -O /tmp/fdb-server.deb
    dpkg -i /tmp/fdb-clients.deb /tmp/fdb-server.deb
    rm -f /tmp/fdb-clients.deb /tmp/fdb-server.deb
  fi

  if ! command -v fdbcli > /dev/null 2>&1; then
    echo "${CFAILURE}FDB installation failed! Please install manually.${CEND}"
    echo "${CMSG}Download from: https://github.com/apple/foundationdb/releases/tag/${fdb_ver}${CEND}"
    return 1
  fi

  echo "${CSUCCESS}FoundationDB ${fdb_ver} installed successfully!${CEND}"
}

Configure_FDB_Cluster() {
  echo "${CMSG}Configuring FDB cluster...${CEND}"

  IFS=',' read -ra FDB_ARRAY <<< "${fdb_nodes}"
  if [ ${#FDB_ARRAY[@]} -eq 0 ]; then
    echo "${CFAILURE}No FDB nodes configured! Please set fdb_nodes in options.conf${CEND}"
    return 1
  fi

  # Generate cluster ID if not set
  if [ -z "${fdb_cluster_id}" ]; then
    fdb_cluster_id=$(mktemp -u XXXXXXXX)
  fi

  # Create FDB data directories
  IFS=',' read -ra FDB_DATA_ARRAY <<< "${fdb_data_dirs}"
  for data_dir in "${FDB_DATA_ARRAY[@]}"; do
    mkdir -p ${data_dir}
  done

  # Create fdb.cluster file
  local coordinator_ip=${FDB_ARRAY[0]}
  local cluster_string="${fdb_cluster_desc}:${fdb_cluster_id}@${coordinator_ip}:4500"
  mkdir -p ${fdb_home}/conf
  echo "${cluster_string}" > ${fdb_home}/conf/fdb.cluster
  echo "${cluster_string}" > /etc/foundationdb/fdb.cluster 2>/dev/null

  fdb_cluster="${cluster_string}"

  echo "${CSUCCESS}FDB cluster configured: ${cluster_string}${CEND}"
}

Start_FDB() {
  echo "${CMSG}Starting FoundationDB...${CEND}"
  systemctl start foundationdb 2>/dev/null || service foundationdb start 2>/dev/null

  sleep 3
  if fdbcli --exec status 2>/dev/null | grep -q "Healthy"; then
    echo "${CSUCCESS}FDB cluster is healthy!${CEND}"
  else
    echo "${CWARNING}FDB cluster status check - may need manual verification${CEND}"
    fdbcli --exec status 2>/dev/null
  fi
}

Stop_FDB() {
  echo "${CMSG}Stopping FoundationDB...${CEND}"
  systemctl stop foundationdb 2>/dev/null || service foundationdb stop 2>/dev/null
  echo "${CSUCCESS}FDB stopped.${CEND}"
}

Check_FDB_Status() {
  if command -v fdbcli > /dev/null 2>&1; then
    echo "${CMSG}FDB cluster status:${CEND}"
    fdbcli --exec status 2>/dev/null
    return $?
  else
    echo "${CWARNING}fdbcli not found. FDB may not be installed.${CEND}"
    return 1
  fi
}

Uninstall_FDB() {
  echo "${CMSG}Uninstalling FoundationDB...${CEND}"

  Stop_FDB

  if [ "${Family}" == "rhel" ]; then
    rpm -e foundationdb-server foundationdb-clients 2>/dev/null
  elif [ "${Family}" == "debian" ] || [ "${Family}" == "ubuntu" ]; then
    dpkg -r foundationdb-server foundationdb-clients 2>/dev/null
  fi

  # Backup FDB data
  if [ -d "${fdb_home}" ]; then
    echo "${CWARNING}Backing up FDB data to ${fdb_home}.bak.$(date +%Y%m%d%H%M%S)${CEND}"
    mv ${fdb_home} ${fdb_home}.bak.$(date +%Y%m%d%H%M%S)
  fi

  echo "${CSUCCESS}FDB uninstalled successfully!${CEND}"
}

# Deploy FDB using Doris-provided scripts (from the tools/ dir in package)
Deploy_FDB_With_Scripts() {
  local doris_ver=$1

  echo "${CMSG}Deploying FDB using Doris-provided scripts...${CEND}"

  # Extract tools from package
  local doris_pkg=$(Get_Doris_Pkg "${doris_ver}")
  if [ ! -f "${doris_dir}/src/${doris_pkg}" ]; then
    echo "${CFAILURE}Package ${doris_pkg} not found!${CEND}"
    return 1
  fi

  local tmp_dir=$(mktemp -d)
  tar xzf ${doris_dir}/src/${doris_pkg} -C ${tmp_dir} --strip-components=1

  if [ -d "${tmp_dir}/tools/fdb" ]; then
    cp -rf ${tmp_dir}/tools/fdb ${doris_dir}/tools/
    echo "${CSUCCESS}FDB deployment scripts extracted to ${doris_dir}/tools/fdb/${CEND}"

    # Configure fdb_vars.sh
    if [ -f "${doris_dir}/tools/fdb/fdb_vars.sh" ]; then
      sed -i "s|^DATA_DIRS=.*|DATA_DIRS=${fdb_data_dirs}|" ${doris_dir}/tools/fdb/fdb_vars.sh
      sed -i "s|^FDB_CLUSTER_IPS=.*|FDB_CLUSTER_IPS=${fdb_nodes}|" ${doris_dir}/tools/fdb/fdb_vars.sh
      sed -i "s|^FDB_HOME=.*|FDB_HOME=${fdb_home}|" ${doris_dir}/tools/fdb/fdb_vars.sh
      sed -i "s|^FDB_CLUSTER_ID=.*|FDB_CLUSTER_ID=${fdb_cluster_id}|" ${doris_dir}/tools/fdb/fdb_vars.sh
      sed -i "s|^FDB_CLUSTER_DESC=.*|FDB_CLUSTER_DESC=${fdb_cluster_desc}|" ${doris_dir}/tools/fdb/fdb_vars.sh

      echo "${CMSG}Deploying FDB cluster...${CEND}"
      cd ${doris_dir}/tools/fdb && bash fdb_ctl.sh deploy
      echo "${CMSG}Starting FDB...${CEND}"
      cd ${doris_dir}/tools/fdb && bash fdb_ctl.sh start

      # Read FDB connection string
      if [ -f "${fdb_home}/conf/fdb.cluster" ]; then
        fdb_cluster=$(tail -1 ${fdb_home}/conf/fdb.cluster)
        echo "${CSUCCESS}FDB cluster connection: ${fdb_cluster}${CEND}"
      fi
    fi
  else
    echo "${CWARNING}FDB tools not found in package. Using system FDB installation.${CEND}"
    Install_FDB
    Configure_FDB_Cluster
    Start_FDB
  fi

  rm -rf ${tmp_dir}
}
