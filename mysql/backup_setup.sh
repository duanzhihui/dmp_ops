#!/bin/bash
# MySQL 备份配置向导
# Author: DMP OPS
#
# 说明: 交互式配置备份策略，设置 cron 定时任务

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear

printf "
#######################################################################
#                   MySQL Backup Setup Wizard                         #
#                         DMP OPS Project                             #
#######################################################################
"

# 获取脚本所在目录
mysql_dir=$(dirname "$(readlink -f $0)")
pushd ${mysql_dir} > /dev/null

# Root 检查
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# 加载配置
. ./options.conf
. ./include/color.sh
. ./include/check_dir.sh

# 检测 MySQL 是否安装
if [ ! -d "${db_install_dir}/support-files" ]; then
  echo "${CFAILURE}MySQL is not installed on this system.${CEND}"
  exit 1
fi

echo ""
echo "${CMSG}MySQL Backup Configuration Wizard${CEND}"
echo ""

# 1. 选择要备份的数据库
echo "Step 1: Select databases to backup"
echo ""

# 获取数据库列表
db_list=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW DATABASES" 2>/dev/null | grep -Ev "^(information_schema|performance_schema|mysql|sys)$")

if [ -z "${db_list}" ]; then
  echo "${CWARNING}No user databases found.${CEND}"
  read -e -p "Enter database names to backup (comma separated): " db_name
else
  echo "Available databases:"
  echo ""
  i=1
  for db in ${db_list}; do
    echo "  ${i}. ${db}"
    ((i++))
  done
  echo "  a. All databases"
  echo ""
  
  read -e -p "Enter database numbers (comma separated) or 'a' for all: " db_choice
  
  if [ "${db_choice}" == "a" ]; then
    db_name=$(echo ${db_list} | tr ' ' ',')
  else
    db_name=""
    for num in $(echo ${db_choice} | tr ',' ' '); do
      db=$(echo ${db_list} | awk -v n=${num} '{print $n}')
      [ -n "${db}" ] && db_name="${db_name},${db}"
    done
    db_name=${db_name#,}
  fi
fi

echo ""
echo "Selected databases: ${CMSG}${db_name}${CEND}"
echo ""

# 2. 选择备份目标
echo "Step 2: Select backup destination"
echo ""
echo "  1. Local only"
echo "  2. Local + Remote (rsync/scp)"
echo "  3. Local + Aliyun OSS"
echo "  4. Local + Tencent COS"
echo "  5. Local + AWS S3"
echo ""

read -e -p "Enter your choice [1-5]: " dest_choice

case "${dest_choice}" in
  1)
    backup_destination="local"
    ;;
  2)
    backup_destination="local,remote"
    echo ""
    read -e -p "Remote host: " remote_host
    read -e -p "Remote port [22]: " remote_port
    remote_port=${remote_port:-22}
    read -e -p "Remote user [root]: " remote_user
    remote_user=${remote_user:-root}
    read -e -p "Remote directory [/data/backup]: " remote_dir
    remote_dir=${remote_dir:-/data/backup}
    ;;
  3)
    backup_destination="local,oss"
    echo ""
    read -e -p "OSS Endpoint: " oss_endpoint
    read -e -p "OSS Bucket: " oss_bucket
    read -e -p "OSS Access Key ID: " oss_access_key_id
    read -e -p "OSS Access Key Secret: " oss_access_key_secret
    ;;
  4)
    backup_destination="local,cos"
    echo ""
    read -e -p "COS Region: " cos_region
    read -e -p "COS Bucket: " cos_bucket
    read -e -p "COS Secret ID: " cos_secret_id
    read -e -p "COS Secret Key: " cos_secret_key
    ;;
  5)
    backup_destination="local,s3"
    echo ""
    read -e -p "S3 Region: " s3_region
    read -e -p "S3 Bucket: " s3_bucket
    read -e -p "S3 Access Key: " s3_access_key
    read -e -p "S3 Secret Key: " s3_secret_key
    ;;
  *)
    backup_destination="local"
    ;;
esac

echo ""
echo "Backup destination: ${CMSG}${backup_destination}${CEND}"
echo ""

# 3. 设置备份保留天数
echo "Step 3: Set backup retention"
echo ""
read -e -p "Backup retention days [5]: " expired_days
expired_days=${expired_days:-5}
echo ""

# 4. 设置备份目录
echo "Step 4: Set backup directory"
echo ""
read -e -p "Backup directory [/data/backup]: " backup_dir
backup_dir=${backup_dir:-/data/backup}
[ ! -d "${backup_dir}" ] && mkdir -p ${backup_dir}
echo ""

# 5. 设置定时任务
echo "Step 5: Set backup schedule"
echo ""
echo "  1. Daily at 2:00 AM"
echo "  2. Daily at 3:00 AM"
echo "  3. Every 6 hours"
echo "  4. Every 12 hours"
echo "  5. Custom"
echo "  6. Skip (manual backup only)"
echo ""

read -e -p "Enter your choice [1-6]: " schedule_choice

case "${schedule_choice}" in
  1)
    cron_schedule="0 2 * * *"
    ;;
  2)
    cron_schedule="0 3 * * *"
    ;;
  3)
    cron_schedule="0 */6 * * *"
    ;;
  4)
    cron_schedule="0 */12 * * *"
    ;;
  5)
    read -e -p "Enter cron expression (e.g., '0 2 * * *'): " cron_schedule
    ;;
  6)
    cron_schedule=""
    ;;
  *)
    cron_schedule="0 2 * * *"
    ;;
esac

# 6. 保存配置
echo ""
echo "${CMSG}Saving configuration...${CEND}"

# 更新 options.conf
sed -i "s@^backup_dir=.*@backup_dir=${backup_dir}@" ./options.conf
sed -i "s@^expired_days=.*@expired_days=${expired_days}@" ./options.conf
sed -i "s@^backup_destination=.*@backup_destination=${backup_destination}@" ./options.conf
sed -i "s@^db_name=.*@db_name=${db_name}@" ./options.conf

# 更新远程备份配置
if [ "${dest_choice}" == "2" ]; then
  sed -i "s@^remote_host=.*@remote_host=${remote_host}@" ./options.conf
  sed -i "s@^remote_port=.*@remote_port=${remote_port}@" ./options.conf
  sed -i "s@^remote_user=.*@remote_user=${remote_user}@" ./options.conf
  sed -i "s@^remote_dir=.*@remote_dir=${remote_dir}@" ./options.conf
fi

# 更新 OSS 配置
if [ "${dest_choice}" == "3" ]; then
  sed -i "s@^oss_endpoint=.*@oss_endpoint=${oss_endpoint}@" ./options.conf
  sed -i "s@^oss_bucket=.*@oss_bucket=${oss_bucket}@" ./options.conf
  sed -i "s@^oss_access_key_id=.*@oss_access_key_id=${oss_access_key_id}@" ./options.conf
  sed -i "s@^oss_access_key_secret=.*@oss_access_key_secret=${oss_access_key_secret}@" ./options.conf
fi

# 更新 COS 配置
if [ "${dest_choice}" == "4" ]; then
  sed -i "s@^cos_region=.*@cos_region=${cos_region}@" ./options.conf
  sed -i "s@^cos_bucket=.*@cos_bucket=${cos_bucket}@" ./options.conf
  sed -i "s@^cos_secret_id=.*@cos_secret_id=${cos_secret_id}@" ./options.conf
  sed -i "s@^cos_secret_key=.*@cos_secret_key=${cos_secret_key}@" ./options.conf
fi

# 更新 S3 配置
if [ "${dest_choice}" == "5" ]; then
  sed -i "s@^s3_region=.*@s3_region=${s3_region}@" ./options.conf
  sed -i "s@^s3_bucket=.*@s3_bucket=${s3_bucket}@" ./options.conf
  sed -i "s@^s3_access_key=.*@s3_access_key=${s3_access_key}@" ./options.conf
  sed -i "s@^s3_secret_key=.*@s3_secret_key=${s3_secret_key}@" ./options.conf
fi

# 7. 设置 cron 任务
if [ -n "${cron_schedule}" ]; then
  echo "${CMSG}Setting up cron job...${CEND}"
  
  # 移除旧的 cron 任务
  crontab -l 2>/dev/null | grep -v "${mysql_dir}/backup.sh" > /tmp/crontab.tmp
  
  # 添加新的 cron 任务
  echo "${cron_schedule} ${mysql_dir}/backup.sh >> ${backup_dir}/backup.log 2>&1" >> /tmp/crontab.tmp
  
  crontab /tmp/crontab.tmp
  rm -f /tmp/crontab.tmp
  
  echo "Cron job added: ${cron_schedule}"
fi

# 8. 显示配置摘要
echo ""
echo "${CSUCCESS}========================================${CEND}"
echo "${CSUCCESS}Backup configuration completed!${CEND}"
echo "${CSUCCESS}========================================${CEND}"
echo ""
echo "  Databases:       ${db_name}"
echo "  Destination:     ${backup_destination}"
echo "  Backup Dir:      ${backup_dir}"
echo "  Retention:       ${expired_days} days"
[ -n "${cron_schedule}" ] && echo "  Schedule:        ${cron_schedule}"
echo ""
echo "  Manual backup:   ${mysql_dir}/backup.sh"
echo "  View logs:       tail -f ${backup_dir}/backup.log"
echo ""

# 9. 测试备份
read -e -p "Do you want to run a test backup now? [y/n]: " test_backup
if [ "${test_backup}" == "y" ]; then
  echo ""
  echo "${CMSG}Running test backup...${CEND}"
  ${mysql_dir}/backup.sh
fi

popd > /dev/null
