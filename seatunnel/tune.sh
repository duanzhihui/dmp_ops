#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - JVM/Memory Tuning Script
#
# 根据系统内存大小与 CPU 核数，推荐并可选应用 JVM / 内存参数优化。
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

# Source configuration and modules
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${seatunnel_dir}"
. ./options.conf
. ./versions.txt
. ./include/color.sh
. ./include/check_os.sh
. ./include/tune_memory.sh
. ./include/seatunnel_config.sh

# Help message
Show_Help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "SeaTunnel JVM/Memory tuning based on system resources."
  echo
  echo "Options:"
  echo "  -h, --help        Show this help message"
  echo "  --show            Show tuning report only (default)"
  echo "  --apply           Apply recommended JVM params (rewrite options.conf and regenerate configs)"
  echo "  --restart         With --apply: restart SeaTunnel service after applying"
  echo "  -q, --quiet       Quiet mode, no confirmation"
  echo
  echo "Examples:"
  echo "  $0                        # Show tuning report"
  echo "  $0 --apply                # Apply recommended params"
  echo "  $0 --apply --restart -q   # Apply and restart service quietly"
}

# Parse arguments
ARG_NUM=$#
TEMP=$(getopt -o hq --long help,show,apply,restart,quiet -- "$@" 2>/dev/null)
[ $? != 0 ] && { echo "Invalid options"; Show_Help; exit 1; }
eval set -- "${TEMP}"

action=show
restart_service=false
quiet_mode=false
while true; do
  case "$1" in
    -h|--help)
      Show_Help
      popd > /dev/null
      exit 0
      ;;
    --show)
      action=show
      shift
      ;;
    --apply)
      action=apply
      shift
      ;;
    --restart)
      restart_service=true
      shift
      ;;
    -q|--quiet)
      quiet_mode=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1"
      Show_Help
      popd > /dev/null
      exit 1
      ;;
  esac
done

# 当前节点的调优角色
TUNE_ROLE=$(Get_Tune_Role)

# 应用推荐参数：写回 options.conf 并重新生成 JVM 配置文件
Apply_Tuning() {
  if [ ! -d "${seatunnel_install_dir}/config" ]; then
    echo "${CFAILURE}SeaTunnel is not installed at ${seatunnel_install_dir}!${CEND}"
    popd > /dev/null
    exit 1
  fi

  Recommend_JVM_By_Mem "${Mem:-0}" "${TUNE_ROLE}"

  echo "${CMSG}Applying recommended JVM params...${CEND}"
  Update_Opt_Conf jvm_auto_tune "true"
  Update_Opt_Conf jvm_heap_size "${REC_HEAP}"
  Update_Opt_Conf jvm_metaspace_size "${REC_METASPACE}"
  Update_Opt_Conf jvm_direct_memory_size "${REC_DIRECT}"
  Update_Opt_Conf jvm_client_heap_size "${REC_CLIENT_HEAP}"
  Update_Opt_Conf jvm_gc_threads "${REC_GC_THREADS}"

  # 同步到当前 shell 环境（Generate_JVM_Options 读取这些变量）
  jvm_heap_size=${REC_HEAP}
  jvm_metaspace_size=${REC_METASPACE}
  jvm_direct_memory_size=${REC_DIRECT}
  jvm_client_heap_size=${REC_CLIENT_HEAP}
  jvm_gc_threads=${REC_GC_THREADS}

  Generate_JVM_Options "${seatunnel_install_dir}/config" "${deploy_mode:-hybrid}"

  chown -R ${run_user:-seatunnel}:${run_group:-seatunnel} ${seatunnel_install_dir}/config 2>/dev/null

  echo "${CSUCCESS}JVM params applied:${CEND}"
  echo "  heap=${REC_HEAP}  metaspace=${REC_METASPACE}  direct=${REC_DIRECT}  gc-threads=${REC_GC_THREADS}"
}

# 重启 SeaTunnel 服务
Restart_Service() {
  echo "${CMSG}Restarting SeaTunnel services...${CEND}"
  if [ "${deploy_mode}" == "hybrid" ]; then
    systemctl restart seatunnel
  elif [ "${deploy_mode}" == "separated" ]; then
    if [ "${node_role}" == "master" ]; then
      systemctl restart seatunnel-master
    else
      systemctl restart seatunnel-worker
    fi
  else
    echo "${CWARNING}local mode has no service to restart, skip.${CEND}"
    return 0
  fi
  sleep 5
  if [ "${deploy_mode}" == "hybrid" ]; then
    systemctl is-active --quiet seatunnel && echo "${CSUCCESS}seatunnel service restarted.${CEND}" || echo "${CFAILURE}seatunnel service failed to restart!${CEND}"
  elif [ "${node_role}" == "master" ]; then
    systemctl is-active --quiet seatunnel-master && echo "${CSUCCESS}seatunnel-master service restarted.${CEND}" || echo "${CFAILURE}seatunnel-master service failed to restart!${CEND}"
  else
    systemctl is-active --quiet seatunnel-worker && echo "${CSUCCESS}seatunnel-worker service restarted.${CEND}" || echo "${CFAILURE}seatunnel-worker service failed to restart!${CEND}"
  fi
}

# Main logic
Show_Tune_Report "${Mem:-0}" "${TUNE_ROLE}"
Show_Memory_Advisory "${Mem:-0}"

if [ "${action}" == "apply" ]; then
  Apply_Tuning
  if [ "${restart_service}" == "true" ]; then
    Restart_Service
  else
    echo
    echo "${CMSG}Note: restart SeaTunnel service to take effect, e.g.: $0 --apply --restart${CEND}"
  fi
else
  echo
  echo "${CMSG}To apply the recommended params, run: $0 --apply${CEND}"
fi

popd > /dev/null
