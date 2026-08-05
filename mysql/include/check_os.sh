#!/bin/bash
# 操作系统检测与适配
# Author: DMP OPS
#
# 说明: 检测 OS 类型、版本、架构，设置包管理器等变量
# 支持: CentOS/RHEL 7+, Debian 9+, Ubuntu 16+, AlmaLinux, Rocky Linux

# 检测 /etc/os-release
if [ -f /etc/os-release ]; then
  . /etc/os-release
  Platform=${ID,,}
  VERSION_MAIN_ID=${VERSION_ID%%.*}
  PRETTY_NAME="${PRETTY_NAME}"
else
  echo "${CFAILURE}Error: Cannot detect OS. /etc/os-release not found.${CEND}"
  exit 1
fi

# 检测架构
ARCH=$(arch 2>/dev/null || uname -m)
case "${ARCH}" in
  x86_64)
    ARCH="x86_64"
    ;;
  aarch64|arm64)
    ARCH="aarch64"
    ;;
  *)
    echo "${CFAILURE}Error: Unsupported architecture: ${ARCH}${CEND}"
    exit 1
    ;;
esac

# 检测 CPU 线程数
if [ -f /proc/cpuinfo ]; then
  THREAD=$(grep -c 'processor' /proc/cpuinfo)
else
  THREAD=$(nproc 2>/dev/null || echo 1)
fi

# 检测内存大小 (MB)
if command -v free >/dev/null 2>&1; then
  Mem=$(free -m | awk '/Mem:/{print $2}')
else
  Mem=1024
fi

# 设置包管理器和系统族
case "${Platform}" in
  centos|rhel|almalinux|rocky|ol|anolis|openeuler|fedora)
    PM="yum"
    Family="rhel"
    [ "${Platform}" == "fedora" ] && PM="dnf"
    [ "${VERSION_MAIN_ID}" -ge 8 ] 2>/dev/null && PM="dnf"
    ;;
  debian)
    PM="apt-get"
    Family="debian"
    ;;
  ubuntu|linuxmint|pop)
    PM="apt-get"
    Family="ubuntu"
    Ubuntu_ver="${VERSION_MAIN_ID}"
    ;;
  *)
    echo "${CFAILURE}Error: Unsupported OS: ${Platform}${CEND}"
    exit 1
    ;;
esac

# 检测 systemd
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  SYSTEMD=true
else
  SYSTEMD=false
fi

# 运行时兼容软链
# MySQL 官方预编译包仍链接旧 soname (libaio.so.1 / libncurses.so.5)，
# 而 Ubuntu 24.04+ 因 64 位 time_t 迁移只提供 libaio.so.1t64，ncurses 也只剩 .so.6，
# 缺链会导致 mysqld 初始化和 mysql 客户端报 "cannot open shared object file"。
# 按文件是否存在建链，对旧版发行版同样安全。
Fix_Compat_Libs() {
  local d lib
  for d in "/usr/lib/$(uname -m)-linux-gnu" "/lib/$(uname -m)-linux-gnu" /usr/lib64 /usr/lib; do
    [ -d "${d}" ] || continue
    if [ -e "${d}/libaio.so.1t64" ] && [ ! -e "${d}/libaio.so.1" ]; then
      ln -s "${d}/libaio.so.1t64" "${d}/libaio.so.1"
    fi
    for lib in libncurses libncursesw libtinfo libtinfow; do
      if [ -e "${d}/${lib}.so.6" ] && [ ! -e "${d}/${lib}.so.5" ]; then
        ln -s "${d}/${lib}.so.6" "${d}/${lib}.so.5"
      fi
    done
  done
  ldconfig
}

# 校验二进制的动态库依赖是否齐全，缺失时打印缺库清单
# 用法: Check_Bin_Libs /usr/local/mysql/bin/mysqld
Check_Bin_Libs() {
  local bin="$1"
  [ -x "${bin}" ] || return 0
  local missing=$(ldd "${bin}" 2>/dev/null | awk '/not found/{print $1}' | sort -u)
  if [ -n "${missing}" ]; then
    echo "${CFAILURE}Missing shared libraries for ${bin}:${CEND}"
    echo "${missing}" | sed 's@^@  @'
    return 1
  fi
  return 0
}

# 输出检测结果（调试用）
Show_OS_Info() {
  echo "========== OS Information =========="
  echo "Platform:    ${Platform}"
  echo "Version:     ${VERSION_MAIN_ID}"
  echo "Family:      ${Family}"
  echo "Package Mgr: ${PM}"
  echo "Arch:        ${ARCH}"
  echo "CPU Threads: ${THREAD}"
  echo "Memory:      ${Mem} MB"
  echo "Systemd:     ${SYSTEMD}"
  echo "===================================="
}
