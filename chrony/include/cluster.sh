#!/bin/bash
# chrony 集群批量部署模块
# 项目: dmp_ops/chrony
# 核心函数: Parse_Host / Check_SSH / Deploy_Node / Deploy_Cluster / Add_Client / Rollout_Conf / Check_Cluster_Sync
#
# 前置条件: 控制机到各节点已建立 SSH 免密，可使用仓库中的 sshtrust 工具:
#   ../sshtrust/sshtrust.sh --add-file hosts.txt

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"

# 解析主机条目，支持 host / user@host / host:port / user@host:port
# 输出全局变量: H_USER / H_ADDR / H_PORT
Parse_Host() {
  local entry="$1"
  H_USER="${ssh_user}"
  H_PORT="${ssh_port}"
  H_ADDR="${entry}"

  case "${entry}" in
    *@*)
      H_USER="${entry%%@*}"
      H_ADDR="${entry#*@}"
      ;;
  esac
  case "${H_ADDR}" in
    *:*)
      H_PORT="${H_ADDR##*:}"
      H_ADDR="${H_ADDR%%:*}"
      ;;
  esac
  [ -z "${H_USER}" ] && H_USER=root
  [ -z "${H_PORT}" ] && H_PORT=22
}

# 远程执行命令
Ssh_Exec() {
  local entry="$1"; shift
  Parse_Host "${entry}"
  ssh ${SSH_OPTS} -p "${H_PORT}" "${H_USER}@${H_ADDR}" "$@"
}

# 远程静默取值（失败返回空）
Ssh_Query() {
  local entry="$1"; shift
  Parse_Host "${entry}"
  ssh ${SSH_OPTS} -p "${H_PORT}" "${H_USER}@${H_ADDR}" "$@" 2>/dev/null
}

# 从文件加载节点清单
# 文件格式: 每行 "role host"，role 为 server/client；# 开头为注释
# 例:
#   server 10.0.0.11
#   client root@10.0.0.21:2222
Load_Hosts_File() {
  local file="$1"
  [ -f "${file}" ] || { echo "${CFAILURE}主机清单文件不存在: ${file}${CEND}"; return 1; }

  local servers="" clients="" role host
  while read -r role host _; do
    [ -z "${role}" ] && continue
    case "${role}" in
      \#*) continue ;;
      server) servers="${servers}${host}," ;;
      client) clients="${clients}${host}," ;;
      *)      echo "${CWARNING}忽略无法识别的行: ${role} ${host}${CEND}" ;;
    esac
  done < "${file}"

  ntp_server_hosts="${servers%,}"
  ntp_client_hosts="${clients%,}"
  Set_Option ntp_server_hosts "${ntp_server_hosts}"
  Set_Option ntp_client_hosts "${ntp_client_hosts}"
  echo "${CMSG}已加载节点清单: server=[${ntp_server_hosts}] client=[${ntp_client_hosts}]${CEND}"
}

# 校验 SSH 免密可达
Check_SSH() {
  local hosts="$1"
  local failed=""
  for h in $(echo "${hosts}" | tr ',' ' '); do
    [ -z "${h}" ] && continue
    if Ssh_Exec "${h}" "true" > /dev/null 2>&1; then
      echo "${CSUCCESS}[OK] SSH 免密可达: ${h}${CEND}"
    else
      echo "${CFAILURE}[FAIL] SSH 不可达: ${h}${CEND}"
      failed="${failed} ${h}"
    fi
  done

  if [ -n "${failed}" ]; then
    echo ""
    echo "${CFAILURE}以下节点 SSH 免密不可用:${failed}${CEND}"
    echo "${CWARNING}请先建立免密互信，例如:${CEND}"
    echo "${CWARNING}  ${script_dir}/../sshtrust/sshtrust.sh --add${failed}${CEND}"
    return 1
  fi
  return 0
}

# 部署单个节点
# 用法: Deploy_Node <host> <role>
Deploy_Node() {
  local host="$1" role="$2"
  Parse_Host "${host}"

  local self_addr="${H_ADDR}" self_user="${H_USER}" self_port="${H_PORT}"
  local pkg="/tmp/chrony_deploy_$$_${self_addr//[^0-9A-Za-z]/_}.tgz"
  local pkg_name="${pkg##*/}"

  echo "${CMSG}[${self_addr}] 开始部署 chrony (role=${role}) ...${CEND}"

  # 1. 创建远端目录
  ssh ${SSH_OPTS} -p "${self_port}" "${self_user}@${self_addr}" \
    "rm -rf ${remote_dir} && mkdir -p ${remote_dir}" || {
    echo "${CFAILURE}[${self_addr}] 创建远端目录失败${CEND}"
    return 1
  }

  # 2. 分发脚本（排除本地 options.conf，避免覆盖远端角色配置）
  tar czf "${pkg}" -C "${script_dir}" \
      --exclude='options.conf' --exclude='options.conf.*' --exclude='src/*.tar.gz' . 2>/dev/null
  scp ${SSH_OPTS} -P "${self_port}" -q "${pkg}" "${self_user}@${self_addr}:${remote_dir}/" || {
    echo "${CFAILURE}[${self_addr}] 分发失败${CEND}"
    rm -f "${pkg}"
    return 1
  }
  rm -f "${pkg}"
  ssh ${SSH_OPTS} -p "${self_port}" "${self_user}@${self_addr}" \
    "cd ${remote_dir} && tar xzf ${pkg_name} && rm -f ${pkg_name}"

  # 3. 组装远端安装命令
  local remote_cmd="cd ${remote_dir} && bash install.sh --quiet --mode cluster --role ${role}"
  remote_cmd="${remote_cmd} --timezone '${timezone}'"
  if [ "${role}" == 'server' ]; then
    remote_cmd="${remote_cmd} --ntp_servers '${upstream_ntp_servers}'"
    remote_cmd="${remote_cmd} --allow '${allow_networks}'"
    # 其他 Server 作为本节点的 peer（排除自身）
    local peers=""
    for s in $(echo "${ntp_server_hosts}" | tr ',' ' '); do
      [ -z "${s}" ] && continue
      Parse_Host "${s}"
      [ "${H_ADDR}" == "${self_addr}" ] && continue
      peers="${peers}${H_ADDR},"
    done
    peers="${peers%,}"
    [ -n "${peers}" ] && remote_cmd="${remote_cmd} --peer '${peers}'"
  else
    # Client 指向所有 Server（仅取地址部分）
    local srv=""
    for s in $(echo "${ntp_server_hosts}" | tr ',' ' '); do
      [ -z "${s}" ] && continue
      Parse_Host "${s}"
      srv="${srv}${H_ADDR},"
    done
    remote_cmd="${remote_cmd} --ntp_servers '${srv%,}'"
  fi
  H_ADDR="${self_addr}"; H_USER="${self_user}"; H_PORT="${self_port}"

  # 4. 远端执行
  ssh ${SSH_OPTS} -p "${self_port}" "${self_user}@${self_addr}" "${remote_cmd}"
  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}[${self_addr}] 部署成功${CEND}"
    return 0
  fi
  echo "${CFAILURE}[${self_addr}] 部署失败${CEND}"
  return 1
}

# 等待 Server 完成首次同步
Wait_Server_Ready() {
  local host="$1"
  local timeout=${2:-60}
  local elapsed=0
  Parse_Host "${host}"

  echo "${CMSG}[${H_ADDR}] 等待 NTP Server 完成首次同步（最多 ${timeout}s）...${CEND}"
  while [ ${elapsed} -lt ${timeout} ]; do
    local leap
    leap=$(Ssh_Query "${host}" "chronyc tracking 2>/dev/null | awk -F': *' '/Leap status/{print \$2}'")
    if [ "${leap}" == "Normal" ]; then
      echo "${CSUCCESS}[${H_ADDR}] Server 已就绪 (Leap status=Normal)${CEND}"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  echo "${CWARNING}[${H_ADDR}] 等待超时，Server 尚未完成同步，继续部署 Client${CEND}"
  return 1
}

# 全集群部署：先串行部署 Server，再并发部署 Client
Deploy_Cluster() {
  if [ -z "${ntp_server_hosts}" ]; then
    echo "${CFAILURE}未配置 ntp_server_hosts，无法部署集群${CEND}"
    return 1
  fi
  if [ -z "${allow_networks}" ]; then
    echo "${CFAILURE}未配置 allow_networks（Server 允许同步的网段），无法部署集群${CEND}"
    return 1
  fi

  Check_SSH "${ntp_server_hosts},${ntp_client_hosts}" || return 1

  echo ""
  echo "${CMSG}========== 阶段 1/3: 部署 NTP Server ==========${CEND}"
  local srv_fail=0
  for h in $(echo "${ntp_server_hosts}" | tr ',' ' '); do
    [ -z "${h}" ] && continue
    Deploy_Node "${h}" server || srv_fail=$((srv_fail + 1))
  done
  if [ ${srv_fail} -gt 0 ]; then
    echo "${CFAILURE}有 ${srv_fail} 台 Server 部署失败，中止 Client 部署${CEND}"
    return 1
  fi

  echo ""
  echo "${CMSG}========== 阶段 2/3: 等待 Server 就绪 ==========${CEND}"
  for h in $(echo "${ntp_server_hosts}" | tr ',' ' '); do
    [ -z "${h}" ] && continue
    Wait_Server_Ready "${h}" 60
  done

  echo ""
  echo "${CMSG}========== 阶段 3/3: 并发部署 Client ==========${CEND}"
  local pids=""
  for h in $(echo "${ntp_client_hosts}" | tr ',' ' '); do
    [ -z "${h}" ] && continue
    Deploy_Node "${h}" client &
    pids="${pids} $!"
  done
  local cli_fail=0
  for p in ${pids}; do
    wait "${p}" || cli_fail=$((cli_fail + 1))
  done

  echo ""
  [ ${cli_fail} -gt 0 ] && echo "${CWARNING}有 ${cli_fail} 台 Client 部署失败${CEND}" \
                        || echo "${CSUCCESS}全集群部署完成${CEND}"
  echo ""
  Check_Cluster_Sync
  return 0
}

# 增量添加 Client 节点
Add_Client() {
  local hosts="$1"
  [ -z "${hosts}" ] && { echo "${CFAILURE}未指定要添加的节点${CEND}"; return 1; }

  Check_SSH "${hosts}" || return 1

  local pids=""
  for h in $(echo "${hosts}" | tr ',' ' '); do
    [ -z "${h}" ] && continue
    Deploy_Node "${h}" client &
    pids="${pids} $!"
  done
  for p in ${pids}; do wait "${p}"; done

  # 合并进节点清单（去重）
  local merged
  merged=$(echo "${ntp_client_hosts},${hosts}" | tr ',' '\n' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's@,$@@')
  ntp_client_hosts="${merged}"
  Set_Option ntp_client_hosts "${merged}"
  echo "${CSUCCESS}节点清单已更新: ${merged}${CEND}"
}

# 只重新分发配置并重启，不重装软件包
Rollout_Conf() {
  local all="${ntp_server_hosts},${ntp_client_hosts}"
  Check_SSH "${all}" || return 1

  for h in $(echo "${ntp_server_hosts}" | tr ',' ' '); do
    [ -z "${h}" ] && continue
    Deploy_Node "${h}" server
  done
  for h in $(echo "${ntp_client_hosts}" | tr ',' ' '); do
    [ -z "${h}" ] && continue
    Deploy_Node "${h}" client &
  done
  wait
  echo "${CSUCCESS}配置分发完成${CEND}"
  Check_Cluster_Sync
}

# 全集群同步状态巡检
Check_Cluster_Sync() {
  echo "${CMSG}========== 集群时间同步巡检: $(date '+%F %T') ==========${CEND}"
  printf "%-20s %-8s %-9s %-16s %-10s %s\n" "HOST" "ROLE" "STRATUM" "LAST_OFFSET(s)" "LEAP" "REF_ID"
  printf "%s\n" "----------------------------------------------------------------------------------------"

  local role h out stratum offset leap refid flag abs exceed
  for role in server client; do
    local list=""
    [ "${role}" == 'server' ] && list="${ntp_server_hosts}" || list="${ntp_client_hosts}"
    for h in $(echo "${list}" | tr ',' ' '); do
      [ -z "${h}" ] && continue
      Parse_Host "${h}"
      out=$(Ssh_Query "${h}" "chronyc tracking")
      if [ -z "${out}" ]; then
        printf "%-20s %-8s %-9s %-16s %-10s %s\n" "${H_ADDR}" "${role}" "-" "-" "UNREACHABLE" "-"
        continue
      fi
      stratum=$(echo "${out}" | awk -F': *' '/Stratum/{print $2}')
      offset=$(echo "${out}" | awk -F': *' '/Last offset/{print $2}' | awk '{print $1}')
      leap=$(echo "${out}" | awk -F': *' '/Leap status/{print $2}')
      refid=$(echo "${out}" | awk -F': *' '/Reference ID/{print $2}' | awk '{print $1}')

      abs=$(awk -v v="${offset}" 'BEGIN{v=v+0; if(v<0) v=-v; printf "%.9f", v}')
      exceed=$(awk -v a="${abs}" -v t="${offset_threshold}" 'BEGIN{print ((a+0)>(t+0))?1:0}')
      flag=""
      { [ "${exceed}" == "1" ] || [ "${leap}" != "Normal" ]; } && flag="  <== 异常"

      printf "%-20s %-8s %-9s %-16s %-10s %s%s\n" \
        "${H_ADDR}" "${role}" "${stratum:--}" "${offset:--}" "${leap:--}" "${refid:--}" "${flag}"
    done
  done
  echo ""
}
