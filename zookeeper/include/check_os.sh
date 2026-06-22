#!/bin/bash
# 操作系统检测
# 项目: oneinstack/zookeeper

Check_OS() {
  # 检测架构
  if [ "$(uname -m)" == "x86_64" ]; then
    ARCH=x86_64
    SYS_ARCH=amd64
  elif [ "$(uname -m)" == "aarch64" ]; then
    ARCH=aarch64
    SYS_ARCH=arm64
  else
    echo "${CFAILURE}Unsupported architecture: $(uname -m)${CEND}"
    exit 1
  fi

  # 检测 CPU 线程数
  THREAD=$(grep -c 'processor' /proc/cpuinfo)

  # 检测操作系统
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    Platform=$(echo "${ID}" | tr '[:upper:]' '[:lower:]')
    VERSION_MAIN_ID=$(echo "${VERSION_ID}" | awk -F'.' '{print $1}')
  elif [ -f /etc/redhat-release ]; then
    Platform="centos"
    VERSION_MAIN_ID=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
  else
    echo "${CFAILURE}Unsupported OS${CEND}"
    exit 1
  fi

  # 确定系统族和包管理器
  case "${Platform}" in
    centos|rhel|rocky|almalinux|ol|fedora|anolis|opencloudos|tencentos|alinux)
      Family=rhel
      PM=yum
      [ "${VERSION_MAIN_ID}" -ge 8 ] && PM=dnf
      ;;
    debian)
      Family=debian
      PM=apt-get
      ;;
    ubuntu|linuxmint|pop)
      Family=ubuntu
      PM=apt-get
      ;;
    *)
      echo "${CFAILURE}Unsupported OS: ${Platform}${CEND}"
      exit 1
      ;;
  esac

  # 输出检测结果
  echo "${CMSG}OS Detection:${CEND}"
  echo "  Platform: ${Platform}"
  echo "  Family: ${Family}"
  echo "  Version: ${VERSION_MAIN_ID}"
  echo "  Arch: ${ARCH}"
  echo "  Package Manager: ${PM}"
  echo "  CPU Threads: ${THREAD}"
}
