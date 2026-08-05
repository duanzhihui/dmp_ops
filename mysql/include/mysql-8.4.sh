#!/bin/bash
# MySQL 8.4 安装模块
# Author: DMP OPS
#
# 说明: MySQL 8.4 的完整安装逻辑，支持二进制和源码编译两种方式

Install_MySQL84() {
  pushd ${mysql_dir}/src > /dev/null
  
  # 1. 检测是否已安装（幂等）
  if [ -d "${mysql_install_dir}/support-files" ]; then
    echo "${CWARNING}MySQL is already installed at ${mysql_install_dir}${CEND}"
    return 0
  fi

  # 2. 创建 mysql 用户（幂等）
  id -u mysql >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    useradd -M -s /sbin/nologin mysql
    echo "${CSUCCESS}Created mysql user${CEND}"
  fi

  # 3. 创建安装目录和数据目录
  [ ! -d "${mysql_install_dir}" ] && mkdir -p ${mysql_install_dir}
  [ ! -d "${mysql_data_dir}" ] && mkdir -p ${mysql_data_dir}
  chown mysql:mysql -R ${mysql_data_dir}

  # 4. 安装方式分支
  if [ "${dbinstallmethod}" == "1" ]; then
    # === 二进制安装 ===
    echo "${CMSG}Installing MySQL ${mysql84_ver} from binary package...${CEND}"
    
    # 下载二进制包
    if [ "${ARCH}" == "x86_64" ]; then
      src_url=${DOWN_ADDR_MYSQL}/mysql-${mysql84_ver}-linux-glibc2.17-x86_64.tar.xz
    else
      src_url=${DOWN_ADDR_MYSQL}/mysql-${mysql84_ver}-linux-glibc2.17-${ARCH}.tar.xz
    fi
    Download_src
    
    # 解压
    local filename="${src_url##*/}"
    local dirname="${filename%.tar.xz}"
    tar xJf ${filename}
    
    # 移动文件
    mv ${dirname}/* ${mysql_install_dir}
    
    # 修正 mysqld_safe 路径
    if [ -f "${mysql_install_dir}/bin/mysqld_safe" ]; then
      sed -i "s@/usr/local/mysql@${mysql_install_dir}@g" ${mysql_install_dir}/bin/mysqld_safe
    fi
    
  elif [ "${dbinstallmethod}" == "2" ]; then
    # === 源码编译安装 ===
    echo "${CMSG}Installing MySQL ${mysql84_ver} from source...${CEND}"
    
    # 下载 boost
    local boostVersion2=$(echo ${boost_mysql84_ver} | awk -F. '{print $1"_"$2"_"$3}')
    src_url=${DOWN_ADDR_MYSQL}/boost_${boostVersion2}.tar.gz
    Download_src
    tar xzf boost_${boostVersion2}.tar.gz
    
    # 下载 MySQL 源码
    src_url=${DOWN_ADDR_MYSQL}/mysql-${mysql84_ver}.tar.gz
    Download_src
    tar xzf mysql-${mysql84_ver}.tar.gz
    
    pushd mysql-${mysql84_ver}
    cmake . -DCMAKE_INSTALL_PREFIX=${mysql_install_dir} \
      -DMYSQL_DATADIR=${mysql_data_dir} \
      -DWITH_BOOST=../boost_${boostVersion2} \
      -DSYSCONFDIR=/etc \
      -DWITH_INNOBASE_STORAGE_ENGINE=1 \
      -DWITH_PARTITION_STORAGE_ENGINE=1 \
      -DWITH_FEDERATED_STORAGE_ENGINE=1 \
      -DWITH_BLACKHOLE_STORAGE_ENGINE=1 \
      -DWITH_MYISAM_STORAGE_ENGINE=1 \
      -DENABLED_LOCAL_INFILE=1 \
      -DDEFAULT_CHARSET=utf8mb4 \
      -DDEFAULT_COLLATION=utf8mb4_0900_ai_ci \
      -DWITH_EXTRA_CHARSETS=all \
      -DWITH_EMBEDDED_SERVER=0
    
    make -j ${THREAD}
    make install
    popd
  fi

  # 5. 安装后验证
  if [ ! -d "${mysql_install_dir}/support-files" ]; then
    rm -rf ${mysql_install_dir}
    echo "${CFAILURE}MySQL install failed!${CEND}"
    grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    kill -9 $$; exit 1;
  fi

  # 6. 配置 jemalloc 优化
  if [ -f /usr/local/lib/libjemalloc.so ]; then
    if [ -f "${mysql_install_dir}/bin/mysqld_safe" ]; then
      sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${mysql_install_dir}/bin/mysqld_safe
    fi
  fi

  # 7. 生成 my.cnf 配置文件
  Generate_MySQL_Config

  # 8. 注册服务脚本
  /bin/cp ${mysql_install_dir}/support-files/mysql.server /etc/init.d/mysqld
  sed -i "s@^basedir=.*@basedir=${mysql_install_dir}@" /etc/init.d/mysqld
  sed -i "s@^datadir=.*@datadir=${mysql_data_dir}@" /etc/init.d/mysqld
  chmod +x /etc/init.d/mysqld
  
  if [ "${PM}" == 'yum' ] || [ "${PM}" == 'dnf' ]; then
    chkconfig --add mysqld
    chkconfig mysqld on
  elif [ "${PM}" == 'apt-get' ]; then
    update-rc.d mysqld defaults
  fi

  # 9. 初始化数据目录
  echo "${CMSG}Initializing MySQL data directory...${CEND}"
  # 二进制包依赖旧 soname，初始化前再补一次兼容软链并校验，避免 libaio.so.1 缺失导致静默失败
  Fix_Compat_Libs
  if ! Check_Bin_Libs ${mysql_install_dir}/bin/mysqld; then
    echo "${CFAILURE}mysqld cannot run due to missing libraries, aborting.${CEND}"
    kill -9 $$; exit 1;
  fi
  if [ -d "${mysql_data_dir}/mysql" ]; then
    echo "${CWARNING}Data directory ${mysql_data_dir} already initialized, skip.${CEND}"
  elif ! ${mysql_install_dir}/bin/mysqld --initialize-insecure --user=mysql --basedir=${mysql_install_dir} --datadir=${mysql_data_dir}; then
    echo "${CFAILURE}Failed to initialize data directory ${mysql_data_dir}!${CEND}"
    [ -f "${mysql_data_dir}/mysql-error.log" ] && tail -20 ${mysql_data_dir}/mysql-error.log
    kill -9 $$; exit 1;
  fi
  chown mysql:mysql -R ${mysql_data_dir}

  # 10. 启动服务
  service mysqld start
  sleep 3
  if ! ${mysql_install_dir}/bin/mysqladmin --socket=/tmp/mysql.sock ping >/dev/null 2>&1; then
    echo "${CFAILURE}MySQL failed to start!${CEND}"
    [ -f "${mysql_data_dir}/mysql-error.log" ] && tail -20 ${mysql_data_dir}/mysql-error.log
    kill -9 $$; exit 1;
  fi

  # 11. 设置 PATH 环境变量
  if [ -z "$(grep ^'export PATH=' /etc/profile)" ]; then
    echo "export PATH=${mysql_install_dir}/bin:\$PATH" >> /etc/profile
  elif [ -z "$(grep ${mysql_install_dir} /etc/profile)" ]; then
    sed -i "s@^export PATH=\(.*\)@export PATH=${mysql_install_dir}/bin:\1@" /etc/profile
  fi
  . /etc/profile

  # 12. 设置 root 密码
  echo "${CMSG}Setting MySQL root password...${CEND}"
  if ! Check_Bin_Libs ${mysql_install_dir}/bin/mysql; then
    echo "${CFAILURE}mysql client cannot run due to missing libraries, aborting.${CEND}"
    kill -9 $$; exit 1;
  fi
  if ! ${mysql_install_dir}/bin/mysql -uroot -hlocalhost -e "CREATE USER IF NOT EXISTS root@'127.0.0.1' IDENTIFIED BY '${dbrootpwd}';"; then
    echo "${CFAILURE}Failed to set MySQL root password!${CEND}"
    kill -9 $$; exit 1;
  fi
  ${mysql_install_dir}/bin/mysql -uroot -hlocalhost -e "GRANT ALL PRIVILEGES ON *.* TO root@'127.0.0.1' WITH GRANT OPTION;"
  ${mysql_install_dir}/bin/mysql -uroot -hlocalhost -e "GRANT ALL PRIVILEGES ON *.* TO root@'localhost' WITH GRANT OPTION;"
  ${mysql_install_dir}/bin/mysql -uroot -hlocalhost -e "ALTER USER root@'localhost' IDENTIFIED BY '${dbrootpwd}';"
  # MySQL 8.4 移除了 RESET MASTER，改用 RESET BINARY LOGS AND GTIDS
  ${mysql_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "RESET BINARY LOGS AND GTIDS;" 2>/dev/null

  # 13. 配置动态链接库
  rm -rf /etc/ld.so.conf.d/*mysql*.conf
  echo "${mysql_install_dir}/lib" > /etc/ld.so.conf.d/z-mysql.conf
  ldconfig

  # 14. 保存密码到配置文件
  sed -i "s+^dbrootpwd.*+dbrootpwd='${dbrootpwd}'+" ${mysql_dir}/options.conf

  # 15. 清理源码包
  rm -rf mysql-${mysql84_ver}* boost_*

  echo "${CSUCCESS}MySQL ${mysql84_ver} installed successfully!${CEND}"
  service mysqld stop
  popd
}

# 生成 MySQL 配置文件
Generate_MySQL_Config() {
  cat > /etc/my.cnf << EOF
[client]
port = 3306
socket = /tmp/mysql.sock
default-character-set = utf8mb4

[mysql]
prompt="MySQL [\\d]> "
no-auto-rehash

[mysqld]
port = 3306
socket = /tmp/mysql.sock

basedir = ${mysql_install_dir}
datadir = ${mysql_data_dir}
pid-file = ${mysql_data_dir}/mysql.pid
user = mysql
bind-address = 0.0.0.0
server-id = 1

init-connect = 'SET NAMES utf8mb4'
character-set-server = utf8mb4
collation-server = utf8mb4_0900_ai_ci

skip-name-resolve
back_log = 300

max_connections = 1000
max_connect_errors = 6000
open_files_limit = 65535
table_open_cache = 128
max_allowed_packet = 500M
binlog_cache_size = 1M
max_heap_table_size = 8M
tmp_table_size = 16M

read_buffer_size = 2M
read_rnd_buffer_size = 8M
sort_buffer_size = 8M
join_buffer_size = 8M
key_buffer_size = 4M

thread_cache_size = 8

ft_min_word_len = 4

log_bin = mysql-bin
binlog_format = mixed
binlog_expire_logs_seconds = 604800

log_error = ${mysql_data_dir}/mysql-error.log
slow_query_log = 1
long_query_time = 1
slow_query_log_file = ${mysql_data_dir}/mysql-slow.log

performance_schema = 0
explicit_defaults_for_timestamp

skip-external-locking

default_storage_engine = InnoDB
innodb_file_per_table = 1
innodb_open_files = 500
innodb_buffer_pool_size = 64M
innodb_write_io_threads = 4
innodb_read_io_threads = 4
innodb_thread_concurrency = 0
innodb_purge_threads = 1
innodb_flush_log_at_trx_commit = 2
innodb_log_buffer_size = 2M
innodb_max_dirty_pages_pct = 90
innodb_lock_wait_timeout = 120

bulk_insert_buffer_size = 8M
myisam_sort_buffer_size = 8M
myisam_max_sort_file_size = 10G

interactive_timeout = 28800
wait_timeout = 28800

[mysqldump]
quick
max_allowed_packet = 500M

[myisamchk]
key_buffer_size = 8M
sort_buffer_size = 8M
read_buffer = 4M
write_buffer = 4M
EOF

  # 根据内存大小调整配置
  if [ ${Mem} -gt 1500 ] && [ ${Mem} -le 3500 ]; then
    sed -i "s@^max_connections.*@max_connections = $((${Mem}/3))@" /etc/my.cnf
    sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 256M@' /etc/my.cnf
  elif [ ${Mem} -gt 3500 ]; then
    sed -i "s@^max_connections.*@max_connections = $((${Mem}/2))@" /etc/my.cnf
    sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 1024M@' /etc/my.cnf
    sed -i 's@^thread_cache_size.*@thread_cache_size = 16@' /etc/my.cnf
  fi
}
