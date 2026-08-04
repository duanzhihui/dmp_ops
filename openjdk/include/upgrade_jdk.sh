#!/bin/bash
# OpenJDK 升级模块
# 项目: dmp_ops/openjdk
#
# 原则: 只做同 feature 版本内的补丁升级(如 17.0.x -> 17.0.y)
#       跨大版本必须走 install.sh + switch.sh，避免业务无法回退

# 获取指定 feature 版本的最新 GA release_name
Get_Latest_Release() {
  local ver=$1
  curl -s --connect-timeout 15 --max-time 30 \
    "${adoptium_api}/info/release_names?architecture=${API_ARCH}&image_type=jdk&os=linux&vendor=eclipse&release_type=ga&version=%5B${ver}%2C$((ver+1))%29&page_size=1&sort_order=DESC" 2>/dev/null \
    | grep -o 'jdk[-]\?[0-9][^"]*' | head -1
}

# 列出依赖该 JDK 的 JVM 进程(升级后需重启)
Print_Affected_JVM() {
  local jh=$1
  local real_jh=$(readlink -f "${jh}" 2>/dev/null)
  local pids=$(ps -eo pid,args 2>/dev/null | grep -F -e "${real_jh}/bin/java" -e "${jdk_link}/bin/java" | grep -v grep | awk '{print $1}' | sort -u)
  [ -z "${pids}" ] && return 0
  echo "${CWARNING}The following JVM processes are running on this JDK and MUST be restarted after upgrade:${CEND}"
  ps -fp $(echo ${pids} | tr '\n' ' ') 2>/dev/null | sed 1d
}

Upgrade_OpenJDK() {
  local ver=$1
  Check_Support_Ver ${ver} || return 1

  local jh=$(Detect_JAVA_HOME ${ver})
  [ -z "${jh}" ] && {
    echo "${CWARNING}OpenJDK ${ver} is not installed!${CEND}"
    echo "Run: ./install.sh --jdk_option $(Ver_To_Option ${ver})"
    exit 1
  }

  # ---------- 1. 当前版本 ----------
  OLD_ver=$(Get_JDK_Full_Ver "${jh}")
  echo "Current Version: ${CMSG}${OLD_ver}${CEND}  (${jh})"

  # ---------- 2. 最新可用补丁版本 ----------
  local latest_release=$(Get_Latest_Release ${ver})
  Latest_ver=$(echo "${latest_release}" | sed -e 's@^jdk-@@' -e 's@^jdk@@')
  [ -z "${Latest_ver}" ] && echo "${CWARNING}Cannot fetch latest version from Adoptium API${CEND}"

  # ---------- 3. 目标版本 ----------
  if [ -n "${target_patch_ver}" ]; then
    NEW_ver="${target_patch_ver}"
  elif [ "${quiet_mode}" == '1' ]; then
    NEW_ver="${Latest_ver}"
  else
    read -e -p "Please input upgrade version(default: ${Latest_ver}): " NEW_ver
    NEW_ver=${NEW_ver:-${Latest_ver}}
  fi
  [ -z "${NEW_ver}" ] && { echo "${CFAILURE}Target version is empty${CEND}"; exit 1; }

  # ---------- 4. 版本校验 ----------
  if [ "${NEW_ver}" == "${OLD_ver}" ]; then
    echo "${CWARNING}Same version, skip upgrade${CEND}"
    exit 0
  fi
  local new_feature=$(echo "${NEW_ver}" | sed -e 's@^jdk-\?@@' | awk -F'[.u+_-]' '{if ($1==1) print $2; else print $1}')
  if [ "${new_feature}" != "${ver}" ]; then
    echo "${CFAILURE}Cross feature-version upgrade is not allowed (${ver} -> ${new_feature}).${CEND}"
    echo "${CMSG}Use: ./install.sh --jdk_option $(Ver_To_Option ${new_feature}) && ./switch.sh --jdk_option $(Ver_To_Option ${new_feature})${CEND}"
    exit 1
  fi

  Print_Affected_JVM "${jh}"
  if [ "${quiet_mode}" != '1' ]; then
    read -e -p "Continue to upgrade ${OLD_ver} -> ${NEW_ver}? [y/n]: " up_flag
    [ "${up_flag}" != 'y' ] && exit 0
  fi

  # ---------- 5. 升级前备份 ----------
  mkdir -p "${backup_dir}"
  local conf_bak="${backup_dir}/JDK_${ver}_conf_$(date +%Y%m%d_%H%M%S).tgz"
  local sec_dirs=""
  [ -d "${jh}/lib/security" ] && sec_dirs="${sec_dirs} lib/security"
  [ -d "${jh}/conf" ] && sec_dirs="${sec_dirs} conf"
  [ -d "${jh}/jre/lib/security" ] && sec_dirs="${sec_dirs} jre/lib/security"
  if [ -n "${sec_dirs}" ]; then
    tar czf "${conf_bak}" -C "${jh}" ${sec_dirs} 2>/dev/null && \
      echo "${CMSG}Config backup: ${conf_bak}${CEND}"
  fi

  local dir_bak=""
  if [[ "${jh}" == ${jdk_base_dir}/jdk-* ]]; then
    dir_bak="${jh}_bak_$(date +%m%d%H%M)"
    /bin/cp -a "${jh}" "${dir_bak}" && echo "${CMSG}Directory backup: ${dir_bak}${CEND}"
  fi

  # ---------- 6. 执行升级 ----------
  java_home=""
  if [ "${install_method}" == 'binary' ]; then
    jdk_patch_ver="${NEW_ver}"
    Install_JDK_Binary ${ver}
  else
    Get_Pkg_Name ${ver}
    echo "${CMSG}Upgrading ${pkg_name} via ${PM} ...${CEND}"
    if [ "${PM}" == 'apt-get' ]; then
      apt-get -y update > /dev/null 2>&1
      apt-get -y install --only-upgrade ${pkg_name}
    else
      ${PM} -y update ${pkg_name}
    fi
    java_home=$(Detect_JAVA_HOME ${ver})
  fi

  # ---------- 7. 验证与回滚 ----------
  [ -z "${java_home}" ] && java_home=$(Detect_JAVA_HOME ${ver})
  if [ -n "${java_home}" ] && ${java_home}/bin/java -version > /dev/null 2>&1; then
    local cur_ver=$(Get_JDK_Full_Ver "${java_home}")
    # 若当前默认 JDK 是该版本，刷新软链与 alternatives
    if [ "$(readlink -f ${jdk_link} 2>/dev/null)" == "$(readlink -f ${jh})" ] || [ "${jdk_current_ver}" == "${ver}" ]; then
      Set_JDK_Env "${java_home}" "${ver}"
    fi
    Register_Alternatives "${java_home}" "${ver}"
    [ -n "${dir_bak}" ] && rm -rf "${dir_bak}"
    echo "${CSUCCESS}Successfully upgrade OpenJDK from ${OLD_ver} to ${cur_ver}${CEND}"
    Print_Affected_JVM "${java_home}"
    return 0
  fi

  echo "${CFAILURE}Upgrade failed, rolling back...${CEND}"
  if [ -n "${dir_bak}" ] && [ -d "${dir_bak}" ]; then
    rm -rf "${jdk_base_dir}/jdk-${ver}"
    /bin/mv "${dir_bak}" "${jdk_base_dir}/jdk-${ver}"
    Set_JDK_Env "${jdk_base_dir}/jdk-${ver}" "${ver}"
    echo "${CMSG}Rolled back to ${OLD_ver}${CEND}"
  else
    echo "${CWARNING}No directory backup available. Restore config from: ${conf_bak}${CEND}"
  fi
  exit 1
}
