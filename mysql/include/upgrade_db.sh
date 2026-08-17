#!/bin/bash
# MySQL 升级模块
# Author: DMP OPS
#
# 说明: MySQL 版本升级逻辑，包含备份、版本校验、升级、恢复等完整流程

Upgrade_DB() {
  pushd ${mysql_dir}/src > /dev/null
  
  # 1. 检测是否已安装
  if [ ! -e "${db_install_dir}/bin/mysql" ]; then
    echo "${CWARNING}MySQL is not installed on your system!${CEND}"
    exit 1
  fi

  # 2. 验证 root 密码
  echo "${CMSG}Verifying MySQL root password...${CEND}"
  while :; do
    ${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "quit" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "${CSUCCESS}Password verified successfully${CEND}"
      break
    else
      echo "${CWARNING}Password verification failed${CEND}"
      read -e -p "Please input the root password of database: " NEW_dbrootpwd
      ${db_install_dir}/bin/mysql -uroot -p${NEW_dbrootpwd} -e "quit" >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        dbrootpwd=${NEW_dbrootpwd}
        sed -i "s+^dbrootpwd.*+dbrootpwd='${dbrootpwd}'+" ${mysql_dir}/options.conf
        echo "${CSUCCESS}Password updated in options.conf${CEND}"
        break
      else
        echo "${CFAILURE}MySQL root password incorrect, Please enter again!${CEND}"
      fi
    fi
  done

  # 3. 获取当前版本
  OLD_db_ver=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e 'SELECT VERSION();' 2>/dev/null | tail -1)
  OLD_db_ver_main=$(echo ${OLD_db_ver} | awk -F. '{print $1"."$2}')
  echo ""
  echo "Current MySQL Version: ${CMSG}${OLD_db_ver}${CEND}"
  echo ""

  # 4. 升级前备份
  echo "${CMSG}Starting MySQL backup before upgrade...${CEND}"
  local backup_file="DB_all_backup_$(date +"%Y%m%d_%H%M%S").sql"
  ${db_install_dir}/bin/mysqldump -uroot -p${dbrootpwd} --opt --single-transaction --all-databases > ${backup_file}
  if [ -f "${backup_file}" ] && [ -s "${backup_file}" ]; then
    echo "${CSUCCESS}MySQL backup success: ${backup_file}${CEND}"
  else
    echo "${CFAILURE}MySQL backup failed!${CEND}"
    exit 1
  fi

  # 5. 输入目标版本并校验
  while :; do
    echo ""
    read -e -p "Please input upgrade MySQL Version (example: ${OLD_db_ver}): " NEW_db_ver
    
    # 检查版本号格式
    if ! echo "${NEW_db_ver}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "${CWARNING}Invalid version format! Please use format like: 8.0.39${CEND}"
      continue
    fi
    
    NEW_db_ver_main=$(echo ${NEW_db_ver} | awk -F. '{print $1"."$2}')
    
    # 检查主版本是否一致
    if [ "${NEW_db_ver_main}" != "${OLD_db_ver_main}" ]; then
      echo "${CWARNING}Major version must match!${CEND}"
      echo "Current: ${OLD_db_ver_main}.x, you can only upgrade to ${OLD_db_ver_main}.x"
      continue
    fi
    
    # 检查是否为同一版本
    if [ "${NEW_db_ver}" == "${OLD_db_ver}" ]; then
      echo "${CWARNING}New version is same as current version!${CEND}"
      continue
    fi
    
    break
  done

  # 6. 下载新版本
  echo ""
  echo "${CMSG}Downloading MySQL ${NEW_db_ver}...${CEND}"
  if [ "${ARCH}" == "x86_64" ]; then
    DB_filename=mysql-${NEW_db_ver}-linux-glibc2.17-x86_64
  else
    DB_filename=mysql-${NEW_db_ver}-linux-glibc2.17-${ARCH}
  fi
  
  src_url=${DOWN_ADDR_MYSQL}/${DB_filename}.tar.xz
  Download_src
  
  if [ ! -f "${DB_filename}.tar.xz" ]; then
    echo "${CFAILURE}Download failed!${CEND}"
    exit 1
  fi

  # 7. 停止服务
  echo "${CMSG}Stopping MySQL service...${CEND}"
  service mysqld stop
  while [ -n "$(pgrep mysqld)" ]; do
    sleep 1
  done
  echo "${CSUCCESS}MySQL service stopped${CEND}"

  # 8. 备份旧目录
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  echo "${CMSG}Backing up old directories...${CEND}"
  mv ${mysql_install_dir} ${mysql_install_dir}_old_${timestamp}
  mv ${mysql_data_dir} ${mysql_data_dir}_old_${timestamp}
  echo "Old install dir: ${mysql_install_dir}_old_${timestamp}"
  echo "Old data dir: ${mysql_data_dir}_old_${timestamp}"

  # 9. 创建新目录
  mkdir -p ${mysql_install_dir}
  mkdir -p ${mysql_data_dir}
  chown mysql:mysql -R ${mysql_data_dir}

  # 10. 解压新版本
  echo "${CMSG}Extracting new version...${CEND}"
  tar xJf ${DB_filename}.tar.xz
  mv ${DB_filename}/* ${mysql_install_dir}/

  # 11. 配置 jemalloc
  if [ -f /usr/local/lib/libjemalloc.so ] && [ -f "${mysql_install_dir}/bin/mysqld_safe" ]; then
    sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${mysql_install_dir}/bin/mysqld_safe
  fi
  
  # 修正路径
  if [ -f "${mysql_install_dir}/bin/mysqld_safe" ]; then
    sed -i "s@/usr/local/mysql@${mysql_install_dir}@g" ${mysql_install_dir}/bin/mysqld_safe
  fi

  # 12. 初始化数据目录
  echo "${CMSG}Initializing new data directory...${CEND}"
  ${mysql_install_dir}/bin/mysqld --initialize-insecure --user=mysql --basedir=${mysql_install_dir} --datadir=${mysql_data_dir}
  chown mysql:mysql -R ${mysql_data_dir}

  # 13. 更新服务脚本
  /bin/cp ${mysql_install_dir}/support-files/mysql.server /etc/init.d/mysqld
  sed -i "s@^basedir=.*@basedir=${mysql_install_dir}@" /etc/init.d/mysqld
  sed -i "s@^datadir=.*@datadir=${mysql_data_dir}@" /etc/init.d/mysqld
  chmod +x /etc/init.d/mysqld

  # 14. 启动服务
  echo "${CMSG}Starting MySQL service...${CEND}"
  service mysqld start
  sleep 3

  # 15. 恢复数据
  echo "${CMSG}Restoring database from backup...${CEND}"
  ${mysql_install_dir}/bin/mysql -uroot < ${backup_file}
  
  # 设置 root 密码
  ${mysql_install_dir}/bin/mysql -uroot -hlocalhost -e "ALTER USER root@'localhost' IDENTIFIED BY '${dbrootpwd}';"

  # 16. 重启服务
  service mysqld restart
  sleep 2

  # 17. 执行 mysql_upgrade (MySQL 8.0.16 之前需要)
  if echo "${NEW_db_ver}" | grep -qE '^5\.|^8\.0\.[0-9]$|^8\.0\.1[0-5]$'; then
    echo "${CMSG}Running mysql_upgrade...${CEND}"
    ${mysql_install_dir}/bin/mysql_upgrade -uroot -p${dbrootpwd} 2>/dev/null
  fi

  # 18. 验证升级结果
  NEW_ver_check=$(${mysql_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e 'SELECT VERSION();' 2>/dev/null | tail -1)
  if [ "${NEW_ver_check}" == "${NEW_db_ver}" ]; then
    echo ""
    echo "${CSUCCESS}========================================${CEND}"
    echo "${CSUCCESS}MySQL upgrade completed successfully!${CEND}"
    echo "${CSUCCESS}From: ${OLD_db_ver} -> To: ${NEW_db_ver}${CEND}"
    echo "${CSUCCESS}========================================${CEND}"
    
    # 清理下载的文件
    rm -rf ${DB_filename}*
  else
    echo "${CFAILURE}Upgrade verification failed!${CEND}"
    echo "Expected: ${NEW_db_ver}, Got: ${NEW_ver_check}"
  fi

  popd
}

# 显示升级帮助
Show_Upgrade_Help() {
  echo "MySQL Upgrade Tool"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help     Show this help message"
  echo "  -v, --version  Show current MySQL version"
  echo ""
  echo "Notes:"
  echo "  - Only minor version upgrades are supported (e.g., 8.0.35 -> 8.0.39)"
  echo "  - Major version upgrades (e.g., 5.7 -> 8.0) are NOT supported"
  echo "  - A full backup will be created before upgrade"
  echo "  - Old directories will be preserved with timestamp suffix"
}
