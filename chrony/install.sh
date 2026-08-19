#!/bin/bash
# Chrony 安装主入口
# 项目: dmp_ops/chrony
# 用法: ./install.sh [OPTIONS]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

script_dir=$(cd "$(dirname "$0")" && pwd)
src_dir="${script_dir}/src"

# Root 检查
[ "$(id -u)" != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

# 加载配置和公共库
. "${script_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${script_dir}" || exit 1
. "${script_dir}/options.conf"
. "${script_dir}/versions.txt"
. "${script_dir}/include/color.sh"
. "${script_dir}/include/check_os.sh"
. "${script_dir}/include/check_env.sh"
. "${script_dir}/include/download.sh"
. "${script_dir}/include/get_char.sh"
. "${script_dir}/include/chrony_config.sh"
. "${script_dir}/include/chrony.sh"

Show_Help() {
  cat << EOF
Usage: $0 [OPTIONS]

Chrony 时间同步安装脚本（支持单机 / 集群）

Options:
  -h, --help                 显示帮助
  -v, --version              显示版本信息
  -q, --quiet                静默模式，跳过确认

  --role ROLE                部署角色: server | client (默认: ${chrony_role})
  --mode MODE                部署模式: standalone | cluster (默认: ${deploy_mode})
  --ntp_servers LIST         时间源，逗号分隔
                             server 角色: 公网上游；client 角色: 内网 Server 或公网上游
  --allow LIST               server 角色允许同步的网段，逗号分隔 (如 10.0.0.0/24)
  --peer LIST                对等 Server，逗号分隔（双 Server 高可用）
  --timezone TZ              时区 (默认: ${timezone})
  --install_method METHOD    package | source (默认: ${install_method})
  --no_makestep              安装后不执行 chronyc makestep 强制校时
  --force                    已安装时强制重装

Examples:
  # 单机：同步公网时间源
  $0 --quiet --role client --mode standalone --ntp_servers ntp.aliyun.com,cn.pool.ntp.org

  # 集群：内网 NTP Server 节点
  $0 --quiet --role server --mode cluster --ntp_servers ntp.aliyun.com \\
     --allow 10.0.0.0/24 --peer 10.0.0.12

  # 集群：Client 节点
  $0 --quiet --role client --mode cluster --ntp_servers 10.0.0.11,10.0.0.12

EOF
}

Show_Version() {
  echo "Chrony 运维脚本 (dmp_ops)"
  echo "  源码编译默认版本: ${chrony_ver}"
  command -v chronyd > /dev/null 2>&1 && echo "  当前已安装: $(chronyd -v 2>/dev/null | head -1)"
}

# 交互式菜单
Show_Menu() {
  echo ""
  echo "${CMSG}#####################################################################${CEND}"
  echo "${CMSG}#                  Chrony 时间同步安装脚本                          #${CEND}"
  echo "${CMSG}#                  https://chrony-project.org                       #${CEND}"
  echo "${CMSG}#####################################################################${CEND}"
  echo ""

  Check_OS
  echo ""

  # 1. 部署模式
  echo "${CMSG}请选择部署模式:${CEND}"
  echo "  1) standalone  单机时间同步（直连公网 NTP 源）"
  echo "  2) cluster     集群时间同步（内网 NTP Server + 多客户端）"
  while :; do
    read -e -p "请输入选择 [1-2, 默认: 1]: " m
    m=${m:-1}
    case "${m}" in
      1) deploy_mode=standalone; break ;;
      2) deploy_mode=cluster; break ;;
      *) echo "${CWARNING}输入无效${CEND}" ;;
    esac
  done

  # 2. 角色
  if [ "${deploy_mode}" == 'standalone' ]; then
    chrony_role=client
  else
    echo ""
    echo "${CMSG}请选择本节点角色:${CEND}"
    echo "  1) client   客户端（同步内网 NTP Server）"
    echo "  2) server   内网 NTP Server（同步公网并对内网提供服务）"
    while :; do
      read -e -p "请输入选择 [1-2, 默认: 1]: " r
      r=${r:-1}
      case "${r}" in
        1) chrony_role=client; break ;;
        2) chrony_role=server; break ;;
        *) echo "${CWARNING}输入无效${CEND}" ;;
      esac
    done
  fi

  # 3. 时间源
  echo ""
  if [ "${chrony_role}" == 'server' ]; then
    read -e -p "上游公网 NTP 源（逗号分隔，默认: ${upstream_ntp_servers}）: " tmp
    [ -n "${tmp}" ] && upstream_ntp_servers="${tmp}"

    while :; do
      read -e -p "允许同步的内网网段（逗号分隔，如 10.0.0.0/24）: " tmp
      [ -n "${tmp}" ] && { allow_networks="${tmp}"; break; }
      echo "${CWARNING}Server 角色必须指定 allow 网段${CEND}"
    done

    read -e -p "对等 Server（可选，逗号分隔，回车跳过）: " tmp
    [ -n "${tmp}" ] && peer_servers="${tmp}"

    read -e -p "外网断开时的孤岛层级 local stratum [默认: ${local_stratum}]: " tmp
    [ -n "${tmp}" ] && local_stratum="${tmp}"
  elif [ "${deploy_mode}" == 'cluster' ]; then
    while :; do
      read -e -p "内网 NTP Server 地址（逗号分隔）: " tmp
      [ -n "${tmp}" ] && { ntp_server_hosts="${tmp}"; break; }
      echo "${CWARNING}集群 Client 必须指定内网 NTP Server${CEND}"
    done
  else
    read -e -p "公网 NTP 源（逗号分隔，默认: ${upstream_ntp_servers}）: " tmp
    [ -n "${tmp}" ] && upstream_ntp_servers="${tmp}"
  fi

  # 4. 时区
  echo ""
  read -e -p "时区 [默认: ${timezone}]: " tmp
  [ -n "${tmp}" ] && timezone="${tmp}"

  # 5. 是否强制校时
  echo ""
  echo "${CWARNING}chronyc makestep 会使系统时间立即跳变，运行中的数据库/中间件可能受影响${CEND}"
  read -e -p "安装后是否执行强制校时? [y/n, 默认: ${force_makestep}]: " tmp
  [ -n "${tmp}" ] && force_makestep="${tmp}"

  # 摘要
  echo ""
  echo "${CMSG}=== 安装摘要 ===${CEND}"
  echo "  部署模式  : ${deploy_mode}"
  echo "  节点角色  : ${chrony_role}"
  echo "  安装方式  : ${install_method}"
  echo "  时区      : ${timezone}"
  if [ "${chrony_role}" == 'server' ]; then
    echo "  上游源    : ${upstream_ntp_servers}"
    echo "  允许网段  : ${allow_networks}"
    echo "  对等 Server: ${peer_servers:-无}"
    echo "  孤岛层级  : stratum ${local_stratum}"
  elif [ "${deploy_mode}" == 'cluster' ]; then
    echo "  内网 Server: ${ntp_server_hosts}"
  else
    echo "  公网源    : ${upstream_ntp_servers}"
  fi
  echo "  强制校时  : ${force_makestep}"
  echo ""

  Confirm "确认开始安装?" || exit 0
}

# 参数解析
ARG_NUM=$#
quiet_mode=0
force_reinstall=n

TEMP=$(getopt -o hvq --long help,version,quiet,role:,mode:,ntp_servers:,allow:,peer:,timezone:,install_method:,no_makestep,force -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"

while true; do
  case "$1" in
    -h|--help)          Show_Help; exit 0 ;;
    -v|--version)       Show_Version; exit 0 ;;
    -q|--quiet)         quiet_mode=1; shift ;;
    --role)             chrony_role="$2"; shift 2 ;;
    --mode)             deploy_mode="$2"; shift 2 ;;
    --ntp_servers)      arg_ntp_servers="$2"; shift 2 ;;
    --allow)            allow_networks="$2"; shift 2 ;;
    --peer)             peer_servers="$2"; shift 2 ;;
    --timezone)         timezone="$2"; shift 2 ;;
    --install_method)   install_method="$2"; shift 2 ;;
    --no_makestep)      force_makestep=n; shift ;;
    --force)            force_reinstall=y; shift ;;
    --)                 shift; break ;;
    *)                  break ;;
  esac
done

main() {
  if [ ${ARG_NUM} -eq 0 ]; then
    Show_Menu
  else
    Check_OS
  fi

  # --ntp_servers 按角色/模式落到不同字段
  if [ -n "${arg_ntp_servers}" ]; then
    if [ "${chrony_role}" == 'client' ] && [ "${deploy_mode}" == 'cluster' ]; then
      ntp_server_hosts="${arg_ntp_servers}"
    else
      upstream_ntp_servers="${arg_ntp_servers}"
    fi
  fi

  # 参数校验
  case "${chrony_role}" in
    server|client) ;;
    *) echo "${CFAILURE}无效的 --role: ${chrony_role}（可选 server/client）${CEND}"; exit 1 ;;
  esac
  case "${deploy_mode}" in
    standalone|cluster) ;;
    *) echo "${CFAILURE}无效的 --mode: ${deploy_mode}（可选 standalone/cluster）${CEND}"; exit 1 ;;
  esac
  if [ "${chrony_role}" == 'server' ] && [ -z "${allow_networks}" ]; then
    echo "${CFAILURE}server 角色必须通过 --allow 指定允许同步的网段${CEND}"
    exit 1
  fi

  # 持久化到 options.conf
  Set_Option chrony_role "${chrony_role}"
  Set_Option deploy_mode "${deploy_mode}"
  Set_Option timezone "${timezone}"
  Set_Option install_method "${install_method}"
  Set_Option upstream_ntp_servers "${upstream_ntp_servers}"
  Set_Option ntp_server_hosts "${ntp_server_hosts}"
  Set_Option allow_networks "${allow_networks}"
  Set_Option peer_servers "${peer_servers}"
  Set_Option local_stratum "${local_stratum}"
  Set_Option force_makestep "${force_makestep}"

  Install_Chrony
  exit $?
}

main
