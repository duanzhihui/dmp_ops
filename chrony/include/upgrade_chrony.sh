#!/bin/bash
# chrony 升级模块
# 项目: dmp_ops/chrony
# 核心函数: Get_Chrony_Version / Upgrade_Chrony

# 获取当前安装版本
Get_Chrony_Version() {
  command -v chronyd > /dev/null 2>&1 || return 1
  chronyd -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

# 升级前备份：配置 + drift + keys
# drift 文件丢失后 chrony 需要重新学习时钟漂移（数小时），必须备份
Backup_Before_Upgrade() {
  upgrade_bk="/tmp/chrony_upgrade_$(date +%Y%m%d%H%M%S)"
  mkdir -p "${upgrade_bk}"
  [ -f "${chrony_conf}" ] && /bin/cp -p "${chrony_conf}" "${upgrade_bk}/"
  [ -f "${chrony_keys}" ] && /bin/cp -p "${chrony_keys}" "${upgrade_bk}/"
  [ -f "${drift_file}" ]  && /bin/cp -p "${drift_file}"  "${upgrade_bk}/"
  echo "${CMSG}升级前备份已保存到 ${upgrade_bk}${CEND}"
}

Upgrade_Chrony() {
  Detect_Chrony_Path

  local OLD_ver
  OLD_ver=$(Get_Chrony_Version)
  if [ -z "${OLD_ver}" ]; then
    echo "${CWARNING}Chrony 未安装，请先执行 ./install.sh${CEND}"
    exit 1
  fi
  echo "当前版本: ${CMSG}${OLD_ver}${CEND}"

  # 1. 升级前备份
  Backup_Before_Upgrade

  # 2. 执行升级
  if [ "${install_method}" == 'package' ]; then
    echo "${CMSG}使用包管理器升级 chrony ...${CEND}"
    case "${PM}" in
      yum|dnf)
        ${PM} -y update chrony
        ;;
      apt-get)
        DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade chrony
        ;;
    esac
  else
    local NEW_ver="${target_ver:-${chrony_ver}}"
    if [ "${NEW_ver}" == "${OLD_ver}" ]; then
      echo "${CWARNING}目标版本与当前版本相同 (${OLD_ver})，无需升级${CEND}"
      exit 0
    fi
    echo "${CMSG}源码升级: ${OLD_ver} -> ${NEW_ver}${CEND}"
    chrony_ver="${NEW_ver}"
    systemctl stop "${chrony_service}" > /dev/null 2>&1
    Install_Chrony_Source || {
      echo "${CFAILURE}源码升级失败，备份位于 ${upgrade_bk}${CEND}"
      exit 1
    }
    sed -i "s@^chrony_ver=.*@chrony_ver=${NEW_ver}@" "${script_dir}/versions.txt"
  fi

  # 3. 恢复被软件包覆盖的配置
  local conf_name
  conf_name=$(basename "${chrony_conf}")
  if [ -f "${upgrade_bk}/${conf_name}" ]; then
    /bin/cp -p "${upgrade_bk}/${conf_name}" "${chrony_conf}"
    echo "${CMSG}已恢复升级前的 ${chrony_conf}${CEND}"
  fi
  [ -f "${upgrade_bk}/$(basename ${drift_file})" ] && \
    /bin/cp -p "${upgrade_bk}/$(basename ${drift_file})" "${drift_file}" 2>/dev/null

  # 4. 重启并验证
  systemctl restart "${chrony_service}" > /dev/null 2>&1
  sleep 3

  local NEW_ver_actual
  NEW_ver_actual=$(Get_Chrony_Version)

  if systemctl is-active --quiet "${chrony_service}" && chronyc tracking > /dev/null 2>&1; then
    if [ "${NEW_ver_actual}" == "${OLD_ver}" ]; then
      echo "${CWARNING}版本未变化 (${OLD_ver})，仓库中可能已是最新版本${CEND}"
    else
      echo "${CSUCCESS}升级成功: ${OLD_ver} -> ${NEW_ver_actual}${CEND}"
    fi
    echo ""
    chronyc tracking 2>/dev/null | head -6
    return 0
  fi

  echo "${CFAILURE}升级后服务异常！${CEND}"
  journalctl -u "${chrony_service}" -n 30 --no-pager 2>/dev/null
  echo "${CWARNING}请使用备份手动回滚: ${upgrade_bk}${CEND}"
  exit 1
}
