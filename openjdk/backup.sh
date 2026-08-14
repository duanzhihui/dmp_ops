#!/bin/bash
# OpenJDK 备份执行脚本(由 cron 调用)
# 项目: dmp_ops/openjdk
#
# 备份对象为 JDK 的"配置态资产":
#   cacerts — 证书库(企业自签 CA，重装必丢)
#   conf    — 安全与运行配置(java.security/java.policy/net.properties)
#   jdk     — 完整 JDK 目录(离线复原用)
# 同时生成已装 JDK 清单，便于灾备重建

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

openjdk_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
src_dir="${openjdk_dir}/src"

# Root 检查(--help 除外)
if [[ ! "$1" =~ ^-h$|^--help$ ]]; then
  [ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }
fi

. "${openjdk_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${openjdk_dir}"
. "${openjdk_dir}/options.conf"
. "${openjdk_dir}/versions.txt"
. "${openjdk_dir}/include/color.sh"
. "${openjdk_dir}/include/check_os.sh"
. "${openjdk_dir}/include/check_env.sh"
. "${openjdk_dir}/include/jdk_env.sh"

Check_OS > /dev/null
mkdir -p "${backup_dir}" "${log_dir}"

BK_LOG="${log_dir}/backup.log"
Log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${BK_LOG}"; }

# 待备份版本: 未指定则取当前默认版本，无默认则取全部已装
Get_Backup_Vers() {
  if [ -n "$1" ]; then
    echo "$1"
  elif [ -n "${jdk_current_ver}" ]; then
    echo "${jdk_current_ver}"
  else
    List_JDK | awk '{print $1}'
  fi
}

# ---------- 本地备份 ----------
JDK_Local_BK() {
  local ver=$1
  local jh=$(Detect_JAVA_HOME ${ver})
  [ -z "${jh}" ] && { Log "OpenJDK ${ver} not installed, skip"; return 1; }

  local stamp=$(date +%Y%m%d_%H%M%S)
  local tar_dirs=""

  if [ -n "$(echo ${backup_content} | grep -ow cacerts)" ]; then
    [ -f "${jh}/lib/security/cacerts" ] && tar_dirs="${tar_dirs} lib/security/cacerts"
    [ -f "${jh}/jre/lib/security/cacerts" ] && tar_dirs="${tar_dirs} jre/lib/security/cacerts"
  fi
  if [ -n "$(echo ${backup_content} | grep -ow conf)" ]; then
    [ -d "${jh}/conf" ] && tar_dirs="${tar_dirs} conf"
    [ -d "${jh}/lib/security" ] && tar_dirs="${tar_dirs} lib/security"
    [ -d "${jh}/jre/lib/security" ] && tar_dirs="${tar_dirs} jre/lib/security"
  fi

  # 去重
  tar_dirs=$(echo ${tar_dirs} | tr ' ' '\n' | sort -u | tr '\n' ' ')

  if [ -n "${tar_dirs}" ]; then
    BK_FILE="JDK_${ver}_conf_${stamp}.tgz"
    tar czf "${backup_dir}/${BK_FILE}" -C "${jh}" ${tar_dirs} 2>/dev/null
    [ $? -eq 0 ] && Log "backup OK: ${backup_dir}/${BK_FILE}" || Log "backup FAILED: ${BK_FILE}"
  fi

  # 完整 JDK 目录
  if [ -n "$(echo ${backup_content} | grep -ow jdk)" ]; then
    BK_FULL="JDK_${ver}_full_${stamp}.tgz"
    tar czf "${backup_dir}/${BK_FULL}" -C "$(dirname ${jh})" "$(basename ${jh})" 2>/dev/null
    [ $? -eq 0 ] && Log "backup OK: ${backup_dir}/${BK_FULL}" || Log "backup FAILED: ${BK_FULL}"
  fi

  # 环境配置与已装清单
  [ -f "/etc/profile.d/openjdk.sh" ] && \
    /bin/cp -f /etc/profile.d/openjdk.sh "${backup_dir}/openjdk.sh.${stamp}"
  List_JDK > "${backup_dir}/JDK_installed_$(date +%Y%m%d).list"

  # 过期清理
  local OldFile="${backup_dir}/JDK_${ver}_*_$(date +%Y%m%d --date="${expired_days} days ago")_*.tgz"
  [ -n "$(ls ${OldFile} 2>/dev/null)" ] && { rm -f ${OldFile}; Log "removed expired backups: ${OldFile}"; }
  find "${backup_dir}" -maxdepth 1 -name 'openjdk.sh.*' -mtime +${expired_days} -delete 2>/dev/null
  find "${backup_dir}" -maxdepth 1 -name 'JDK_installed_*.list' -mtime +${expired_days} -delete 2>/dev/null
  return 0
}

# ---------- 远程备份(rsync over ssh) ----------
JDK_Remote_BK() {
  local ver=$1
  JDK_Local_BK ${ver} || return 1
  [ -z "${remote_host}" -o -z "${remote_dir}" ] && { Log "remote_host/remote_dir not configured"; return 1; }
  local f
  for f in "${backup_dir}"/JDK_${ver}_*_$(date +%Y%m%d)_*.tgz; do
    [ -f "${f}" ] || continue
    rsync -avz -e "ssh -p ${remote_port} -o StrictHostKeyChecking=no" "${f}" \
      "${remote_user}@${remote_host}:${remote_dir}/" > /dev/null 2>&1
    [ $? -eq 0 ] && Log "remote upload OK: $(basename ${f})" || Log "remote upload FAILED: $(basename ${f})"
  done
}

# ---------- 阿里云 OSS ----------
JDK_OSS_BK() {
  local ver=$1
  command -v ossutil > /dev/null 2>&1 || { Log "ossutil not found"; return 1; }
  [ -z "${oss_bucket}" ] && { Log "oss_bucket not configured"; return 1; }
  JDK_Local_BK ${ver} || return 1
  local f
  for f in "${backup_dir}"/JDK_${ver}_*_$(date +%Y%m%d)_*.tgz; do
    [ -f "${f}" ] || continue
    ossutil cp -f "${f}" "oss://${oss_bucket}/$(date +%F)/$(basename ${f})" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      Log "OSS upload OK: $(basename ${f})"
      ossutil rm -rf "oss://${oss_bucket}/$(date +%F --date="${expired_days} days ago")/" > /dev/null 2>&1
      [ -z "$(echo ${backup_destination} | grep -ow local)" ] && rm -f "${f}"
    else
      Log "OSS upload FAILED: $(basename ${f})"
    fi
  done
}

# ---------- 腾讯云 COS ----------
JDK_COS_BK() {
  local ver=$1
  command -v coscli > /dev/null 2>&1 || { Log "coscli not found"; return 1; }
  [ -z "${cos_bucket}" ] && { Log "cos_bucket not configured"; return 1; }
  JDK_Local_BK ${ver} || return 1
  local f
  for f in "${backup_dir}"/JDK_${ver}_*_$(date +%Y%m%d)_*.tgz; do
    [ -f "${f}" ] || continue
    coscli cp "${f}" "cos://${cos_bucket}/$(date +%F)/$(basename ${f})" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      Log "COS upload OK: $(basename ${f})"
      [ -z "$(echo ${backup_destination} | grep -ow local)" ] && rm -f "${f}"
    else
      Log "COS upload FAILED: $(basename ${f})"
    fi
  done
}

# ---------- AWS S3 ----------
JDK_S3_BK() {
  local ver=$1
  command -v aws > /dev/null 2>&1 || { Log "aws cli not found"; return 1; }
  [ -z "${s3_bucket}" ] && { Log "s3_bucket not configured"; return 1; }
  JDK_Local_BK ${ver} || return 1
  local f
  for f in "${backup_dir}"/JDK_${ver}_*_$(date +%Y%m%d)_*.tgz; do
    [ -f "${f}" ] || continue
    aws s3 cp "${f}" "s3://${s3_bucket}/$(date +%F)/$(basename ${f})" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      Log "S3 upload OK: $(basename ${f})"
      aws s3 rm --recursive "s3://${s3_bucket}/$(date +%F --date="${expired_days} days ago")/" > /dev/null 2>&1
      [ -z "$(echo ${backup_destination} | grep -ow local)" ] && rm -f "${f}"
    else
      Log "S3 upload FAILED: $(basename ${f})"
    fi
  done
}

main() {
  [ -z "${backup_destination}" ] && {
    echo "${CWARNING}backup_destination is empty, run ./backup_setup.sh first${CEND}"
    exit 1
  }
  [ -z "${backup_content}" ] && {
    echo "${CWARNING}backup_content is empty, run ./backup_setup.sh first${CEND}"
    exit 1
  }

  Log "===== backup start (dest=${backup_destination} content=${backup_content}) ====="
  local ver dest
  for ver in $(Get_Backup_Vers "$1"); do
    for dest in $(echo ${backup_destination} | tr ',' ' '); do
      case "${dest}" in
        local)  JDK_Local_BK ${ver} ;;
        remote) JDK_Remote_BK ${ver} ;;
        oss)    JDK_OSS_BK ${ver} ;;
        cos)    JDK_COS_BK ${ver} ;;
        s3)     JDK_S3_BK ${ver} ;;
        *)      Log "unknown backup destination: ${dest}" ;;
      esac
    done
  done
  Log "===== backup finished ====="
}

main "$@"
