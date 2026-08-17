#!/bin/bash
# ZooKeeper 备份配置向导
# 项目: oneinstack/zookeeper
# 用法: ./backup_setup.sh

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本目录
script_dir=$(cd "$(dirname "$0")" && pwd)

# Root 检查
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# 加载配置
. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}"
. "${script_dir}/options.conf"
. "${script_dir}/include/color.sh"

echo ""
echo "${CMSG}#######################################################################${CEND}"
echo "${CMSG}#                  ZooKeeper Backup Configuration                    #${CEND}"
echo "${CMSG}#######################################################################${CEND}"
echo ""

# 1. 选择备份目标
echo "${CMSG}Step 1: Select backup destination${CEND}"
echo "  1) Local storage only"
echo "  2) Aliyun OSS"
echo "  3) AWS S3"
echo "  4) Local + OSS"
echo "  5) Local + S3"
echo ""

while :; do
  read -e -p "Enter your choice [1-5, default: 1]: " dest_choice
  dest_choice=${dest_choice:-1}
  case "${dest_choice}" in
    1)
      backup_destination="local"
      break
      ;;
    2)
      backup_destination="oss"
      break
      ;;
    3)
      backup_destination="s3"
      break
      ;;
    4)
      backup_destination="local,oss"
      break
      ;;
    5)
      backup_destination="local,s3"
      break
      ;;
    *)
      echo "${CWARNING}Invalid choice${CEND}"
      ;;
  esac
done

echo "Selected: ${backup_destination}"
echo ""

# 2. 配置本地备份目录
echo "${CMSG}Step 2: Configure local backup directory${CEND}"
read -e -p "Backup directory [${backup_dir}]: " new_backup_dir
backup_dir=${new_backup_dir:-${backup_dir}}
mkdir -p "${backup_dir}"
echo "Backup directory: ${backup_dir}"
echo ""

# 3. 配置过期天数
echo "${CMSG}Step 3: Configure retention period${CEND}"
read -e -p "Keep backups for how many days [${expired_days}]: " new_expired_days
expired_days=${new_expired_days:-${expired_days}}
echo "Retention: ${expired_days} days"
echo ""

# 4. 配置云存储（如果选择）
if [[ "${backup_destination}" == *"oss"* ]]; then
  echo "${CMSG}Step 4: Configure Aliyun OSS${CEND}"
  read -e -p "OSS Bucket name: " oss_bucket
  
  if [ -n "${oss_bucket}" ]; then
    # 测试连接
    if command -v ossutil &> /dev/null; then
      echo "Testing OSS connection..."
      if ossutil ls "oss://${oss_bucket}/" &>/dev/null; then
        echo "${CSUCCESS}OSS connection successful${CEND}"
      else
        echo "${CWARNING}OSS connection failed. Please check your credentials.${CEND}"
      fi
    else
      echo "${CWARNING}ossutil not installed. Please install it before using OSS backup.${CEND}"
    fi
  fi
  echo ""
fi

if [[ "${backup_destination}" == *"s3"* ]]; then
  echo "${CMSG}Step 4: Configure AWS S3${CEND}"
  read -e -p "S3 Bucket name: " s3_bucket
  
  if [ -n "${s3_bucket}" ]; then
    # 测试连接
    if command -v aws &> /dev/null; then
      echo "Testing S3 connection..."
      if aws s3 ls "s3://${s3_bucket}/" &>/dev/null; then
        echo "${CSUCCESS}S3 connection successful${CEND}"
      else
        echo "${CWARNING}S3 connection failed. Please check your credentials.${CEND}"
      fi
    else
      echo "${CWARNING}AWS CLI not installed. Please install it before using S3 backup.${CEND}"
    fi
  fi
  echo ""
fi

# 5. 配置告警
echo "${CMSG}Step 5: Configure alerts (optional)${CEND}"
read -e -p "Alert email (leave empty to skip): " alert_email
read -e -p "Webhook URL (leave empty to skip): " webhook_url
echo ""

# 6. 配置定时任务
echo "${CMSG}Step 6: Configure scheduled backup${CEND}"
echo "  1) Daily at 2:00 AM"
echo "  2) Daily at 3:00 AM"
echo "  3) Every 12 hours"
echo "  4) Custom"
echo "  5) Skip (manual backup only)"
echo ""

while :; do
  read -e -p "Enter your choice [1-5, default: 1]: " cron_choice
  cron_choice=${cron_choice:-1}
  case "${cron_choice}" in
    1)
      cron_schedule="0 2 * * *"
      break
      ;;
    2)
      cron_schedule="0 3 * * *"
      break
      ;;
    3)
      cron_schedule="0 */12 * * *"
      break
      ;;
    4)
      read -e -p "Enter cron schedule (e.g., '0 2 * * *'): " cron_schedule
      break
      ;;
    5)
      cron_schedule=""
      break
      ;;
    *)
      echo "${CWARNING}Invalid choice${CEND}"
      ;;
  esac
done

# 7. 保存配置
echo ""
echo "${CMSG}Saving configuration...${CEND}"

sed -i "s@^backup_dir=.*@backup_dir=${backup_dir}@" "${script_dir}/options.conf"
sed -i "s@^expired_days=.*@expired_days=${expired_days}@" "${script_dir}/options.conf"
sed -i "s@^backup_destination=.*@backup_destination=${backup_destination}@" "${script_dir}/options.conf"
sed -i "s@^oss_bucket=.*@oss_bucket=${oss_bucket}@" "${script_dir}/options.conf"
sed -i "s@^s3_bucket=.*@s3_bucket=${s3_bucket}@" "${script_dir}/options.conf"
sed -i "s@^alert_email=.*@alert_email=${alert_email}@" "${script_dir}/options.conf"
sed -i "s@^webhook_url=.*@webhook_url=${webhook_url}@" "${script_dir}/options.conf"

echo "${CSUCCESS}Configuration saved to options.conf${CEND}"

# 8. 设置 cron
if [ -n "${cron_schedule}" ]; then
  echo ""
  echo "${CMSG}Setting up cron job...${CEND}"
  
  # 移除旧的 cron 任务
  crontab -l 2>/dev/null | grep -v "${script_dir}/backup.sh" > /tmp/crontab.tmp
  
  # 添加新的 cron 任务
  echo "${cron_schedule} ${script_dir}/backup.sh >> ${backup_dir}/backup.log 2>&1" >> /tmp/crontab.tmp
  
  crontab /tmp/crontab.tmp
  rm -f /tmp/crontab.tmp
  
  echo "${CSUCCESS}Cron job configured: ${cron_schedule}${CEND}"
fi

# 9. 显示摘要
echo ""
echo "${CMSG}=== Backup Configuration Summary ===${CEND}"
echo "  Destination: ${backup_destination}"
echo "  Local Dir: ${backup_dir}"
echo "  Retention: ${expired_days} days"
[ -n "${oss_bucket}" ] && echo "  OSS Bucket: ${oss_bucket}"
[ -n "${s3_bucket}" ] && echo "  S3 Bucket: ${s3_bucket}"
[ -n "${alert_email}" ] && echo "  Alert Email: ${alert_email}"
[ -n "${cron_schedule}" ] && echo "  Schedule: ${cron_schedule}"
echo ""
echo "${CSUCCESS}Backup configuration complete!${CEND}"
echo ""
echo "To run a manual backup: ${script_dir}/backup.sh"
