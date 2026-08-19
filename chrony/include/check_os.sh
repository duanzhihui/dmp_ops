#!/bin/bash
# 操作系统检测
# 项目: dmp_ops/chrony
# 输出变量: Platform / Family / PM / ARCH / SYS_ARCH / THREAD / VERSION_MAIN_ID

Check_OS() {
  # 检测架构
  case "$(uname -m)" in
    x86_64)
      ARCH=x86_64
      SYS_ARCH=amd64
      ;;
    aarch64)
      ARCH=aarch64
      SYS_ARCH=arm64
      ;;
    *)
      echo "${CFAILURE}Unsupported architecture: $(uname -m)${CEND}"
      exit 1
      ;;
  esac

  # 检测 CPU 线程数
  THREAD=$(grep -c 'processor' /proc/cpuinfo 2>/dev/null)
  [ -z "${THREAD}" ] && THREAD=1

  # 检测操作系统
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    Platform=$(echo "${ID}" | tr '[:upper:]' '[:lower:]')
    VERSION_MAIN_ID=$(echo "${VERSION_ID}" | awk -F'.' '{print $1}')
    OS_PRETTY="${PRETTY_NAME}"
  elif [ -f /etc/redhat-release ]; then
    Platform="centos"
    VERSION_MAIN_ID=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    OS_PRETTY=$(cat /etc/redhat-release)
  else
    echo "${CFAILURE}Unsupported OS${CEND}"
    exit 1
  fi

  # 确定系统族和包管理器
  case "${Platform}" in
    centos|rhel|rocky|almalinux|ol|fedora|anolis|opencloudos|tencentos|alinux|kylin|uos|euleros|openeuler|bclinux)
      Family=rhel
      PM=yum
      [ -n "${VERSION_MAIN_ID}" ] && [ "${VERSION_MAIN_ID}" -ge 8 ] 2>/dev/null && PM=dnf
      command -v dnf > /dev/null 2>&1 || PM=yum
      ;;
    debian|deepin|kali)
      Family=debian
      PM=apt-get
      ;;
    ubuntu|linuxmint|pop|galliumos)
      Family=ubuntu
      PM=apt-get
      ;;
    *)
      # 兜底: 按 ID_LIKE 判定
      case "${ID_LIKE}" in
        *rhel*|*fedora*|*centos*)
          Family=rhel; PM=yum
          command -v dnf > /dev/null 2>&1 && PM=dnf
          ;;
        *debian*|*ubuntu*)
          Family=debian; PM=apt-get
          ;;
        *)
          echo "${CFAILURE}Unsupported OS: ${Platform}${CEND}"
          exit 1
          ;;
      esac
      ;;
  esac

  # 输出检测结果
  echo "${CMSG}OS Detection:${CEND}"
  echo "  Platform : ${Platform}"
  echo "  Family   : ${Family}"
  echo "  Version  : ${VERSION_MAIN_ID}"
  echo "  Arch     : ${ARCH}"
  echo "  Pkg Mgr  : ${PM}"
  echo "  Threads  : ${THREAD}"
}
