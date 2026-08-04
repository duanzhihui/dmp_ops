#!/bin/bash
# MySQL 单库备份脚本
# Author: DMP OPS
#
# 说明: 备份单个数据库，由 backup.sh 调用
# 用法: ./db_bk.sh <database_name>

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# 获取脚本所在目录
tools_dir=$(dirname "$(readlink -f $0)")
mysql_dir=$(dirname "${tools_dir}")

# 加载配置
. ${mysql_dir}/options.conf
. ${mysql_dir}/include/check_dir.sh

# 检查参数
DBname=$1
if [ -z "${DBname}" ]; then
  echo "Usage: $0 <database_name>"
  exit 1
fi

# 设置文件路径
LogFile=${backup_dir}/db.log
Timestamp=$(date +%Y%m%d_%H%M%S)
DumpFile=${backup_dir}/DB_${DBname}_${Timestamp}.sql
NewFile=${backup_dir}/DB_${DBname}_${Timestamp}.tgz
OldFile="${backup_dir}/DB_${DBname}_$(date +%Y%m%d --date="${expired_days} days ago")*.tgz"

# 确保备份目录存在
[ ! -d "${backup_dir}" ] && mkdir -p ${backup_dir}

# 记录日志
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> ${LogFile}
}

# 检查数据库是否存在
DB_tmp=$(${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -N -e "SHOW DATABASES LIKE '${DBname}'" 2>/dev/null)
if [ -z "${DB_tmp}" ]; then
  log "[ERROR] Database [${DBname}] does not exist"
  echo "Database [${DBname}] does not exist"
  exit 1
fi

# 删除过期备份
if ls ${OldFile} >/dev/null 2>&1; then
  rm -f ${OldFile}
  log "[INFO] Deleted old backup files: ${OldFile}"
fi

# 检查备份文件是否已存在
if [ -e "${NewFile}" ]; then
  log "[WARNING] Backup file already exists: ${NewFile}"
  echo "Backup file already exists: ${NewFile}"
  exit 1
fi

# 执行备份
log "[INFO] Starting backup of database: ${DBname}"

${db_install_dir}/bin/mysqldump \
  -uroot \
  -p${dbrootpwd} \
  --single-transaction \
  --quick \
  --lock-tables=false \
  --databases ${DBname} > ${DumpFile} 2>/dev/null

if [ $? -ne 0 ] || [ ! -s "${DumpFile}" ]; then
  log "[ERROR] mysqldump failed for database: ${DBname}"
  rm -f ${DumpFile}
  exit 1
fi

# 压缩备份文件
pushd ${backup_dir} > /dev/null
tar czf ${NewFile} ${DumpFile##*/} 2>/dev/null

if [ $? -eq 0 ] && [ -s "${NewFile}" ]; then
  # 获取文件大小
  file_size=$(ls -lh ${NewFile} | awk '{print $5}')
  log "[SUCCESS] Backup completed: ${NewFile} (${file_size})"
  echo "Backup success: ${NewFile} (${file_size})"
  
  # 删除临时 SQL 文件
  rm -f ${DumpFile}
else
  log "[ERROR] Compression failed for: ${DumpFile}"
  rm -f ${DumpFile} ${NewFile}
  exit 1
fi

popd > /dev/null
