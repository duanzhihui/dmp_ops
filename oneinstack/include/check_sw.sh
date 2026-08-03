#!/bin/bash
# Author:  Alpha Eva <kaneawk AT gmail.com>
#
# Notes: OneinStack for CentOS/RedHat 7+ Debian 9+ and Ubuntu 16+
#
# Project home page:
#       https://oneinstack.com
#       https://github.com/oneinstack/oneinstack

installDepsDebian() {
  echo "${CMSG}Removing the conflicting packages...${CEND}"
  if [ "${apache_flag}" == 'y' ]; then
    killall apache2
    pkgList="apache2 apache2-doc libsodium-dev apache2-utils apache2.2-common apache2.2-bin apache2-mpm-prefork apache2-doc apache2-mpm-worker php5 php5-common php5-cgi php5-cli php5-mysql php5-curl php5-gd"
    for Package in ${pkgList};do
      apt-get -y purge ${Package}
    done
    dpkg -l | grep ^rc | awk '{print $2}' | xargs dpkg -P
  fi

  if [[ "${db_option}" =~ ^[1-9]$|^1[0-2]$ ]]; then
    pkgList="mysql-client mysql-server mysql-common libsodium-dev mysql-server-core-5.5 mysql-client-5.5 mariadb-client mariadb-server mariadb-common"
    for Package in ${pkgList};do
      apt-get -y purge ${Package}
    done
    dpkg -l | grep ^rc | awk '{print $2}' | xargs dpkg -P
  fi

  echo "${CMSG}Installing dependencies packages...${CEND}"
  apt-get -y update
  apt-get -y autoremove
  apt-get -yf install
  export DEBIAN_FRONTEND=noninteractive

  # critical security updates
  grep security /etc/apt/sources.list > /tmp/security.sources.list
  apt-get -y upgrade -o Dir::Etc::SourceList=/tmp/security.sources.list

  # Install needed packages
  case "${Debian_ver}" in
    9|10|11|12|13)
      pkgList="debian-keyring libsodium-dev debian-archive-keyring libxpm-dev build-essential gcc g++ make cmake autoconf libbz2-dev libjpeg62-turbo-dev libjpeg-dev libpng-dev libgd-dev libxml2 libxml2-dev zlib1g zlib1g-dev libc6 libc6-dev libc-client2007e-dev libglib2.0-0 libglib2.0-dev bzip2 libzip-dev libbz2-1.0 libncurses5 libncurses5-dev libaio1 libaio-dev numactl libreadline-dev curl libcurl3-gnutls libcurl4-openssl-dev e2fsprogs libkrb5-3 libkrb5-dev libltdl-dev libidn11 libidn11-dev openssl net-tools libssl-dev libtool libevent-dev bison re2c libsasl2-dev libxslt1-dev libicu-dev locales patch vim zip unzip tmux htop bc dc expect libexpat1-dev libonig-dev libtirpc-dev rsync git lsof lrzsz rsyslog cron logrotate chrony libsqlite3-dev psmisc wget sysv-rc apt-transport-https ca-certificates software-properties-common gnupg ufw"
      ;;
    *)
      echo "${CFAILURE}Your system Debian ${Debian_ver} are not supported!${CEND}"
      kill -9 $$; exit 1;
      ;;
  esac
  for Package in ${pkgList}; do
    apt-get --no-install-recommends -y install ${Package}
  done
}

installDepsRHEL() {
  [ -e '/etc/yum.conf' ] && sed -i 's@^exclude@#exclude@' /etc/yum.conf
  if [ "${RHEL_ver}" == '9' ]; then
    if [[ "${Platform}" =~ "rhel" ]]; then
      subscription-manager repos --enable codeready-builder-for-rhel-9-${ARCH}-rpms
      dnf -y install chrony oniguruma-devel rpcgen
    elif [[ "${Platform}" =~ "ol" ]]; then
      dnf config-manager --set-enabled ol9_codeready_builder
      dnf -y install chrony oniguruma-devel rpcgen
    else
      dnf -y --enablerepo=crb install chrony oniguruma-devel rpcgen
    fi
    systemctl enable chronyd
  elif [ "${RHEL_ver}" == '8' ]; then
    if [[ "${Platform}" =~ "rhel" ]]; then
      subscription-manager repos --enable codeready-builder-for-rhel-8-${ARCH}-rpms
      dnf -y install chrony oniguruma-devel rpcgen
    elif [[ "${Platform}" =~ "ol" ]]; then
      dnf config-manager --set-enabled ol8_codeready_builder
      dnf -y install chrony oniguruma-devel rpcgen
    else
      [ -z "`grep -w epel /etc/yum.repos.d/*.repo`" ] && yum -y install epel-release
      if grep -qw "^\[PowerTools\]" /etc/yum.repos.d/*.repo; then
        dnf -y --enablerepo=PowerTools install chrony oniguruma-devel rpcgen
      elif grep -qw "^\[powertools\]" /etc/yum.repos.d/*.repo; then
        dnf -y --enablerepo=powertools install chrony oniguruma-devel rpcgen
      fi
    fi
    systemctl enable chronyd
  elif [ "${RHEL_ver}" == '7' ]; then
    [ -z "`grep -w epel /etc/yum.repos.d/*.repo`" ] && yum -y install epel-release
    yum -y groupremove "Basic Web Server" "MySQL Database server" "MySQL Database client"
  fi

  if [ "${RHEL_ver}" == '9' ]; then
    [ ! -e "/usr/lib64/libtinfo.so.5" ] && ln -s /usr/lib64/libtinfo.so.6 /usr/lib64/libtinfo.so.5
    [ ! -e "/usr/lib64/libncurses.so.5" ] && ln -s /usr/lib64/libncurses.so.6 /usr/lib64/libncurses.so.5
  fi

  echo "${CMSG}Installing dependencies packages...${CEND}"
  # Install needed packages
  pkgList="perl-FindBin deltarpm libsodium-dev drpm gcc gcc-c++ make cmake autoconf libjpeg libjpeg-dev libjpeg-devel libbz2-dev libjpeg-turbo libjpeg-turbo-devel libpng libpng-devel libxml2 libxml2-devel zlib zlib-devel libzip libzip-devel glibc glibc-devel krb5-devel libcurl4-openssl-dev libc-client libc-client-devel glib2 glib2-devel bzip2 bzip2-devel ncurses ncurses-devel ncurses-compat-libs libaio numactl numactl-libs readline-devel curl curl-devel e2fsprogs e2fsprogs-devel krb5-devel libidn libidn-devel openssl openssl-devel net-tools libxslt-devel libssl-dev libicu-devel libevent-devel libtool libtool-ltdl bison gd-devel vim-enhanced pcre-devel libmcrypt libsqlite3-dev libmcrypt-devel mhash mhash-devel mcrypt zip unzip chrony oniguruma-devel rpcgen sqlite-devel sysstat patch bc expect expat-devel perl-devel oniguruma oniguruma-devel libtirpc-devel nss libnsl rsync rsyslog git lsof lrzsz psmisc wget which libatomic tmux chkconfig firewalld"
  for Package in ${pkgList}; do
    yum -y install ${Package}
  done
  [ ${RHEL_ver} -lt 8 >/dev/null 2>&1 ] && yum -y install cmake3

  yum -y update bash openssl glibc
}

installDepsUbuntu() {
  # Uninstall the conflicting software
  echo "${CMSG}Removing the conflicting packages...${CEND}"
  if [ "${apache_flag}" == 'y' ]; then
    killall apache2
    pkgList="apache2 apache2-doc apache2-utils apache2.2-common apache2.2-bin apache2-mpm-prefork apache2-doc apache2-mpm-worker php5 php5-common php5-cgi php5-cli php5-mysql php5-curl php5-gd libncurses5"
    for Package in ${pkgList};do
      apt-get -y purge ${Package}
    done
    dpkg -l | grep ^rc | awk '{print $2}' | xargs dpkg -P
  fi

  if [[ "${db_option}" =~ ^[1-9]$|^1[0-2]$ ]]; then
    pkgList="mysql-client mysql-server mysql-common mysql-server-core-5.5 mysql-client-5.5 mariadb-client mariadb-server mariadb-common"
    for Package in ${pkgList};do
      apt-get -y purge ${Package}
    done
    dpkg -l | grep ^rc | awk '{print $2}' | xargs dpkg -P
  fi

  echo "${CMSG}Installing dependencies packages...${CEND}"
  apt-get -y update
  apt-get -y autoremove
  apt-get -yf install
  export DEBIAN_FRONTEND=noninteractive
  [[ "${Ubuntu_ver}" =~ ^22$ ]] && apt-get -y --allow-downgrades install libicu70=70.1-2 libglib2.0-0=2.72.1-1 libxml2-dev

  # critical security updates
  # Ubuntu 24.04+ 默认使用 deb822 格式 (/etc/apt/sources.list.d/ubuntu.sources)，
  # /etc/apt/sources.list 可能为空，直接 grep 会得到空源列表，这里加判断避免异常
  if grep -q security /etc/apt/sources.list 2>/dev/null; then
    grep security /etc/apt/sources.list > /tmp/security.sources.list
    apt-get -y upgrade -o Dir::Etc::SourceList=/tmp/security.sources.list
  fi

  # 优先确保编译工具链及 nginx/php 早期必需的开发库安装成功
  # （缺失会导致 icu/jemalloc/nginx 等源码编译连锁失败，如 zlib 缺失时 nginx gzip 模块报错）
  apt-get --no-install-recommends -y install build-essential gcc g++ make cmake autoconf bzip2 zlib1g-dev libssl-dev

  # 通用依赖包（各 Ubuntu 版本通用）
  pkgList="libperl-dev pkg-config libsodium-dev libbz2-dev libxslt-dev libjpeg-dev libxml2-dev libxpm-dev libfreetype-dev debian-keyring debian-archive-keyring build-essential gcc g++ make cmake autoconf libpng-dev libxml2 libxml2-dev zlib1g zlib1g-dev libc6 libc6-dev libglib2.0-0 libglib2.0-dev bzip2 libzip-dev libbz2-1.0 libaio-dev numactl libreadline-dev curl libcurl4-openssl-dev e2fsprogs libkrb5-3 libkrb5-dev libltdl-dev openssl net-tools libssl-dev libtool libevent-dev re2c libsasl2-dev libxslt1-dev libicu-dev libsqlite3-dev bison patch vim zip unzip tmux htop bc dc expect libexpat1-dev rsyslog libonig-dev libtirpc-dev libnss3 rsync git lsof lrzsz chrony psmisc wget sysv-rc apt-transport-https ca-certificates software-properties-common gnupg ufw libiconv-dev libfreetype6-dev libexif-dev gettext libgmp-dev"

  # 版本相关依赖包（24.04 起大量库因 64 位 time_t 迁移被重命名，旧包名已移除）
  case "${Ubuntu_ver}" in
    24|25|26)
      verPkgList="libjpeg-turbo8 libjpeg-turbo8-dev libaio1t64 libncurses-dev libncurses6 libidn12 libidn-dev libcurl3t64-gnutls libcurl4-gnutls-dev"
      ;;
    *)
      verPkgList="libjpeg8 libjpeg8-dev libpng12-0 libpng12-dev libpng3 libc-client2007e-dev libaio1 libncurses5 libncurses5-dev libidn11 libidn11-dev libcloog-ppl1 libcurl3-gnutls libcurl4-gnutls-dev"
      ;;
  esac

  export DEBIAN_FRONTEND=noninteractive
  for Package in ${pkgList} ${verPkgList}; do
    apt-get --no-install-recommends -y install ${Package}
  done

  # Ubuntu 24.04 将 libaio1 更名为 libaio1t64 且无过渡包，但 MySQL/Percona 仍链接 libaio.so.1，补软链
  libaio_t64=$(ldconfig -p 2>/dev/null | awk '/libaio\.so\.1t64/{print $NF; exit}')
  if [ -n "${libaio_t64}" ] && [ ! -e "${libaio_t64%t64}" ]; then
    ln -s "${libaio_t64}" "${libaio_t64%t64}"
    ldconfig
  fi

  # 校验编译工具链是否就绪，缺失则明确报错退出（避免后续 icu/jemalloc 出现难以定位的连锁失败）
  for tool in gcc g++ make bzip2; do
    if ! command -v ${tool} > /dev/null 2>&1; then
      echo "${CFAILURE}Essential build tool '${tool}' is missing after apt install. Please check your apt sources / network, then re-run.${CEND}"
      kill -9 $$; exit 1;
    fi
  done

  # 校验关键开发库头文件（zlib 缺失会导致 nginx 编译失败），缺失时再补装一次并报错退出
  if [ ! -e /usr/include/zlib.h ]; then
    apt-get -y install zlib1g-dev
    if [ ! -e /usr/include/zlib.h ]; then
      echo "${CFAILURE}zlib1g-dev is missing after apt install (maybe killed by OOM). Please free memory / add swap, then re-run.${CEND}"
      kill -9 $$; exit 1;
    fi
  fi
}

installDepsBySrc() {
  pushd ${oneinstack_dir}/src > /dev/null
  if ! command -v icu-config > /dev/null 2>&1 || icu-config --version | grep '^3.' || [ "${Ubuntu_ver}" == "20" ]; then
    tar xzf icu4c-${icu4c_ver}-src.tgz
    pushd icu/source > /dev/null
    ./configure --prefix=/usr/local
    make -j ${THREAD} && make install
    popd > /dev/null
    rm -rf icu
  fi

  if command -v lsof >/dev/null 2>&1; then
    echo 'already initialize' > ~/.oneinstack
  else
    echo "${CFAILURE}${PM} config error parsing file failed${CEND}"
    kill -9 $$; exit 1;
  fi

  popd > /dev/null
}
