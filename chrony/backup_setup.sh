#!/bin/bash
# Chrony 备份策略配置向导
# 项目: dmp_ops/chrony
# 用法: ./backup_setup.sh

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

script_dir=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}"
. "${script_dir}/options.conf"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/get_char.sh"
. "${script_dir}/include/chrony_config.sh"

echo ""
echo "${CMSG}#####################################################################${CEND}"
echo "${CMSG}#                  Chrony 备份策略配置向导                          #${CEND}"
echo "${CMSG}#####################################################################${CEND}"
echo ""
echo "备份内容: chrony.conf / chrony.keys / drift 文件 / rtc 文件"
echo ""

# 1. 备份目标
echo "${CMSG}请选择备份目标（可多选，逗号分隔）:${CEND}"
echo "  1) local   本地目录"
echo "  2) remote  远程主机（scp，需 SSH 免密）"
echo "  3) local,remote  两者都要"
while :; do
  read -e -p "请输入选择 [1-3, 默认: 1]: " c
  c=${c:-1}
  case "${c}" in
    1) backup_destination=local; break ;;
    2) backup_destination=remote; break ;;
    3) backup_destination=local,remote; break ;;
    *) echo "${CWARNING}输入无效${CEND}" ;;
  esac
done

# 2. 本地备份目录
read -e -p "本地备份目录 [默认: ${backup_dir}]: " tmp
[ -n "${tmp}" ] && backup_dir="${tmp}"
mkdir -p "${backup_dir}"

# 3. 保留天数
read -e -p "备份保留天数 [默认: ${expired_days}]: " tmp
[ -n "${tmp}" ] && expired_days="${tmp}"

# 4. 远程配置
if [ -n "$(echo ${backup_destination} | grep -ow remote)" ]; then
  echo ""
  echo "${CMSG}远程备份配置:${CEND}"
  read -e -p "  远程主机地址: " remote_host
  read -e -p "  远程 SSH 端口 [默认: ${remote_port}]: " tmp
  [ -n "${tmp}" ] && remote_port="${tmp}"
  read -e -p "  远程用户 [默认: ${remote_user}]: " tmp
  [ -n "${tmp}" ] && remote_user="${tmp}"
  read -e -p "  远程备份目录 [默认: ${remote_dir_backup}]: " tmp
  [ -n "${tmp}" ] && remote_dir_backup="${tmp}"

  echo ""
  echo "${CMSG}测试远程连通性 ...${CEND}"
  if ssh -p "${remote_port}" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=8 \
        "${remote_user}@${remote_host}" "mkdir -p ${remote_dir_backup} && echo ok" 2>/dev/null | grep -q ok; then
    echo "${CSUCCESS}[OK] 远程主机可达且目录可写${CEND}"
  else
    echo "${CWARNING}[WARN] 远程连通性测试失败，请确认已建立 SSH 免密:${CEND}"
    echo "${CWARNING}  ${script_dir}/../sshtrust/sshtrust.sh --add ${remote_user}@${remote_host}${CEND}"
  fi
fi

# 5. 持久化
Set_Option backup_destination "${backup_destination}"
Set_Option backup_content conf
Set_Option backup_dir "${backup_dir}"
Set_Option expired_days "${expired_days}"
Set_Option remote_host "${remote_host}"
Set_Option remote_port "${remote_port}"
Set_Option remote_user "${remote_user}"
Set_Option remote_dir_backup "${remote_dir_backup}"

# 6. cron 定时任务
echo ""
read -e -p "备份执行时间（cron 表达式）[默认: 0 3 * * *]: " cron_expr
cron_expr=${cron_expr:-"0 3 * * *"}

cron_line="${cron_expr} ${script_dir}/backup.sh >> ${log_dir}/backup.log 2>&1"
tmp_cron=$(mktemp)
crontab -l 2>/dev/null | grep -v "${script_dir}/backup.sh" > "${tmp_cron}"
echo "${cron_line}" >> "${tmp_cron}"
crontab "${tmp_cron}"
rm -f "${tmp_cron}"
mkdir -p "${log_dir}"

echo ""
echo "${CSUCCESS}=== 备份策略配置完成 ===${CEND}"
echo "  备份目标  : ${backup_destination}"
echo "  本地目录  : ${backup_dir}"
echo "  保留天数  : ${expired_days}"
[ -n "$(echo ${backup_destination} | grep -ow remote)" ] && \
  echo "  远程目标  : ${remote_user}@${remote_host}:${remote_dir_backup}"
echo "  定时任务  : ${cron_line}"
echo ""
echo "${CMSG}可立即执行一次验证: ${script_dir}/backup.sh${CEND}"
