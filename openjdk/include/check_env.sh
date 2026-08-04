#!/bin/bash
# 前置环境检测
# 项目: dmp_ops/openjdk
#
# 提供函数:
#   Option_To_Ver      jdk_option(1-5) -> feature 版本(8/11/17/18/21)
#   Ver_To_Option      feature 版本 -> jdk_option
#   Check_Deps         安装脚本运行所需的基础工具
#   Detect_JAVA_HOME   探测指定 feature 版本的 JAVA_HOME
#   Check_Installed_JDK 判断指定版本是否已安装(幂等依据)
#   Check_Net          检测 Adoptium 网络可达性

# jdk_option 与 feature 版本映射
Option_To_Ver() {
  case "$1" in
    1) echo 8  ;;
    2) echo 11 ;;
    3) echo 17 ;;
    4) echo 18 ;;
    5) echo 21 ;;
    *) echo "" ;;
  esac
}

Ver_To_Option() {
  case "$1" in
    8)  echo 1 ;;
    11) echo 2 ;;
    17) echo 3 ;;
    18) echo 4 ;;
    21) echo 5 ;;
    *)  echo "" ;;
  esac
}

# 校验 feature 版本是否受支持
Check_Support_Ver() {
  local ver=$1
  [ -z "${ver}" ] && return 1
  [ -n "$(echo ${jdk_support_vers} | tr ' ' '\n' | grep -x "${ver}")" ] && return 0
  echo "${CFAILURE}Unsupported JDK version: ${ver} (supported: ${jdk_support_vers})${CEND}"
  return 1
}

# 基础依赖检测与安装
Check_Deps() {
  local pkgs=""
  command -v wget   > /dev/null 2>&1 || pkgs="${pkgs} wget"
  command -v curl   > /dev/null 2>&1 || pkgs="${pkgs} curl"
  command -v tar    > /dev/null 2>&1 || pkgs="${pkgs} tar"
  command -v gzip   > /dev/null 2>&1 || pkgs="${pkgs} gzip"

  if [ "${Family}" == 'rhel' ]; then
    command -v alternatives > /dev/null 2>&1 || pkgs="${pkgs} chkconfig"
  else
    # Adoptium 仓库需要 apt-add-repository / gpg / https 传输
    command -v apt-add-repository > /dev/null 2>&1 || pkgs="${pkgs} software-properties-common"
    command -v gpg > /dev/null 2>&1 || pkgs="${pkgs} gnupg"
    [ -e "/usr/lib/apt/methods/https" ] || pkgs="${pkgs} apt-transport-https"
    [ -d "/usr/share/ca-certificates" ] || pkgs="${pkgs} ca-certificates"
  fi

  if [ -n "${pkgs}" ]; then
    echo "${CMSG}Installing dependencies:${pkgs}${CEND}"
    if [ "${PM}" == 'apt-get' ]; then
      apt-get -y update > /dev/null 2>&1
      apt-get --no-install-recommends -y install ${pkgs}
    else
      ${PM} -y install ${pkgs}
    fi
  fi
}

# 探测 JAVA_HOME
# 用法: java_home=$(Detect_JAVA_HOME 17)
# 兼容 package(发行版/temurin) 与 binary 两种安装布局，排除 jre 目录
Detect_JAVA_HOME() {
  local ver=$1
  [ -z "${ver}" ] && return 1

  local candidates=(
    "${jdk_base_dir}/jdk-${ver}"
    "/usr/lib/jvm/java-${ver}-openjdk"
    "/usr/lib/jvm/java-${ver}-openjdk-${SYS_ARCH}"
    "/usr/lib/jvm/temurin-${ver}-jdk"
    "/usr/lib/jvm/temurin-${ver}-jdk-${SYS_ARCH}"
  )
  if [ "${ver}" == '8' ]; then
    candidates+=(
      "/usr/lib/jvm/java-1.8.0-openjdk"
      "/usr/lib/jvm/java-1.8.0-openjdk-${SYS_ARCH}"
      "/usr/lib/jvm/java-8-openjdk-${SYS_ARCH}"
    )
  fi

  local d
  for d in "${candidates[@]}"; do
    if [ -x "${d}/bin/java" ] && [ -x "${d}/bin/javac" ]; then
      echo "${d}"
      return 0
    fi
  done

  # 兜底: 模糊匹配 /usr/lib/jvm 与 jdk_base_dir，排除 jre
  local fuzzy
  for fuzzy in $(ls -d /usr/lib/jvm/*${ver}* ${jdk_base_dir}/*${ver}* 2>/dev/null | grep -v jre); do
    if [ -x "${fuzzy}/bin/java" ] && [ -x "${fuzzy}/bin/javac" ]; then
      # 二次确认主版本号，避免 java-1.8.0 匹配到 18
      local real_ver=$(${fuzzy}/bin/java -version 2>&1 | head -1 | awk -F'"' '{print $2}' | awk -F'[._]' '{if ($1==1) print $2; else print $1}')
      [ "${real_ver}" == "${ver}" ] && { echo "${fuzzy}"; return 0; }
    fi
  done

  return 1
}

# 获取指定 JDK 的完整版本号
Get_JDK_Full_Ver() {
  local jh=$1
  [ -x "${jh}/bin/java" ] || return 1
  ${jh}/bin/java -version 2>&1 | head -1 | awk -F'"' '{print $2}'
}

# 判断指定 feature 版本是否已安装
Check_Installed_JDK() {
  local ver=$1
  local jh=$(Detect_JAVA_HOME ${ver})
  [ -n "${jh}" ] && return 0
  return 1
}

# Adoptium 网络可达性检测(binary 模式使用)
Check_Net() {
  local target=${1:-${adoptium_api}}
  if curl -s --connect-timeout 10 --max-time 20 -o /dev/null "${target}/info/available_releases" 2>/dev/null; then
    return 0
  fi
  echo "${CWARNING}Cannot reach ${target}, will try mirror and local src/ package${CEND}"
  return 1
}
