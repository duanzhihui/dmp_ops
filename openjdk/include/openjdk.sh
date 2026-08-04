#!/bin/bash
# OpenJDK 安装/卸载编排模块
# 项目: dmp_ops/openjdk
#
# 提供函数:
#   Install_OpenJDK    安装(幂等)
#   Print_OpenJDK      卸载预览
#   Check_JDK_InUse    占用检测
#   Uninstall_status   卸载确认
#   Uninstall_OpenJDK  卸载

Install_OpenJDK() {
  local ver=$1
  Check_Support_Ver ${ver} || return 1

  [ "${ver}" == '18' ] && \
    echo "${CWARNING}OpenJDK 18 is a non-LTS release and already EOL, not recommended for production${CEND}"

  # ---------- 1. 幂等检测 ----------
  local exist_home=$(Detect_JAVA_HOME ${ver})
  if [ -n "${exist_home}" ]; then
    echo "${CWARNING}OpenJDK ${ver} already installed: ${exist_home} ($(Get_JDK_Full_Ver ${exist_home}))${CEND}"
    if [ "${set_default}" == 'y' ]; then
      Set_JDK_Env "${exist_home}" "${ver}" && Register_Alternatives "${exist_home}" "${ver}"
      Save_Option jdk_current_ver "${ver}"
      echo "${CMSG}Set as default JDK${CEND}"
    fi
    return 0
  fi

  # ---------- 2. 依赖 ----------
  Check_Deps

  # ---------- 3. 安装 ----------
  java_home=""
  case "${install_method}" in
    package)
      Install_JDK_Package ${ver}
      ;;
    binary)
      Install_JDK_Binary ${ver}
      ;;
    *)
      echo "${CFAILURE}Invalid install_method: ${install_method} (package|binary)${CEND}"
      return 1
      ;;
  esac

  # ---------- 4. 路径校验 ----------
  [ -z "${java_home}" ] && java_home=$(Detect_JAVA_HOME ${ver})
  if [ -z "${java_home}" ] || [ ! -x "${java_home}/bin/java" ]; then
    echo "${CFAILURE}OpenJDK ${ver} install failed, Please contact the author!${CEND}" && \
      grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    kill -9 $$; exit 1
  fi

  # ---------- 5. 环境变量与 alternatives ----------
  if [ "${set_default}" == 'y' ]; then
    Set_JDK_Env "${java_home}" "${ver}"
  fi
  Register_Alternatives "${java_home}" "${ver}"

  # ---------- 6. 日志目录 ----------
  mkdir -p "${log_dir}"

  # ---------- 7. 安装验证 ----------
  if ${java_home}/bin/java -version > /dev/null 2>&1 && ${java_home}/bin/javac -version > /dev/null 2>&1; then
    local full_ver=$(Get_JDK_Full_Ver "${java_home}")
    echo ""
    echo "${CSUCCESS}OpenJDK ${full_ver} installed successfully!${CEND}"
    echo "  Method    : ${install_method}"
    echo "  JAVA_HOME : ${java_home}"
    [ "${set_default}" == 'y' ] && echo "  Default   : yes (${jdk_link} -> ${java_home})"
    [ "${set_default}" != 'y' ] && echo "  Default   : no (use ./switch.sh --jdk_option $(Ver_To_Option ${ver}) to activate)"
    echo ""
    echo "${CMSG}Installed JDKs:${CEND}"
    Print_JDK_Table
    echo ""
    echo "${CMSG}Run 'source /etc/profile.d/openjdk.sh' or re-login to apply env in current shell${CEND}"
  else
    echo "${CFAILURE}OpenJDK ${ver} install failed, Please contact the author!${CEND}" && \
      grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    kill -9 $$; exit 1
  fi

  # ---------- 8. 配置持久化 ----------
  [ "${set_default}" == 'y' ] && Save_Option jdk_current_ver "${ver}"
  return 0
}

# 卸载预览
Print_OpenJDK() {
  local ver=$1
  local jh=$(Detect_JAVA_HOME ${ver})
  [ -z "${jh}" ] && { echo "${CWARNING}OpenJDK ${ver} is not installed${CEND}"; return 1; }

  echo "${CMSG}The following will be removed:${CEND}"
  echo "  ${jh}"
  if [ "$(readlink -f ${jdk_link} 2>/dev/null)" == "$(readlink -f ${jh})" ]; then
    echo "  ${jdk_link} (symlink, will be re-pointed or removed)"
    echo "  /etc/profile.d/openjdk.sh (will be rewritten or removed)"
  fi
  echo "  alternatives entries: ${jh}/bin/{java,javac,jar,keytool,...}"
  if [[ "${jh}" == ${jdk_base_dir}/jdk-* ]]; then
    echo "  install method: binary (directory will be renamed then deleted)"
  else
    Get_Pkg_Name ${ver} > /dev/null 2>&1
    echo "  install method: package (${pkg_name} will be removed by ${PM})"
  fi
  return 0
}

# 卸载确认(来源: oneinstack uninstall.sh)
Uninstall_status() {
  while :; do
    read -e -p "Do you want to uninstall it? [y/n]: " uninstall_flag
    if [[ ! "${uninstall_flag}" =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done
}

# 占用检测: 是否有 JVM 进程正在使用该 JDK
Check_JDK_InUse() {
  local jh=$1
  local real_jh=$(readlink -f "${jh}" 2>/dev/null)
  local pids=$(ps -eo pid,args 2>/dev/null | grep -F "${real_jh}/bin/java" | grep -v grep | awk '{print $1}')
  # 通过 ${jdk_link} 启动的进程也算占用
  if [ "$(readlink -f ${jdk_link} 2>/dev/null)" == "${real_jh}" ]; then
    local link_pids=$(ps -eo pid,args 2>/dev/null | grep -F "${jdk_link}/bin/java" | grep -v grep | awk '{print $1}')
    pids="${pids} ${link_pids}"
  fi
  pids=$(echo ${pids} | tr ' ' '\n' | grep -v '^$' | sort -u)

  if [ -n "${pids}" ]; then
    echo "${CWARNING}These JVM processes are still using ${jh}:${CEND}"
    ps -fp $(echo ${pids} | tr '\n' ' ') 2>/dev/null | sed 1d
    if [ "${force_flag}" == 'y' ]; then
      echo "${CWARNING}--force specified, continue anyway${CEND}"
      return 0
    fi
    echo "${CFAILURE}Stop them first, or re-run with --force${CEND}"
    return 1
  fi
  return 0
}

Uninstall_OpenJDK() {
  local ver=$1
  local jh=$(Detect_JAVA_HOME ${ver})
  [ -z "${jh}" ] && { echo "${CWARNING}OpenJDK ${ver} is not installed${CEND}"; return 0; }

  Check_JDK_InUse "${jh}" || return 1

  local was_default=0
  [ "$(readlink -f ${jdk_link} 2>/dev/null)" == "$(readlink -f ${jh})" ] && was_default=1

  # 1. 注销 alternatives
  Unregister_Alternatives "${jh}"

  # 2. 按安装方式卸载
  if [[ "${jh}" == ${jdk_base_dir}/jdk-* ]]; then
    Uninstall_JDK_Binary ${ver}
  else
    Uninstall_JDK_Package ${ver}
    # 包管理器有时残留空目录
    [ -d "${jh}" ] && [ ! -x "${jh}/bin/java" ] && rm -rf "${jh}"
  fi

  # 3. 默认版本回退或彻底清理
  if [ ${was_default} -eq 1 ]; then
    local next_ver=$(List_JDK | awk 'NR==1{print $1}')
    if [ -n "${next_ver}" ]; then
      local next_home=$(Detect_JAVA_HOME ${next_ver})
      Set_JDK_Env "${next_home}" "${next_ver}"
      Register_Alternatives "${next_home}" "${next_ver}"
      Save_Option jdk_current_ver "${next_ver}"
      echo "${CMSG}Default JDK switched to ${next_ver} (${next_home})${CEND}"
    else
      Unset_JDK_Env
      Save_Option jdk_current_ver ""
    fi
  fi

  echo "${CMSG}OpenJDK ${ver} uninstall completed!${CEND}"
  return 0
}
