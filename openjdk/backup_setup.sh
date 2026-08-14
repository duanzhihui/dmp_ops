#!/bin/bash
# OpenJDK 备份策略配置向导
# 项目: dmp_ops/openjdk
# 用法: ./backup_setup.sh

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

openjdk_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

. "${openjdk_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${openjdk_dir}"
. "${openjdk_dir}/options.conf"
. "${openjdk_dir}/versions.txt"
. "${openjdk_dir}/include/color.sh"
. "${openjdk_dir}/include/check_os.sh"
. "${openjdk_dir}/include/check_env.sh"
. "${openjdk_dir}/include/jdk_env.sh"

Check_OS > /dev/null

echo ""
echo "${CMSG}#######################################################################${CEND}"
echo "${CMSG}#                OpenJDK Backup Setup Wizard                          #${CEND}"
echo "${CMSG}#######################################################################${CEND}"
echo ""

# ---------- 1. 备份内容 ----------
echo "${CMSG}Please select backup content (multiple choices, space separated):${CEND}"
echo -e "\t${CMSG}1${CEND}. cacerts  - certificate store (recommended)"
echo -e "\t${CMSG}2${CEND}. conf     - security & runtime config (recommended)"
echo -e "\t${CMSG}3${CEND}. jdk      - full JDK directory (large)"
while :; do
  read -e -p "Please input numbers:(Default '1 2' press Enter) " content_input
  content_input=${content_input:-"1 2"}
  if [[ ! "${content_input}" =~ ^[1-3\ ]+$ ]]; then
    echo "${CWARNING}input error! Please only input number 1~3${CEND}"
    continue
  fi
  new_content=""
  for i in ${content_input}; do
    case "${i}" in
      1) new_content="${new_content},cacerts" ;;
      2) new_content="${new_content},conf" ;;
      3) new_content="${new_content},jdk" ;;
    esac
  done
  new_content=$(echo "${new_content}" | sed 's@^,@@')
  [ -n "${new_content}" ] && break
done

# ---------- 2. 备份目标 ----------
echo ""
echo "${CMSG}Please select backup destination (multiple choices, space separated):${CEND}"
echo -e "\t${CMSG}1${CEND}. local  - local directory"
echo -e "\t${CMSG}2${CEND}. remote - remote server via rsync/ssh"
echo -e "\t${CMSG}3${CEND}. oss    - Aliyun OSS (ossutil)"
echo -e "\t${CMSG}4${CEND}. cos    - Tencent COS (coscli)"
echo -e "\t${CMSG}5${CEND}. s3     - AWS S3 (aws cli)"
while :; do
  read -e -p "Please input numbers:(Default 1 press Enter) " dest_input
  dest_input=${dest_input:-1}
  if [[ ! "${dest_input}" =~ ^[1-5\ ]+$ ]]; then
    echo "${CWARNING}input error! Please only input number 1~5${CEND}"
    continue
  fi
  new_dest=""
  for i in ${dest_input}; do
    case "${i}" in
      1) new_dest="${new_dest},local" ;;
      2) new_dest="${new_dest},remote" ;;
      3) new_dest="${new_dest},oss" ;;
      4) new_dest="${new_dest},cos" ;;
      5) new_dest="${new_dest},s3" ;;
    esac
  done
  new_dest=$(echo "${new_dest}" | sed 's@^,@@')
  [ -n "${new_dest}" ] && break
done

# ---------- 3. 备份目录与保留天数 ----------
echo ""
read -e -p "Backup directory (Default ${backup_dir}): " new_bkdir
new_bkdir=${new_bkdir:-${backup_dir}}
read -e -p "Expired days (Default ${expired_days}): " new_days
new_days=${new_days:-${expired_days}}
[[ ! "${new_days}" =~ ^[0-9]+$ ]] && new_days=${expired_days}

# ---------- 4. 各目标的凭证/参数 ----------
if [ -n "$(echo ${new_dest} | grep -ow remote)" ]; then
  echo ""
  echo "${CMSG}Remote backup configuration:${CEND}"
  read -e -p "Remote host: " new_rhost
  read -e -p "Remote ssh port (Default ${remote_port}): " new_rport
  new_rport=${new_rport:-${remote_port}}
  read -e -p "Remote user (Default ${remote_user}): " new_ruser
  new_ruser=${new_ruser:-${remote_user}}
  read -e -p "Remote directory: " new_rdir
  if [ -n "${new_rhost}" ] && [ -n "${new_rdir}" ]; then
    echo "Testing ssh connectivity..."
    ssh -p "${new_rport}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
      "${new_ruser}@${new_rhost}" "mkdir -p ${new_rdir} && echo ok" 2>/dev/null | grep -q ok \
      && echo "${CSUCCESS}Remote connectivity OK${CEND}" \
      || echo "${CWARNING}Remote connectivity failed, please configure ssh key first${CEND}"
  fi
fi

if [ -n "$(echo ${new_dest} | grep -ow oss)" ]; then
  echo ""
  read -e -p "OSS bucket name: " new_oss
  command -v ossutil > /dev/null 2>&1 || echo "${CWARNING}ossutil not installed: https://help.aliyun.com/document_detail/120075.html${CEND}"
  [ -n "${new_oss}" ] && { ossutil ls "oss://${new_oss}" > /dev/null 2>&1 \
    && echo "${CSUCCESS}OSS bucket accessible${CEND}" \
    || echo "${CWARNING}Cannot access oss://${new_oss}, please run 'ossutil config' first${CEND}"; }
fi

if [ -n "$(echo ${new_dest} | grep -ow cos)" ]; then
  echo ""
  read -e -p "COS bucket name: " new_cos
  command -v coscli > /dev/null 2>&1 || echo "${CWARNING}coscli not installed${CEND}"
fi

if [ -n "$(echo ${new_dest} | grep -ow s3)" ]; then
  echo ""
  read -e -p "S3 bucket name: " new_s3
  command -v aws > /dev/null 2>&1 || echo "${CWARNING}aws cli not installed${CEND}"
  [ -n "${new_s3}" ] && { aws s3 ls "s3://${new_s3}" > /dev/null 2>&1 \
    && echo "${CSUCCESS}S3 bucket accessible${CEND}" \
    || echo "${CWARNING}Cannot access s3://${new_s3}, please run 'aws configure' first${CEND}"; }
fi

# ---------- 5. 写入 options.conf ----------
Save_Option backup_content "${new_content}"
Save_Option backup_destination "${new_dest}"
Save_Option backup_dir "${new_bkdir}"
Save_Option expired_days "${new_days}"
[ -n "${new_rhost}" ] && Save_Option remote_host "${new_rhost}"
[ -n "${new_rport}" ] && Save_Option remote_port "${new_rport}"
[ -n "${new_ruser}" ] && Save_Option remote_user "${new_ruser}"
[ -n "${new_rdir}" ]  && Save_Option remote_dir "${new_rdir}"
[ -n "${new_oss}" ]   && Save_Option oss_bucket "${new_oss}"
[ -n "${new_cos}" ]   && Save_Option cos_bucket "${new_cos}"
[ -n "${new_s3}" ]    && Save_Option s3_bucket "${new_s3}"
mkdir -p "${new_bkdir}"

# ---------- 6. cron 定时任务 ----------
echo ""
read -e -p "Add a daily cron job for backup? [y/n]: (Default y press Enter) " cron_flag
cron_flag=${cron_flag:-y}
if [ "${cron_flag}" == 'y' ]; then
  read -e -p "Backup hour (0-23, Default 3): " bk_hour
  bk_hour=${bk_hour:-3}
  [[ ! "${bk_hour}" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] && bk_hour=3
  cron_line="0 ${bk_hour} * * * ${openjdk_dir}/backup.sh > /dev/null 2>&1"
  # 先去重再写入
  (crontab -l 2>/dev/null | grep -v "${openjdk_dir}/backup.sh"; echo "${cron_line}") | crontab -
  echo "${CSUCCESS}Cron job added:${CEND} ${cron_line}"
fi

echo ""
echo "${CMSG}=== Backup Configuration ===${CEND}"
echo "  Content     : ${new_content}"
echo "  Destination : ${new_dest}"
echo "  Directory   : ${new_bkdir}"
echo "  Expired Days: ${new_days}"
echo ""
echo "${CMSG}Run './backup.sh' to execute a backup immediately${CEND}"
