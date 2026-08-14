#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Backup utility for Doris metadata and configuration

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

doris_dir=$(dirname "$(dirname "$(readlink -f $0)")")
pushd ${doris_dir} > /dev/null
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${doris_dir}"
. ./options.conf
. ./include/color.sh

BACKUP_DIR="/data/backup/doris"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

Show_Help() {
  echo "Usage: $0 [options]

Options:
  --all           Backup everything (meta + conf)
  --meta          Backup FE metadata only
  --conf          Backup configuration files only
  --dir <path>    Specify backup directory (default: ${BACKUP_DIR})
  --help, -h      Show this help
  "
}

backup_meta=n
backup_conf=n

case "$1" in
  --all)    backup_meta=y; backup_conf=y ;;
  --meta)   backup_meta=y ;;
  --conf)   backup_conf=y ;;
  --dir)    BACKUP_DIR=$2; shift ;;
  -h|--help) Show_Help; exit 0 ;;
  *)        backup_meta=y; backup_conf=y ;;
esac

mkdir -p ${BACKUP_DIR}

if [ "${backup_conf}" == "y" ]; then
  echo "${CMSG}Backing up configuration files...${CEND}"
  conf_backup="${BACKUP_DIR}/conf_${TIMESTAMP}.tar.gz"

  tar czf ${conf_backup} \
    ${fe_install_dir}/conf/ \
    ${be_install_dir}/conf/ \
    ${doris_dir}/options.conf \
    ${doris_dir}/versions.txt \
    2>/dev/null

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Configuration backup saved: ${conf_backup}${CEND}"
  else
    echo "${CFAILURE}Configuration backup failed!${CEND}"
  fi
fi

if [ "${backup_meta}" == "y" ]; then
  echo "${CMSG}Backing up FE metadata...${CEND}"
  echo "${CWARNING}Note: For consistent backup, consider stopping FE first.${CEND}"

  meta_backup="${BACKUP_DIR}/meta_${TIMESTAMP}.tar.gz"

  tar czf ${meta_backup} \
    ${fe_meta_dir}/ \
    2>/dev/null

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Metadata backup saved: ${meta_backup}${CEND}"
  else
    echo "${CFAILURE}Metadata backup failed!${CEND}"
  fi
fi

# Cleanup old backups (keep last 7 days)
echo "${CMSG}Cleaning up backups older than 7 days...${CEND}"
find ${BACKUP_DIR} -name "*.tar.gz" -mtime +7 -delete 2>/dev/null

echo "${CSUCCESS}Backup completed!${CEND}"
ls -lh ${BACKUP_DIR}/*_${TIMESTAMP}* 2>/dev/null

popd > /dev/null
