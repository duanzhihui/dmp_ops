#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Backup Setup Script
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear

# Check root
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# Get script directory
seatunnel_dir=$(dirname $(readlink -f $0))
pushd ${seatunnel_dir} > /dev/null

# Source configuration
. ./options.conf
. ./include/color.sh
. ./include/get_char.sh

echo
echo "+----------------------------------------------------------------------+"
echo "|              SeaTunnel Backup Configuration Wizard                   |"
echo "+----------------------------------------------------------------------+"
echo

# Step 1: Select backup destination
echo "${CMSG}Step 1: Select backup destination(s)${CEND}"
echo "  1. Local only"
echo "  2. Local + Remote server (SCP)"
echo "  3. Local + Alibaba Cloud OSS"
echo "  4. Local + AWS S3"
echo "  5. Custom (multiple destinations)"
echo

while true; do
  read -e -p "Enter choice [1-5]: " dest_choice
  case "${dest_choice}" in
    1)
      backup_destination="local"
      break
      ;;
    2)
      backup_destination="local,remote"
      break
      ;;
    3)
      backup_destination="local,oss"
      break
      ;;
    4)
      backup_destination="local,s3"
      break
      ;;
    5)
      read -e -p "Enter destinations (comma-separated: local,remote,oss,s3): " backup_destination
      break
      ;;
    *)
      echo "${CWARNING}Invalid choice${CEND}"
      ;;
  esac
done

# Step 2: Configure remote server (if selected)
if [[ "${backup_destination}" == *"remote"* ]]; then
  echo
  echo "${CMSG}Step 2a: Configure remote server${CEND}"
  read -e -p "Remote host: " remote_host
  read -e -p "Remote user: " remote_user
  read -e -p "Remote directory: " remote_dir
  
  # Test connection
  echo "${CMSG}Testing SSH connection...${CEND}"
  ssh -o BatchMode=yes -o ConnectTimeout=5 ${remote_user}@${remote_host} "echo 'Connection successful'" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "${CWARNING}SSH connection failed. Please ensure SSH key is configured.${CEND}"
    echo "You can set up SSH key with: ssh-copy-id ${remote_user}@${remote_host}"
  else
    echo "${CSUCCESS}SSH connection successful!${CEND}"
  fi
fi

# Step 3: Configure OSS (if selected)
if [[ "${backup_destination}" == *"oss"* ]]; then
  echo
  echo "${CMSG}Step 2b: Configure Alibaba Cloud OSS${CEND}"
  read -e -p "OSS bucket name: " oss_bucket
  read -e -p "OSS endpoint (e.g., oss-cn-hangzhou.aliyuncs.com): " oss_endpoint
  
  # Check if ossutil is installed
  if ! command -v ossutil > /dev/null 2>&1; then
    echo "${CWARNING}ossutil is not installed. Please install it first.${CEND}"
    echo "Download: https://help.aliyun.com/document_detail/120075.html"
  else
    echo "${CMSG}Testing OSS connection...${CEND}"
    ossutil ls oss://${oss_bucket} > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "${CSUCCESS}OSS connection successful!${CEND}"
    else
      echo "${CWARNING}OSS connection failed. Please check credentials.${CEND}"
    fi
  fi
fi

# Step 4: Configure S3 (if selected)
if [[ "${backup_destination}" == *"s3"* ]]; then
  echo
  echo "${CMSG}Step 2c: Configure AWS S3${CEND}"
  read -e -p "S3 bucket name: " s3_bucket
  read -e -p "S3 region (e.g., us-east-1): " s3_region
  
  # Check if aws cli is installed
  if ! command -v aws > /dev/null 2>&1; then
    echo "${CWARNING}AWS CLI is not installed. Please install it first.${CEND}"
    echo "Install: pip install awscli"
  else
    echo "${CMSG}Testing S3 connection...${CEND}"
    aws s3 ls s3://${s3_bucket} > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "${CSUCCESS}S3 connection successful!${CEND}"
    else
      echo "${CWARNING}S3 connection failed. Please check credentials.${CEND}"
    fi
  fi
fi

# Step 5: Select backup content
echo
echo "${CMSG}Step 3: Select backup content${CEND}"
echo "  1. config - Configuration files only"
echo "  2. config,connectors - Config + Connector plugins"
echo "  3. config,connectors,jobs - Config + Connectors + Job files"
echo "  4. full - Full backup (all directories)"
echo

while true; do
  read -e -p "Enter choice [1-4] (default: 2): " content_choice
  content_choice=${content_choice:-2}
  case "${content_choice}" in
    1)
      backup_content="config"
      break
      ;;
    2)
      backup_content="config,connectors"
      break
      ;;
    3)
      backup_content="config,connectors,jobs"
      break
      ;;
    4)
      backup_content="full"
      break
      ;;
    *)
      echo "${CWARNING}Invalid choice${CEND}"
      ;;
  esac
done

# Step 6: Configure backup directory and retention
echo
echo "${CMSG}Step 4: Configure backup settings${CEND}"
read -e -p "Backup directory (default: ${backup_dir}): " input_backup_dir
backup_dir=${input_backup_dir:-${backup_dir}}

read -e -p "Retention days (default: ${expired_days}): " input_days
expired_days=${input_days:-${expired_days}}

# Step 7: Configure cron schedule
echo
echo "${CMSG}Step 5: Configure backup schedule${CEND}"
echo "  1. Daily at 2:00 AM"
echo "  2. Daily at 3:00 AM"
echo "  3. Weekly on Sunday at 2:00 AM"
echo "  4. Custom cron expression"
echo "  5. No automatic backup (manual only)"
echo

while true; do
  read -e -p "Enter choice [1-5] (default: 1): " cron_choice
  cron_choice=${cron_choice:-1}
  case "${cron_choice}" in
    1)
      cron_expr="0 2 * * *"
      break
      ;;
    2)
      cron_expr="0 3 * * *"
      break
      ;;
    3)
      cron_expr="0 2 * * 0"
      break
      ;;
    4)
      read -e -p "Enter cron expression (e.g., '0 2 * * *'): " cron_expr
      break
      ;;
    5)
      cron_expr=""
      break
      ;;
    *)
      echo "${CWARNING}Invalid choice${CEND}"
      ;;
  esac
done

# Summary
echo
echo "=========================================="
echo "${CMSG}Backup Configuration Summary${CEND}"
echo "=========================================="
echo "Backup Destination: ${backup_destination}"
echo "Backup Content:     ${backup_content}"
echo "Backup Directory:   ${backup_dir}"
echo "Retention Days:     ${expired_days}"
if [ -n "${cron_expr}" ]; then
  echo "Schedule:           ${cron_expr}"
else
  echo "Schedule:           Manual only"
fi
if [[ "${backup_destination}" == *"remote"* ]]; then
  echo "Remote Server:      ${remote_user}@${remote_host}:${remote_dir}"
fi
if [[ "${backup_destination}" == *"oss"* ]]; then
  echo "OSS Bucket:         ${oss_bucket}"
fi
if [[ "${backup_destination}" == *"s3"* ]]; then
  echo "S3 Bucket:          ${s3_bucket}"
fi
echo "=========================================="
echo

read -e -p "Save this configuration? [y/n]: " save_config
if [[ ! "${save_config}" =~ ^[Yy]$ ]]; then
  echo "${CMSG}Configuration cancelled.${CEND}"
  exit 0
fi

# Save configuration to options.conf
echo "${CMSG}Saving configuration...${CEND}"

sed -i "s@^backup_dir=.*@backup_dir=${backup_dir}@" ${seatunnel_dir}/options.conf
sed -i "s@^expired_days=.*@expired_days=${expired_days}@" ${seatunnel_dir}/options.conf
sed -i "s@^backup_destination=.*@backup_destination=${backup_destination}@" ${seatunnel_dir}/options.conf
sed -i "s@^backup_content=.*@backup_content=${backup_content}@" ${seatunnel_dir}/options.conf

if [[ "${backup_destination}" == *"remote"* ]]; then
  sed -i "s@^remote_host=.*@remote_host=${remote_host}@" ${seatunnel_dir}/options.conf
  sed -i "s@^remote_user=.*@remote_user=${remote_user}@" ${seatunnel_dir}/options.conf
  sed -i "s@^remote_dir=.*@remote_dir=${remote_dir}@" ${seatunnel_dir}/options.conf
fi

if [[ "${backup_destination}" == *"oss"* ]]; then
  sed -i "s@^oss_bucket=.*@oss_bucket=${oss_bucket}@" ${seatunnel_dir}/options.conf
  sed -i "s@^oss_endpoint=.*@oss_endpoint=${oss_endpoint}@" ${seatunnel_dir}/options.conf
fi

if [[ "${backup_destination}" == *"s3"* ]]; then
  sed -i "s@^s3_bucket=.*@s3_bucket=${s3_bucket}@" ${seatunnel_dir}/options.conf
  sed -i "s@^s3_region=.*@s3_region=${s3_region}@" ${seatunnel_dir}/options.conf
fi

# Setup cron job
if [ -n "${cron_expr}" ]; then
  echo "${CMSG}Setting up cron job...${CEND}"
  
  # Remove existing cron job
  crontab -l 2>/dev/null | grep -v "${seatunnel_dir}/backup.sh" > /tmp/crontab_tmp
  
  # Add new cron job
  echo "${cron_expr} ${seatunnel_dir}/backup.sh >> ${backup_dir}/backup.log 2>&1" >> /tmp/crontab_tmp
  crontab /tmp/crontab_tmp
  rm -f /tmp/crontab_tmp
  
  echo "${CSUCCESS}Cron job configured!${CEND}"
fi

# Create backup directory
mkdir -p ${backup_dir}

echo
echo "${CSUCCESS}Backup configuration completed!${CEND}"
echo
echo "To run a manual backup: ${seatunnel_dir}/backup.sh"
echo "Backup logs: ${backup_dir}/backup.log"
echo

popd > /dev/null
