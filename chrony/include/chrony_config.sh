#!/bin/bash
# chrony 路径适配与配置生成模块
# 项目: dmp_ops/chrony
# 核心函数: Set_Option / Detect_Chrony_Path / Generate_Server_Conf / Generate_Client_Conf / Apply_Chrony_Conf

# 持久化配置项到 options.conf
# 用法: Set_Option key value
# 注意: 不使用 sed，避免值中包含 @ / & 等分隔符导致替换失败（如 root@host）
Set_Option() {
  local key="$1" value="$2"
  local conf="${script_dir}/options.conf"
  [ -f "${conf}" ] || return 0

  local tmp="${conf}.tmp.$$"
  local found=0
  local line
  while IFS= read -r line || [ -n "${line}" ]; do
    if [ ${found} -eq 0 ] && [ "${line#${key}=}" != "${line}" ]; then
      printf '%s=%s\n' "${key}" "${value}"
      found=1
    else
      printf '%s\n' "${line}"
    fi
  done < "${conf}" > "${tmp}"

  [ ${found} -eq 0 ] && printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
  /bin/mv -f "${tmp}" "${conf}"
}

# 按发行版探测 chrony 的配置文件、服务名、运行用户、drift 文件
# 输出并持久化: chrony_conf / chrony_keys / chrony_service / chrony_user / drift_file
Detect_Chrony_Path() {
  case "${Family}" in
    rhel)
      chrony_conf=/etc/chrony.conf
      chrony_keys=/etc/chrony.keys
      chrony_service=chronyd
      chrony_user=chrony
      drift_file=/var/lib/chrony/drift
      ;;
    debian|ubuntu)
      chrony_conf=/etc/chrony/chrony.conf
      chrony_keys=/etc/chrony/chrony.keys
      chrony_service=chrony
      chrony_user=_chrony
      drift_file=/var/lib/chrony/chrony.drift
      ;;
    *)
      chrony_conf=/etc/chrony.conf
      chrony_keys=/etc/chrony.keys
      chrony_service=chronyd
      chrony_user=chrony
      drift_file=/var/lib/chrony/drift
      ;;
  esac

  # 兼容：部分 Debian 新版将配置放在 /etc/chrony.conf
  [ ! -f "${chrony_conf}" ] && [ -f /etc/chrony.conf ] && {
    chrony_conf=/etc/chrony.conf
    chrony_keys=/etc/chrony.keys
  }
  # 兼容：服务名以实际存在的 unit 为准
  if ! systemctl list-unit-files 2>/dev/null | grep -qE "^${chrony_service}\.service"; then
    for svc in chronyd chrony; do
      systemctl list-unit-files 2>/dev/null | grep -qE "^${svc}\.service" && { chrony_service=${svc}; break; }
    done
  fi
  # 兼容：运行用户以 /etc/passwd 为准
  id -u "${chrony_user}" > /dev/null 2>&1 || {
    for u in chrony _chrony ntp; do
      id -u "${u}" > /dev/null 2>&1 && { chrony_user=${u}; break; }
    done
  }

  Set_Option chrony_conf "${chrony_conf}"
  Set_Option chrony_keys "${chrony_keys}"
  Set_Option chrony_service "${chrony_service}"
  Set_Option chrony_user "${chrony_user}"
  Set_Option drift_file "${drift_file}"
}

# 渲染配置模板
# 用法: Render_Template <template> <output>
# 多行占位符（{{UPSTREAM_SERVERS}} / {{ALLOW_NETWORKS}} / {{PEER_SERVERS}}）由对应的 _block 变量提供
# 单值占位符直接做字符串替换
Render_Template() {
  local tmpl="$1" out="$2"
  local line

  [ -f "${tmpl}" ] || { echo "${CFAILURE}模板不存在: ${tmpl}${CEND}"; return 1; }
  : > "${out}"

  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      *'{{UPSTREAM_SERVERS}}'*)
        [ -n "${_upstream_block}" ] && printf '%s\n' "${_upstream_block}"
        continue
        ;;
      *'{{ALLOW_NETWORKS}}'*)
        [ -n "${_allow_block}" ] && printf '%s\n' "${_allow_block}"
        continue
        ;;
      *'{{PEER_SERVERS}}'*)
        [ -n "${_peer_block}" ] && printf '%s\n' "${_peer_block}"
        continue
        ;;
      *'{{LOG_MEASUREMENTS}}'*)
        [ -n "${log_measurements}" ] && printf '%s\n' "${log_measurements}"
        continue
        ;;
    esac
    line="${line//\{\{LOCAL_STRATUM\}\}/${local_stratum}}"
    line="${line//\{\{DRIFT_FILE\}\}/${drift_file}}"
    line="${line//\{\{KEYS_FILE\}\}/${chrony_keys}}"
    printf '%s\n' "${line}"
  done < "${tmpl}" > "${out}"

  return 0
}

# 构造多行块变量
Build_Blocks() {
  local sources="$1"
  _upstream_block=""
  _allow_block=""
  _peer_block=""

  for s in $(echo "${sources}" | tr ',' ' '); do
    [ -z "${s}" ] && continue
    _upstream_block="${_upstream_block}server ${s} iburst"$'\n'
  done
  _upstream_block="${_upstream_block%$'\n'}"

  for n in $(echo "${allow_networks}" | tr ',' ' '); do
    [ -z "${n}" ] && continue
    _allow_block="${_allow_block}allow ${n}"$'\n'
  done
  _allow_block="${_allow_block%$'\n'}"

  for p in $(echo "${peer_servers}" | tr ',' ' '); do
    [ -z "${p}" ] && continue
    _peer_block="${_peer_block}peer ${p}"$'\n'
  done
  _peer_block="${_peer_block%$'\n'}"
}

# 生成 Server 角色配置
Generate_Server_Conf() {
  local tmpl="${script_dir}/config/chrony-server.conf.template"
  local out="${script_dir}/config/chrony.conf.rendered"

  # 路径变量未初始化时先探测，避免渲染出空的 driftfile/keyfile
  { [ -z "${drift_file}" ] || [ -z "${chrony_keys}" ]; } && Detect_Chrony_Path

  if [ -z "${upstream_ntp_servers}" ]; then
    echo "${CWARNING}未配置 upstream_ntp_servers，Server 将仅以本地时钟作为 stratum ${local_stratum} 源${CEND}"
  fi
  if [ -z "${allow_networks}" ]; then
    echo "${CFAILURE}Server 角色必须配置 allow_networks（允许同步的内网网段），否则客户端无法连接${CEND}"
    return 1
  fi

  Build_Blocks "${upstream_ntp_servers}"
  Render_Template "${tmpl}" "${out}" || return 1
  echo "${out}"
}

# 生成 Client 角色配置
Generate_Client_Conf() {
  local tmpl="${script_dir}/config/chrony-client.conf.template"
  local out="${script_dir}/config/chrony.conf.rendered"
  local sources=""

  # 路径变量未初始化时先探测，避免渲染出空的 driftfile/keyfile
  { [ -z "${drift_file}" ] || [ -z "${chrony_keys}" ]; } && Detect_Chrony_Path

  # 集群模式优先使用内网 Server，单机模式使用公网上游
  if [ "${deploy_mode}" == 'cluster' ] && [ -n "${ntp_server_hosts}" ]; then
    sources="${ntp_server_hosts}"
  else
    sources="${upstream_ntp_servers}"
  fi

  if [ -z "${sources}" ]; then
    echo "${CFAILURE}未配置任何时间源，请设置 upstream_ntp_servers 或 ntp_server_hosts${CEND}"
    return 1
  fi

  Build_Blocks "${sources}"
  Render_Template "${tmpl}" "${out}" || return 1
  echo "${out}"
}

# 校验 chrony 配置文件语法
# 注意: Ubuntu/Debian 的 AppArmor profile(usr.sbin.chronyd) 只允许 chronyd 读取
#       /etc/chrony/** 等固定路径，直接校验 /tmp 下的渲染文件会报 Permission denied
#       （即使以 root 运行）。因此先把待校验文件复制到 chrony_conf 所在目录再校验。
Validate_Chrony_Conf() {
  local file="$1"
  command -v chronyd > /dev/null 2>&1 || return 0

  [ -z "${chrony_conf}" ] && Detect_Chrony_Path

  # 文件名刻意不以 .conf 结尾，避免被 confdir/sourcedir 的通配规则加载
  local probe="${file}"
  local conf_dir
  conf_dir=$(dirname "${chrony_conf}")
  if [ -d "${conf_dir}" ] || mkdir -p "${conf_dir}" 2>/dev/null; then
    probe="${conf_dir}/.chrony-validate.$$.tmp"
    /bin/cp -f "${file}" "${probe}" 2>/dev/null && chmod 644 "${probe}" || probe="${file}"
  fi

  # 优先使用 -p（打印配置并退出，不产生网络请求、不修改时钟）
  local msg rc
  msg=$(chronyd -p -f "${probe}" 2>&1)
  rc=$?

  # 部分老版本不支持 -p，退化为 -Q（只查询不修改时钟）
  if [ ${rc} -ne 0 ] && echo "${msg}" | grep -qiE 'invalid option|unrecognized|usage:'; then
    timeout 20 chronyd -Q -t 3 -f "${probe}" > /dev/null 2>&1 && rc=0
  fi

  [ "${probe}" != "${file}" ] && rm -f "${probe}"
  [ ${rc} -eq 0 ] && return 0

  echo "${CFAILURE}配置语法校验失败，详细信息：${CEND}"
  echo "${msg}" | head -20
  return 1
}

# 应用配置：校验 -> 备份现有配置 -> 覆盖 -> 重启服务
# 用法: Apply_Chrony_Conf <rendered_file>
Apply_Chrony_Conf() {
  local new_conf="$1"
  [ -f "${new_conf}" ] || { echo "${CFAILURE}待应用的配置文件不存在: ${new_conf}${CEND}"; return 1; }

  Validate_Chrony_Conf "${new_conf}" || {
    echo "${CFAILURE}已中止，现有配置未被修改${CEND}"
    return 1
  }

  # 首次安装保留发行版原始配置副本
  if [ -f "${chrony_conf}" ] && [ ! -f "${chrony_conf}.orig" ]; then
    /bin/cp -p "${chrony_conf}" "${chrony_conf}.orig"
    echo "${CMSG}已保留发行版原始配置: ${chrony_conf}.orig${CEND}"
  fi

  # 每次变更带时间戳备份
  if [ -f "${chrony_conf}" ]; then
    /bin/cp -p "${chrony_conf}" "${chrony_conf}.$(date +%Y%m%d%H%M%S)"
  fi

  mkdir -p "$(dirname "${chrony_conf}")"
  /bin/cp -f "${new_conf}" "${chrony_conf}"
  chmod 644 "${chrony_conf}"
  echo "${CSUCCESS}配置已写入 ${chrony_conf}${CEND}"

  systemctl restart "${chrony_service}" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${CFAILURE}服务重启失败${CEND}"
    journalctl -u "${chrony_service}" -n 20 --no-pager 2>/dev/null
    return 1
  fi
  return 0
}

# 按角色生成并应用配置
Apply_Role_Conf() {
  local rendered
  if [ "${chrony_role}" == 'server' ]; then
    rendered=$(Generate_Server_Conf) || return 1
  else
    rendered=$(Generate_Client_Conf) || return 1
  fi
  # 函数内的提示信息可能混入，取最后一行作为文件路径
  rendered=$(echo "${rendered}" | tail -1)
  Apply_Chrony_Conf "${rendered}"
}
