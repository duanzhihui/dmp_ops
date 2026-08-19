#!/bin/bash
# Chrony 集群管理主入口
# 项目: dmp_ops/chrony
# 用法: ./cluster.sh [OPTIONS]
#
# 前置条件: 控制机到各节点已建立 SSH 免密
#   ../sshtrust/sshtrust.sh --add-file hosts.txt

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

script_dir=$(cd "$(dirname "$0")" && pwd)
src_dir="${script_dir}/src"

[ "$(id -u)" != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}"
. "${script_dir}/options.conf"
. "${script_dir}/versions.txt"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/check_os.sh"
. "${script_dir}/include/get_char.sh"
. "${script_dir}/include/chrony_config.sh"
. "${script_dir}/include/cluster.sh"

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

Chrony 集群批量部署与巡检

Options:
  -h, --help                  显示帮助
  -q, --quiet                 静默模式，跳过确认
  --deploy                    批量部署全集群（先串行 Server，再并发 Client）
  --add-client HOST[,HOST]    新增 Client 节点并部署
  --rollout                   只重新分发配置并重启，不重装软件包
  --check                     巡检全集群同步状态与时间偏差
  --hosts-file FILE           从文件读取节点清单

节点清单文件格式（每行 "角色 主机"，# 开头为注释）:
  server 10.0.0.11
  server 10.0.0.12
  client 10.0.0.21
  client root@10.0.0.22:2222

Examples:
  $0 --hosts-file hosts.txt --deploy
  $0 --check
  $0 --add-client 10.0.0.31,10.0.0.32
  $0 --rollout

EOF
}

Show_Menu() {
  echo ""
  echo "${CMSG}#####################################################################${CEND}"
  echo "${CMSG}#                  Chrony 集群管理                                  #${CEND}"
  echo "${CMSG}#####################################################################${CEND}"
  echo ""
  echo "  当前 Server 节点: ${ntp_server_hosts:-未配置}"
  echo "  当前 Client 节点: ${ntp_client_hosts:-未配置}"
  echo "  允许同步网段    : ${allow_networks:-未配置}"
  echo "  上游公网源      : ${upstream_ntp_servers}"
  echo ""
  echo "${CMSG}请选择操作:${CEND}"
  echo "  1) 批量部署全集群"
  echo "  2) 巡检集群同步状态"
  echo "  3) 新增 Client 节点"
  echo "  4) 重新分发配置（不重装）"
  echo "  5) 从文件加载节点清单"
  echo "  0) 退出"
  echo ""
  while :; do
    read -e -p "请输入选择 [0-5]: " c
    case "${c}" in
      1) action=deploy; break ;;
      2) action=check; break ;;
      3) action=add; read -e -p "请输入要添加的 Client 节点（逗号分隔）: " add_hosts; break ;;
      4) action=rollout; break ;;
      5) action=load; read -e -p "请输入节点清单文件路径: " hosts_file; break ;;
      0) exit 0 ;;
      *) echo "${CWARNING}输入无效${CEND}" ;;
    esac
  done
}

ARG_NUM=$#
quiet_mode=0
action=""
add_hosts=""
hosts_file=""

TEMP=$(getopt -o hq --long help,quiet,deploy,add-client:,rollout,check,hosts-file: -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)       Show_Help; exit 0 ;;
    -q|--quiet)      quiet_mode=1; shift ;;
    --deploy)        action=deploy; shift ;;
    --add-client)    action=add; add_hosts="$2"; shift 2 ;;
    --rollout)       action=rollout; shift ;;
    --check)         action=check; shift ;;
    --hosts-file)    hosts_file="$2"; shift 2 ;;
    --)              shift; break ;;
    *)               break ;;
  esac
done

main() {
  Check_OS > /dev/null 2>&1

  # 先加载节点清单文件（可与其他动作组合）
  if [ -n "${hosts_file}" ]; then
    Load_Hosts_File "${hosts_file}" || exit 1
    [ -z "${action}" ] && action=load
  fi

  [ ${ARG_NUM} -eq 0 ] && Show_Menu

  case "${action}" in
    load)
      # 交互菜单选项 5 在此读取文件（命令行 --hosts-file 已在上面加载过）
      if [ -n "${hosts_file}" ] && [ ${ARG_NUM} -eq 0 ]; then
        Load_Hosts_File "${hosts_file}" || exit 1
      fi
      echo "${CSUCCESS}节点清单已加载并写入 options.conf${CEND}"
      exit 0
      ;;
    deploy)
      echo ""
      echo "${CMSG}=== 部署摘要 ===${CEND}"
      echo "  Server 节点 : ${ntp_server_hosts}"
      echo "  Client 节点 : ${ntp_client_hosts}"
      echo "  上游公网源  : ${upstream_ntp_servers}"
      echo "  允许网段    : ${allow_networks}"
      echo "  时区        : ${timezone}"
      echo "  远端目录    : ${remote_dir}"
      echo ""
      if [ ${quiet_mode} -eq 0 ]; then
        Confirm "确认批量部署?" || { echo "已取消"; exit 0; }
      fi
      Deploy_Cluster
      exit $?
      ;;
    add)
      Add_Client "${add_hosts}"
      exit $?
      ;;
    rollout)
      if [ ${quiet_mode} -eq 0 ]; then
        Confirm "确认重新分发配置并重启各节点 chronyd?" || { echo "已取消"; exit 0; }
      fi
      Rollout_Conf
      exit $?
      ;;
    check)
      Check_Cluster_Sync
      exit 0
      ;;
    *)
      Show_Help
      exit 1
      ;;
  esac
}

main
