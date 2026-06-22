#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Install/Uninstall Module
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

Install_SeaTunnel() {
  pushd ${seatunnel_dir}/src > /dev/null

  # 1. Check if already installed (idempotent)
  if [ -e "${seatunnel_install_dir}/bin/seatunnel.sh" ]; then
    echo "${CWARNING}SeaTunnel is already installed at ${seatunnel_install_dir}!${CEND}"
    popd > /dev/null
    return 0
  fi

  # 2. Check Java environment
  echo "${CMSG}Checking Java environment...${CEND}"
  if ! Ensure_Java; then
    echo "${CFAILURE}Java environment check failed!${CEND}"
    popd > /dev/null
    kill -9 $$; exit 1;
  fi

  # 3. Download SeaTunnel
  echo "${CMSG}Downloading SeaTunnel ${seatunnel_ver}...${CEND}"
  Download_SeaTunnel ${seatunnel_ver}

  # 4. Extract to install directory
  echo "${CMSG}Extracting SeaTunnel...${CEND}"
  local tarball="apache-seatunnel-${seatunnel_ver}-bin.tar.gz"
  if [ ! -f "${tarball}" ]; then
    echo "${CFAILURE}SeaTunnel tarball not found: ${tarball}${CEND}"
    popd > /dev/null
    kill -9 $$; exit 1;
  fi

  mkdir -p $(dirname ${seatunnel_install_dir})
  tar xzf ${tarball} -C $(dirname ${seatunnel_install_dir})
  mv $(dirname ${seatunnel_install_dir})/apache-seatunnel-${seatunnel_ver} ${seatunnel_install_dir}

  if [ ! -d "${seatunnel_install_dir}" ]; then
    echo "${CFAILURE}Failed to extract SeaTunnel!${CEND}"
    popd > /dev/null
    kill -9 $$; exit 1;
  fi

  # 5. Install connector plugins
  echo "${CMSG}Installing connector plugins...${CEND}"
  if [ -n "${connectors}" ]; then
    # Generate plugin_config first
    Generate_Plugin_Config ${seatunnel_install_dir}/config
    
    # Run install-plugin.sh
    pushd ${seatunnel_install_dir} > /dev/null
    sh bin/install-plugin.sh ${seatunnel_ver}
    popd > /dev/null
  fi

  # 6. Create system user
  echo "${CMSG}Creating system user ${run_user}...${CEND}"
  id -u ${run_user} >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    useradd -M -s /sbin/nologin ${run_user}
  fi

  # 7. Generate configuration files
  echo "${CMSG}Generating configuration files...${CEND}"
  Generate_All_Configs ${seatunnel_install_dir}/config

  # 8. Create directories and set permissions
  echo "${CMSG}Setting up directories and permissions...${CEND}"
  mkdir -p ${seatunnel_install_dir}/logs
  mkdir -p ${seatunnel_data_dir}
  mkdir -p ${seatunnel_checkpoint_dir}
  mkdir -p /tmp/seatunnel/dump
  mkdir -p /var/run/seatunnel

  chown -R ${run_user}:${run_group} ${seatunnel_install_dir}
  chown -R ${run_user}:${run_group} ${seatunnel_data_dir}
  chown -R ${run_user}:${run_group} ${seatunnel_checkpoint_dir}
  chown -R ${run_user}:${run_group} /tmp/seatunnel
  chown -R ${run_user}:${run_group} /var/run/seatunnel

  # 9. Configure environment variables
  echo "${CMSG}Configuring environment variables...${CEND}"
  cat > /etc/profile.d/seatunnel.sh << EOF
export SEATUNNEL_HOME=${seatunnel_install_dir}
export PATH=\$SEATUNNEL_HOME/bin:\$PATH
EOF
  . /etc/profile.d/seatunnel.sh

  # 10. Register systemd service based on deploy mode
  echo "${CMSG}Registering systemd service (${deploy_mode} mode)...${CEND}"
  
  if [ "${deploy_mode}" == "hybrid" ]; then
    /bin/cp ${seatunnel_dir}/init.d/seatunnel.service /lib/systemd/system/
    sed -i "s@/opt/seatunnel@${seatunnel_install_dir}@g" /lib/systemd/system/seatunnel.service
    sed -i "s@JAVA_HOME=.*@JAVA_HOME=${JAVA_HOME}@g" /lib/systemd/system/seatunnel.service
    systemctl daemon-reload
    systemctl enable seatunnel
  elif [ "${deploy_mode}" == "separated" ]; then
    if [ "${node_role}" == "master" ]; then
      /bin/cp ${seatunnel_dir}/init.d/seatunnel-master.service /lib/systemd/system/
      sed -i "s@/opt/seatunnel@${seatunnel_install_dir}@g" /lib/systemd/system/seatunnel-master.service
      sed -i "s@JAVA_HOME=.*@JAVA_HOME=${JAVA_HOME}@g" /lib/systemd/system/seatunnel-master.service
      systemctl daemon-reload
      systemctl enable seatunnel-master
    elif [ "${node_role}" == "worker" ]; then
      /bin/cp ${seatunnel_dir}/init.d/seatunnel-worker.service /lib/systemd/system/
      sed -i "s@/opt/seatunnel@${seatunnel_install_dir}@g" /lib/systemd/system/seatunnel-worker.service
      sed -i "s@JAVA_HOME=.*@JAVA_HOME=${JAVA_HOME}@g" /lib/systemd/system/seatunnel-worker.service
      systemctl daemon-reload
      systemctl enable seatunnel-worker
    fi
  fi

  # 11. Verify installation
  if [ -f "${seatunnel_install_dir}/bin/seatunnel.sh" ]; then
    echo "${CSUCCESS}SeaTunnel ${seatunnel_ver} installed successfully!${CEND}"
    
    # Update options.conf
    sed -i "s@^seatunnel_installed=.*@seatunnel_installed=true@" ${seatunnel_dir}/options.conf
    
    # Clean up
    rm -f ${tarball}
    
    # Print summary
    echo
    echo "=========================================="
    echo "${CMSG}SeaTunnel Installation Summary${CEND}"
    echo "=========================================="
    echo "Version:       ${seatunnel_ver}"
    echo "Install Dir:   ${seatunnel_install_dir}"
    echo "Data Dir:      ${seatunnel_data_dir}"
    echo "Log Dir:       ${seatunnel_install_dir}/logs"
    echo "Deploy Mode:   ${deploy_mode}"
    echo "Cluster Name:  ${cluster_name}"
    echo "Port:          ${hazelcast_port}"
    echo "Run User:      ${run_user}"
    echo "JAVA_HOME:     ${JAVA_HOME}"
    echo "=========================================="
    echo
    
    if [ "${deploy_mode}" == "local" ]; then
      echo "${CMSG}To run a job in local mode:${CEND}"
      echo "  ${seatunnel_install_dir}/bin/seatunnel.sh --config <job.conf> -e local"
    elif [ "${deploy_mode}" == "hybrid" ]; then
      echo "${CMSG}To start SeaTunnel Engine:${CEND}"
      echo "  systemctl start seatunnel"
      echo
      echo "${CMSG}To submit a job:${CEND}"
      echo "  ${seatunnel_install_dir}/bin/seatunnel.sh --config <job.conf>"
    elif [ "${deploy_mode}" == "separated" ]; then
      if [ "${node_role}" == "master" ]; then
        echo "${CMSG}To start SeaTunnel Master:${CEND}"
        echo "  systemctl start seatunnel-master"
      else
        echo "${CMSG}To start SeaTunnel Worker:${CEND}"
        echo "  systemctl start seatunnel-worker"
      fi
    fi
    echo
  else
    echo "${CFAILURE}SeaTunnel installation failed!${CEND}"
    rm -rf ${seatunnel_install_dir}
    popd > /dev/null
    kill -9 $$; exit 1;
  fi

  popd > /dev/null
}

Print_SeaTunnel() {
  echo
  echo "${CWARNING}The following will be removed:${CEND}"
  [ -e "${seatunnel_install_dir}" ] && echo "  - ${seatunnel_install_dir}"
  [ -e "/lib/systemd/system/seatunnel.service" ] && echo "  - /lib/systemd/system/seatunnel.service"
  [ -e "/lib/systemd/system/seatunnel-master.service" ] && echo "  - /lib/systemd/system/seatunnel-master.service"
  [ -e "/lib/systemd/system/seatunnel-worker.service" ] && echo "  - /lib/systemd/system/seatunnel-worker.service"
  [ -e "/etc/profile.d/seatunnel.sh" ] && echo "  - /etc/profile.d/seatunnel.sh"
  echo
}

Uninstall_SeaTunnel() {
  # Stop services
  echo "${CMSG}Stopping SeaTunnel services...${CEND}"
  systemctl stop seatunnel > /dev/null 2>&1
  systemctl stop seatunnel-master > /dev/null 2>&1
  systemctl stop seatunnel-worker > /dev/null 2>&1

  # Disable and remove service files
  echo "${CMSG}Removing systemd services...${CEND}"
  if [ -e "/lib/systemd/system/seatunnel.service" ]; then
    systemctl disable seatunnel > /dev/null 2>&1
    rm -f /lib/systemd/system/seatunnel.service
  fi
  if [ -e "/lib/systemd/system/seatunnel-master.service" ]; then
    systemctl disable seatunnel-master > /dev/null 2>&1
    rm -f /lib/systemd/system/seatunnel-master.service
  fi
  if [ -e "/lib/systemd/system/seatunnel-worker.service" ]; then
    systemctl disable seatunnel-worker > /dev/null 2>&1
    rm -f /lib/systemd/system/seatunnel-worker.service
  fi
  systemctl daemon-reload

  # Backup data directory (rename instead of delete)
  if [ -e "${seatunnel_data_dir}" ] && [ "${keep_data}" != "true" ]; then
    echo "${CMSG}Backing up data directory...${CEND}"
    /bin/mv ${seatunnel_data_dir}{,_$(date +%Y%m%d%H%M)}
  fi

  # Remove install directory
  echo "${CMSG}Removing installation directory...${CEND}"
  rm -rf ${seatunnel_install_dir}

  # Remove environment variables
  echo "${CMSG}Cleaning up environment variables...${CEND}"
  rm -f /etc/profile.d/seatunnel.sh

  # Clean up temp directories
  rm -rf /tmp/seatunnel
  rm -rf /var/run/seatunnel

  # Update options.conf
  sed -i "s@^seatunnel_installed=.*@seatunnel_installed=@" ${seatunnel_dir}/options.conf 2>/dev/null

  # Remove user (optional)
  # id -u ${run_user} >/dev/null 2>&1 && userdel ${run_user}

  echo "${CSUCCESS}SeaTunnel uninstall completed!${CEND}"
}
