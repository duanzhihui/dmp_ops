#!/bin/bash
# 操作系统与架构检测
# 项目: dmp_ops/openjdk
#
# 输出变量:
#   Platform  发行版 ID(小写)      如 centos/debian/ubuntu
#   Family    系统族               rhel/debian/ubuntu
#   PM        包管理器             yum/dnf/apt-get
#   RHEL_ver / Debian_ver / Ubuntu_ver  归一化主版本号
#   ARCH      内核架构             x86_64/aarch64
#   SYS_ARCH  发行版包架构后缀     amd64/arm64  (openjdk 包目录名使用)
#   API_ARCH  Adoptium API 架构名  x64/aarch64
#   THREAD    CPU 线程数

Check_OS() {
  # ---------- 架构检测 ----------
  ARCH=$(uname -m)
  case "${ARCH}" in
    x86_64|amd64)
      ARCH=x86_64
      SYS_ARCH=amd64
      API_ARCH=x64
      ;;
    aarch64|arm64)
      ARCH=aarch64
      SYS_ARCH=arm64
      API_ARCH=aarch64
      ;;
    *)
      echo "${CFAILURE}Unsupported architecture: ${ARCH}, only x86_64/aarch64 are supported${CEND}"
      kill -9 $$; exit 1
      ;;
  esac

  # 拒绝 32 位系统
  if [ "$(getconf LONG_BIT 2>/dev/null)" != "64" ]; then
    echo "${CWARNING}32-bit OS are not supported!${CEND}"
    kill -9 $$; exit 1
  fi

  THREAD=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
  [ -z "${THREAD}" ] && THREAD=1

  # ---------- 发行版检测 ----------
  if [ -e "/etc/os-release" ]; then
    . /etc/os-release
  else
    echo "${CFAILURE}/etc/os-release does not exist!${CEND}"
    kill -9 $$; exit 1
  fi

  Platform=$(echo "${ID}" | tr '[:upper:]' '[:lower:]')
  VERSION_MAIN_ID=${VERSION_ID%%.*}

  if [[ "${Platform}" =~ ^centos$|^rhel$|^almalinux$|^rocky$|^fedora$|^amzn$|^ol$|^alinux$|^anolis$|^tencentos$|^opencloudos$|^euleros$|^openeuler$|^kylin$|^uos$|^kylinsecos$ ]]; then
    Family=rhel
    PM=yum
    RHEL_ver=${VERSION_MAIN_ID}
    # 主流衍生版版本号归一化到 RHEL 主版本
    case "${Platform}" in
      fedora)
        [ ${VERSION_MAIN_ID} -ge 19 ] && [ ${VERSION_MAIN_ID} -lt 28 ] && RHEL_ver=7
        [ ${VERSION_MAIN_ID} -ge 28 ] && [ ${VERSION_MAIN_ID} -lt 34 ] && RHEL_ver=8
        [ ${VERSION_MAIN_ID} -ge 34 ] && RHEL_ver=9
        ;;
      amzn|alinux|tencentos|euleros)
        [[ "${VERSION_MAIN_ID}" =~ ^2$ ]] && RHEL_ver=7
        [[ "${VERSION_MAIN_ID}" =~ ^3$ ]] && RHEL_ver=8
        [[ "${VERSION_MAIN_ID}" =~ ^4$ ]] && RHEL_ver=9
        ;;
      openeuler)
        [[ "${VERSION_MAIN_ID}" =~ ^20$ ]] && RHEL_ver=7
        [[ "${VERSION_MAIN_ID}" =~ ^2[12]$ ]] && RHEL_ver=8
        [[ "${VERSION_MAIN_ID}" =~ ^2[2-9]$ ]] && RHEL_ver=9
        ;;
      opencloudos)
        [[ "${VERSION_MAIN_ID}" =~ ^8$ ]] && RHEL_ver=8
        [[ "${VERSION_MAIN_ID}" =~ ^9$ ]] && RHEL_ver=9
        ;;
      kylin)
        [[ "${VERSION_ID}" =~ ^V10 ]] && RHEL_ver=8
        ;;
      uos)
        [[ "${VERSION_MAIN_ID}" =~ ^20$ ]] && RHEL_ver=8
        ;;
      kylinsecos)
        [[ "${VERSION_ID}" =~ ^3.4 ]] && RHEL_ver=7
        [[ "${VERSION_ID}" =~ ^3.5 ]] && RHEL_ver=8
        ;;
    esac
    # RHEL 8+ 优先使用 dnf
    [ ${RHEL_ver} -ge 8 ] 2>/dev/null && command -v dnf > /dev/null 2>&1 && PM=dnf
  elif [[ "${Platform}" =~ ^debian$|^deepin$|^kali$ ]]; then
    Family=debian
    PM=apt-get
    Debian_ver=${VERSION_MAIN_ID}
    case "${Platform}" in
      deepin)
        [[ "${Debian_ver}" =~ ^20$ ]] && Debian_ver=10
        [[ "${Debian_ver}" =~ ^23$ ]] && Debian_ver=11
        ;;
      kali)
        [[ "${Debian_ver}" =~ ^202 ]] && Debian_ver=12
        ;;
    esac
  elif [[ "${Platform}" =~ ^ubuntu$|^linuxmint$|^elementary$|^pop$ ]]; then
    Family=ubuntu
    PM=apt-get
    Ubuntu_ver=${VERSION_MAIN_ID}
    case "${Platform}" in
      linuxmint)
        [[ "${VERSION_MAIN_ID}" =~ ^18$ ]] && Ubuntu_ver=16
        [[ "${VERSION_MAIN_ID}" =~ ^19$ ]] && Ubuntu_ver=18
        [[ "${VERSION_MAIN_ID}" =~ ^20$ ]] && Ubuntu_ver=20
        [[ "${VERSION_MAIN_ID}" =~ ^2[12]$ ]] && Ubuntu_ver=22
        ;;
      elementary)
        [[ "${VERSION_MAIN_ID}" =~ ^5$ ]] && Ubuntu_ver=18
        [[ "${VERSION_MAIN_ID}" =~ ^6$ ]] && Ubuntu_ver=20
        [[ "${VERSION_MAIN_ID}" =~ ^7$ ]] && Ubuntu_ver=22
        ;;
    esac
  else
    echo "${CFAILURE}Does not support this OS: ${Platform}${CEND}"
    grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    kill -9 $$; exit 1
  fi

  # ---------- 最低版本要求 ----------
  if [ ${RHEL_ver} -lt 7 ] 2>/dev/null || [ ${Debian_ver} -lt 9 ] 2>/dev/null || [ ${Ubuntu_ver} -lt 16 ] 2>/dev/null; then
    echo "${CFAILURE}Does not support this OS, Please install CentOS 7+, Debian 9+, Ubuntu 16+${CEND}"
    kill -9 $$; exit 1
  fi

  echo "${CMSG}OS Detection:${CEND}"
  echo "  Platform: ${Platform}"
  echo "  Family:   ${Family} (${RHEL_ver}${Debian_ver}${Ubuntu_ver})"
  echo "  Arch:     ${ARCH} (pkg: ${SYS_ARCH}, adoptium: ${API_ARCH})"
  echo "  PM:       ${PM}"
  echo "  Threads:  ${THREAD}"
}
