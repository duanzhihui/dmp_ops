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
