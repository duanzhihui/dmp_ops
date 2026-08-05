#!/bin/bash
# OpenJDK 包管理器安装实现
# 项目: dmp_ops/openjdk
# 代码来源: oneinstack/include/openjdk-8.sh / openjdk-11.sh / openjdk-17.sh / openjdk-18.sh
#
# 提供函数:
#   Get_Pkg_Name          输出 pkg_name / java_home / use_temurin
#   Install_JDK_Package   包管理器安装
#   Uninstall_JDK_Package 包管理器卸载

# 根据 OS 与 feature 版本推导包名与预期 JAVA_HOME
# 发行版仓库缺包时置 use_temurin=1，改用 Adoptium 的 temurin-{N}-jdk
Get_Pkg_Name() {
  local ver=$1
  pkg_name=""
  java_home=""
  use_temurin=0

  if [ "${Family}" == 'rhel' ]; then
    # CentOS/RHEL 7 官方仓库无 17/18/21
    [[ "${RHEL_ver}" == '7' ]] && [[ "${ver}" =~ ^17$|^18$|^21$ ]] && use_temurin=1
    if [ ${use_temurin} -eq 1 ]; then
      pkg_name="temurin-${ver}-jdk"
      java_home="/usr/lib/jvm/temurin-${ver}-jdk"
    elif [ "${ver}" == '8' ]; then
      pkg_name="java-1.8.0-openjdk-devel"
      java_home="/usr/lib/jvm/java-1.8.0-openjdk"
    else
      pkg_name="java-${ver}-openjdk-devel"
      java_home="/usr/lib/jvm/java-${ver}-openjdk"
    fi
  elif [ "${Family}" == 'debian' ]; then
    # Debian 10+ 已移除 openjdk-8-jdk；Debian 9/10 无 17/21
    [ "${ver}" == '8' ] && [ ${Debian_ver} -ge 10 ] 2>/dev/null && use_temurin=1
    [[ "${ver}" =~ ^17$|^18$|^21$ ]] && [[ "${Debian_ver}" =~ ^9$|^10$ ]] && use_temurin=1
    if [ ${use_temurin} -eq 1 ]; then
      pkg_name="temurin-${ver}-jdk"
      java_home="/usr/lib/jvm/temurin-${ver}-jdk-${SYS_ARCH}"
    else
      pkg_name="openjdk-${ver}-jdk"
      java_home="/usr/lib/jvm/java-${ver}-openjdk-${SYS_ARCH}"
    fi
  elif [ "${Family}" == 'ubuntu' ]; then
    # Ubuntu 16 仓库无 11/17/18/21
    [[ "${Ubuntu_ver}" =~ ^16$ ]] && [[ "${ver}" =~ ^11$|^17$|^18$|^21$ ]] && use_temurin=1
    if [ ${use_temurin} -eq 1 ]; then
      pkg_name="temurin-${ver}-jdk"
      java_home="/usr/lib/jvm/temurin-${ver}-jdk-${SYS_ARCH}"
    else
      pkg_name="openjdk-${ver}-jdk"
      java_home="/usr/lib/jvm/java-${ver}-openjdk-${SYS_ARCH}"
    fi
  fi

  echo "${CMSG}Package: ${pkg_name} (temurin: ${use_temurin})${CEND}"
}

Install_JDK_Package() {
  local ver=$1
  Get_Pkg_Name ${ver}
  [ -z "${pkg_name}" ] && {
    echo "${CFAILURE}Cannot determine package name for OpenJDK ${ver} on ${Platform}${CEND}"
    return 1
  }

  # 后台自动更新(unattended-upgrades)可能正持有 dpkg/yum 锁，先等待再安装
  Wait_PM_Lock || return 1

  [ ${use_temurin} -eq 1 ] && { Add_Adoptium_Repo || return 1; }

  echo "${CMSG}Installing ${pkg_name} ...${CEND}"
  if [ "${PM}" == 'apt-get' ]; then
    PM_Cmd -y update > /dev/null 2>&1
    PM_Cmd --no-install-recommends -y install ${pkg_name}
  else
    PM_Cmd -y install ${pkg_name}
  fi

  # 发行版仓库缺包时，回退 Adoptium 再试一次
  # 注意: 仅当包在仓库中确实不可用才回退，避免把锁/网络/依赖问题误判为缺包
  if [ ! -x "${java_home}/bin/java" ] && [ ${use_temurin} -eq 0 ]; then
    local detected=$(Detect_JAVA_HOME ${ver})
    if [ -z "${detected}" ]; then
      if Pkg_Available "${pkg_name}"; then
        echo "${CFAILURE}${pkg_name} is available in the distro repo but installation failed${CEND}"
        echo "${CWARNING}Check the ${PM} output above, or retry with --install_method binary${CEND}"
        return 1
      fi
      echo "${CWARNING}${pkg_name} not available in distro repo, falling back to Adoptium Temurin...${CEND}"
      use_temurin=1
      Add_Adoptium_Repo || return 1
      pkg_name="temurin-${ver}-jdk"
      if [ "${Family}" == 'rhel' ]; then
        java_home="/usr/lib/jvm/temurin-${ver}-jdk"
      else
        java_home="/usr/lib/jvm/temurin-${ver}-jdk-${SYS_ARCH}"
      fi
      if [ "${PM}" == 'apt-get' ]; then
        PM_Cmd --no-install-recommends -y install ${pkg_name}
      else
        PM_Cmd -y install ${pkg_name}
      fi
    fi
  fi

  # 包名与目录名可能不一致(架构后缀/次版本目录)，二次探测
  local real_home=$(Detect_JAVA_HOME ${ver})
  [ -n "${real_home}" ] && java_home="${real_home}"

  [ -x "${java_home}/bin/java" ] && return 0
  return 1
}

Uninstall_JDK_Package() {
  local ver=$1
  Get_Pkg_Name ${ver}
  [ -z "${pkg_name}" ] && return 1

  echo "${CMSG}Removing ${pkg_name} ...${CEND}"
  if [ "${PM}" == 'apt-get' ]; then
    PM_Cmd -y purge ${pkg_name} > /dev/null 2>&1
    PM_Cmd -y autoremove > /dev/null 2>&1
  else
    PM_Cmd -y remove ${pkg_name} > /dev/null 2>&1
  fi
  return 0
}
