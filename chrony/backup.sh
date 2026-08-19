#!/bin/bash
# Chrony 配置备份执行脚本（由 cron 调用）
# 项目: dmp_ops/chrony
# 用法: ./backup.sh
# cron 示例: 0 3 * * * /opt/dmp_ops/chrony/backup.sh >> /var/log/chrony/backup.log 2>&1

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

script_dir=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}"
. "${script_dir}/options.conf"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/check_os.sh"
. "${script_dir}/include/chrony_config.sh"

Check_OS > /dev/null 2>&1
[ -z "${chrony_conf}" ] && Detect_Chrony_Path

BK_NAME="chrony_$(hostname)_$(date +%Y%m%d_%H%M%S).tgz"

# 本地备份
Conf_Local_BK() {
  mkdir -p "${backup_dir}"

  local files=""
  for f in "${chrony_conf}" "${chrony_keys}" "${drift_file}" /var/lib/chrony/rtc; do
    [ -f "${f}" ] && files="${files} ${f}"
  done

  if [ -z "${files}" ]; then
    echo "${CFAILURE}没有可备份的文件${CEND}"
    return 1
  fi

  tar czf "${backup_dir}/${BK_NAME}" ${files} 2>/dev/null
  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}[$(date '+%F %T')] 备份成功: ${backup_dir}/${BK_NAME}${CEND}"
  else
    echo "${CFAILURE}[$(date '+%F %T')] 备份失败${CEND}"
    return 1
  fi

  # 过期清理
  local old_pattern="${backup_dir}/chrony_$(hostname)_$(date +%Y%m%d --date="${expired_days} days ago")*.tgz"
  if [ -n "$(ls ${old_pattern} 2>/dev/null)" ]; then
    rm -f ${old_pattern}
    echo "${CMSG}已清理 ${expired_days} 天前的备份${CEND}"
  fi
  # 兜底：按修改时间清理超期文件
  find "${backup_dir}" -name "chrony_$(hostname)_*.tgz" -mtime +"${expired_days}" -delete 2>/dev/null
  return 0
}

# 远程备份（scp 到远端主机）
Conf_Remote_BK() {
  if [ -z "${remote_host}" ]; then
    echo "${CFAILURE}未配置 remote_host，跳过远程备份${CEND}"
    return 1
  fi
  [ -f "${backup_dir}/${BK_NAME}" ] || Conf_Local_BK || return 1

  ssh -p "${remote_port}" -o StrictHostKeyChecking=no -o BatchMode=yes \
      "${remote_user}@${remote_host}" "mkdir -p ${remote_dir_backup}" 2>/dev/null
  scp -P "${remote_port}" -o StrictHostKeyChecking=no -o BatchMode=yes -q \
      "${backup_dir}/${BK_NAME}" "${remote_user}@${remote_host}:${remote_dir_backup}/"

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}远程备份成功: ${remote_user}@${remote_host}:${remote_dir_backup}/${BK_NAME}${CEND}"
    # 远端过期清理
    ssh -p "${remote_port}" -o StrictHostKeyChecking=no -o BatchMode=yes \
        "${remote_user}@${remote_host}" \
        "find ${remote_dir_backup} -name 'chrony_$(hostname)_*.tgz' -mtime +${expired_days} -delete" 2>/dev/null
    # 不保留本地副本时删除
    [ -z "$(echo ${backup_destination} | grep -ow 'local')" ] && rm -f "${backup_dir}/${BK_NAME}"
    return 0
  fi

  echo "${CFAILURE}远程备份失败${CEND}"
  return 1
}

main() {
  if [ -z "$(echo ${backup_content} | grep -ow conf)" ]; then
    echo "${CWARNING}backup_content 未包含 conf，无需备份${CEND}"
    exit 0
  fi

  local rc=0
  for DEST in $(echo "${backup_destination}" | tr ',' ' '); do
    case "${DEST}" in
      local)  Conf_Local_BK  || rc=1 ;;
      remote) Conf_Remote_BK || rc=1 ;;
      *)      echo "${CWARNING}未知的备份目标: ${DEST}${CEND}" ;;
    esac
  done
  exit ${rc}
}

main
