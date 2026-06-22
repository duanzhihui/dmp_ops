#!/bin/bash
# DolphinSchedulerStack - Apache DolphinScheduler Cluster Deployment Tool
# OS detection and validation

if [ -e "/etc/os-release" ]; then
  . /etc/os-release
else
  echo "${CFAILURE}/etc/os-release does not exist! ${CEND}"
  kill -9 $$; exit 1;
fi

# Get OS Version
Platform=${ID,,}
VERSION_MAIN_ID=${VERSION_ID%%.*}
ARCH=$(arch)

if [[ "${Platform}" =~ ^centos$|^rhel$|^almalinux$|^rocky$|^fedora$|^amzn$|^ol$|^alinux$|^anolis$|^tencentos$|^opencloudos$|^euleros$|^openeuler$ ]]; then
  PM=yum
  Family=rhel
  RHEL_ver=${VERSION_MAIN_ID}
  if [[ "${Platform}" =~ ^fedora$ ]]; then
    [ ${VERSION_MAIN_ID} -ge 19 ] && [ ${VERSION_MAIN_ID} -lt 28 ] && RHEL_ver=7
    [ ${VERSION_MAIN_ID} -ge 28 ] && [ ${VERSION_MAIN_ID} -lt 34 ] && RHEL_ver=8
    [ ${VERSION_MAIN_ID} -ge 34 ] && RHEL_ver=9
  elif [[ "${Platform}" =~ ^amzn$|^alinux$|^tencentos$|^euleros$ ]]; then
    [[ "${VERSION_MAIN_ID}" =~ ^2$ ]] && RHEL_ver=7
    [[ "${VERSION_MAIN_ID}" =~ ^3$ ]] && RHEL_ver=8
    [[ "${VERSION_MAIN_ID}" =~ ^4$ ]] && RHEL_ver=9
  elif [[ "${Platform}" =~ ^openeuler$ ]]; then
    [[ "${RHEL_ver}" =~ ^20$ ]] && RHEL_ver=7
    [[ "${RHEL_ver}" =~ ^2[1,2]$ ]] && RHEL_ver=8
  fi
elif [[ "${Platform}" =~ ^debian$|^deepin$ ]]; then
  PM=apt-get
  Family=debian
  Debian_ver=${VERSION_MAIN_ID}
  if [[ "${Platform}" =~ ^deepin$ ]]; then
    [[ "${Debian_ver}" =~ ^20$ ]] && Debian_ver=10
    [[ "${Debian_ver}" =~ ^23$ ]] && Debian_ver=11
  fi
elif [[ "${Platform}" =~ ^ubuntu$|^linuxmint$ ]]; then
  PM=apt-get
  Family=ubuntu
  Ubuntu_ver=${VERSION_MAIN_ID}
  if [[ "${Platform}" =~ ^linuxmint$ ]]; then
    [[ "${VERSION_MAIN_ID}" =~ ^19$ ]] && Ubuntu_ver=18
    [[ "${VERSION_MAIN_ID}" =~ ^20$ ]] && Ubuntu_ver=20
    [[ "${VERSION_MAIN_ID}" =~ ^21$ ]] && Ubuntu_ver=22
  fi
else
  echo "${CFAILURE}Does not support this OS ${CEND}"
  kill -9 $$; exit 1;
fi

# Check minimum OS version (DolphinScheduler requires CentOS 7+, Debian 9+, Ubuntu 16+)
if [ "${Family}" == "rhel" ] && [ ${RHEL_ver:-0} -lt 7 ]; then
  echo "${CFAILURE}Does not support this OS, Please install CentOS 7+ ${CEND}"
  kill -9 $$; exit 1;
elif [ "${Family}" == "debian" ] && [ ${Debian_ver:-0} -lt 9 ]; then
  echo "${CFAILURE}Does not support this OS, Please install Debian 9+ ${CEND}"
  kill -9 $$; exit 1;
elif [ "${Family}" == "ubuntu" ] && [ ${Ubuntu_ver:-0} -lt 16 ]; then
  echo "${CFAILURE}Does not support this OS, Please install Ubuntu 16+ ${CEND}"
  kill -9 $$; exit 1;
fi

# Detect system architecture
if [ "$(getconf WORD_BIT)" == "32" ] && [ "$(getconf LONG_BIT)" == "64" ]; then
  if uname -m | grep -Eqi "aarch64"; then
    SYS_ARCH=aarch64
  else
    SYS_ARCH=x86_64
  fi
else
  echo "${CWARNING}32-bit OS are not supported! ${CEND}"
  kill -9 $$; exit 1;
fi

THREAD=$(grep 'processor' /proc/cpuinfo | sort -u | wc -l)
