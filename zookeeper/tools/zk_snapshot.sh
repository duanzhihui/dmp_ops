#!/bin/bash
# ZooKeeper 快照工具
# 项目: oneinstack/zookeeper
# 用法: ./tools/zk_snapshot.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

script_dir=$(cd "$(dirname "$0")/.." && pwd)
. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}"
. "${script_dir}/options.conf"
. "${script_dir}/include/color.sh"

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

ZooKeeper Snapshot Tool

Options:
  -h, --help        Show this help message
  --list            List all snapshots
  --info FILE       Show snapshot info
  --dump FILE       Dump snapshot content
  --verify          Verify snapshot integrity

Examples:
  $0 --list
  $0 --info snapshot.100000001
  $0 --dump snapshot.100000001

EOF
}

# 列出所有快照
List_Snapshots() {
  echo "${CMSG}=== ZooKeeper Snapshots ===${CEND}"
  
  if [ ! -d "${zk_data_dir}/version-2" ]; then
    echo "No snapshots found"
    return 1
  fi
  
  ls -lh "${zk_data_dir}/version-2/snapshot."* 2>/dev/null | while read line; do
    echo "  ${line}"
  done
  
  echo ""
  echo "Total: $(ls "${zk_data_dir}/version-2/snapshot."* 2>/dev/null | wc -l) snapshot(s)"
}

# 显示快照信息
Show_Snapshot_Info() {
  local snapshot_file=$1
  
  if [ ! -f "${snapshot_file}" ]; then
    snapshot_file="${zk_data_dir}/version-2/${snapshot_file}"
  fi
  
  if [ ! -f "${snapshot_file}" ]; then
    echo "${CFAILURE}Snapshot not found: ${snapshot_file}${CEND}"
    return 1
  fi
  
  echo "${CMSG}=== Snapshot Info ===${CEND}"
  echo "File: ${snapshot_file}"
  echo "Size: $(du -h "${snapshot_file}" | awk '{print $1}')"
  echo "Modified: $(stat -c %y "${snapshot_file}")"
  
  # 使用 zkSnapShotToolkit 获取详细信息
  if [ -x "${zk_install_dir}/bin/zkSnapShotToolkit.sh" ]; then
    echo ""
    echo "${CMSG}Snapshot Details:${CEND}"
    ${zk_install_dir}/bin/zkSnapShotToolkit.sh "${snapshot_file}" 2>/dev/null | head -20
  fi
}

# 转储快照内容
Dump_Snapshot() {
  local snapshot_file=$1
  
  if [ ! -f "${snapshot_file}" ]; then
    snapshot_file="${zk_data_dir}/version-2/${snapshot_file}"
  fi
  
  if [ ! -f "${snapshot_file}" ]; then
    echo "${CFAILURE}Snapshot not found: ${snapshot_file}${CEND}"
    return 1
  fi
  
  if [ -x "${zk_install_dir}/bin/zkSnapShotToolkit.sh" ]; then
    ${zk_install_dir}/bin/zkSnapShotToolkit.sh "${snapshot_file}"
  else
    echo "${CFAILURE}zkSnapShotToolkit.sh not found${CEND}"
    return 1
  fi
}

# 验证快照完整性
Verify_Snapshots() {
  echo "${CMSG}=== Verifying Snapshots ===${CEND}"
  
  local error_count=0
  
  for snapshot in "${zk_data_dir}/version-2/snapshot."*; do
    [ ! -f "${snapshot}" ] && continue
    
    local filename=$(basename "${snapshot}")
    
    if [ -x "${zk_install_dir}/bin/zkSnapShotToolkit.sh" ]; then
      if ${zk_install_dir}/bin/zkSnapShotToolkit.sh "${snapshot}" &>/dev/null; then
        echo "  ${CSUCCESS}[OK]${CEND} ${filename}"
      else
        echo "  ${CFAILURE}[FAIL]${CEND} ${filename}"
        error_count=$((error_count + 1))
      fi
    else
      echo "  ${CWARNING}[SKIP]${CEND} ${filename} (no toolkit)"
    fi
  done
  
  echo ""
  if [ "${error_count}" -eq 0 ]; then
    echo "${CSUCCESS}All snapshots verified${CEND}"
  else
    echo "${CFAILURE}${error_count} snapshot(s) failed verification${CEND}"
  fi
}

# 解析参数
action="list"
target_file=""

TEMP=$(getopt -o h --long help,list,info:,dump:,verify -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }

eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)
      Show_Help
      exit 0
      ;;
    --list)
      action="list"
      shift
      ;;
    --info)
      action="info"
      target_file="$2"
      shift 2
      ;;
    --dump)
      action="dump"
      target_file="$2"
      shift 2
      ;;
    --verify)
      action="verify"
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

case "${action}" in
  list)
    List_Snapshots
    ;;
  info)
    Show_Snapshot_Info "${target_file}"
    ;;
  dump)
    Dump_Snapshot "${target_file}"
    ;;
  verify)
    Verify_Snapshots
    ;;
esac
