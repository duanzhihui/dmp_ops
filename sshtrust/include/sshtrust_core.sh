#!/bin/bash
# SSH 互信核心功能模块
# 项目: sshtrust

# 解析主机字符串
# 支持格式: host / user@host / user@host:port / host:port
# 输出变量: _parse_user _parse_host _parse_port
Parse_Host() {
  local input=$1
  _parse_user=""
  _parse_host=""
  _parse_port=""

  # 提取用户（如果存在 user@host 形式）
  if [[ "${input}" == *@* ]]; then
    _parse_user="${input%%@*}"
    local rest="${input#*@}"
  else
    _parse_user="${ssh_user}"
    local rest="${input}"
  fi

  # 提取端口（如果存在 host:port 形式）
  if [[ "${rest}" == *:* ]]; then
    _parse_host="${rest%%:*}"
    _parse_port="${rest#*:}"
  else
    _parse_host="${rest}"
    _parse_port="${ssh_port}"
  fi
}

# 获取本机公钥内容
Get_Local_PubKey() {
  local key_file=$(eval echo "${ssh_key_file}")
  if [ -f "${key_file}.pub" ]; then
    cat "${key_file}.pub"
  else
    echo "${CFAILURE}Public key not found: ${key_file}.pub${CEND}"
    return 1
  fi
}

# 保存配置到 options.conf
Save_Config() {
  # trust_hosts 含空格，必须加引号，否则 source 时后续 IP 会被当成命令执行
  # 使用 | 作为 sed 分隔符，避免 trust_hosts 中的 @ (user@host) 冲突
  sed -i "s|^trust_hosts=.*|trust_hosts=\"${trust_hosts}\"|" "${script_dir}/options.conf"
  sed -i "s|^trust_mode=.*|trust_mode=${trust_mode}|" "${script_dir}/options.conf"
  sed -i "s|^ssh_user=.*|ssh_user=${ssh_user}|" "${script_dir}/options.conf"
  sed -i "s|^ssh_port=.*|ssh_port=${ssh_port}|" "${script_dir}/options.conf"
}

# 检查主机是否已在 trust_hosts 列表中
Host_In_List() {
  local target=$1
  for h in ${trust_hosts}; do
    # 比较主机部分（去掉用户和端口）
    local h_host h_input
    if [[ "${h}" == *@* ]]; then
      h_host="${h#*@}"
    else
      h_host="${h}"
    fi
    # 去掉端口
    h_host="${h_host%%:*}"

    if [[ "${target}" == *@* ]]; then
      h_input="${target#*@}"
    else
      h_input="${target}"
    fi
    h_input="${h_input%%:*}"

    [ "${h_host}" == "${h_input}" ] && return 0
  done
  return 1
}

# 添加单台主机互信
# 参数: $1=主机字符串 $2=密码 $3=per_host_pwd标志 $4=密码序号(用于密码文件模式)
Add_Trust_Single() {
  local host_str=$1
  local password=$2
  local per_host_pwd=${3:-0}
  local pwd_index=${4:-0}

  Parse_Host "${host_str}"
  local remote_user="${_parse_user}"
  local remote_host="${_parse_host}"
  local remote_port="${_parse_port}"

  echo "${CMSG}--- Adding trust: ${remote_user}@${remote_host}:${remote_port} ---${CEND}"

  # 密码文件模式：按序号从数组取密码
  if [ ${#cli_passwords[@]} -gt 0 ] && [ ${pwd_index} -lt ${#cli_passwords[@]} ]; then
    password="${cli_passwords[${pwd_index}]}"
  fi

  # 逐台输入密码模式（交互）
  if [ "${per_host_pwd}" -eq 1 ] && [ -z "${password}" ]; then
    read -s -e -p "Enter password for ${remote_user}@${remote_host}: " password
    echo ""
  fi

  if [ -z "${password}" ]; then
    echo "${CFAILURE}Password is required for ${remote_host}${CEND}"
    return 1
  fi

  # 幂等检查：测试是否已可免密登录
  if ssh -p ${remote_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
       -o PasswordAuthentication=no -o BatchMode=yes \
       ${remote_user}@${remote_host} "true" 2>/dev/null; then
    echo "${CWARNING}Trust already exists: ${remote_user}@${remote_host}${CEND}"
    return 0
  fi

  # 使用 sshpass + ssh-copy-id 分发公钥（捕获 stderr 供失败时诊断）
  local copy_err
  copy_err=$(sshpass -p "${password}" ssh-copy-id -p ${remote_port} \
    -o StrictHostKeyChecking=no \
    ${remote_user}@${remote_host} 2>&1)
  local copy_rc=$?

  if [ ${copy_rc} -ne 0 ]; then
    echo "${CFAILURE}Failed to copy SSH key to ${remote_user}@${remote_host}${CEND}"
    # 输出真实错误原因，便于定位（密码错误/网络不通/端口错误等）
    [ -n "${copy_err}" ] && echo "  Reason: ${copy_err}" >&2
    return 1
  fi

  # 验证免密登录
  if ssh -p ${remote_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
       -o PasswordAuthentication=no -o BatchMode=yes \
       ${remote_user}@${remote_host} "echo ok" 2>/dev/null | grep -q "ok"; then
    echo "${CSUCCESS}Trust established: ${remote_user}@${remote_host}:${remote_port}${CEND}"
    return 0
  else
    echo "${CFAILURE}Trust verification failed: ${remote_user}@${remote_host}${CEND}"
    return 1
  fi
}

# 添加多台主机互信（one-way 模式）
# 参数: $@=主机列表
Add_Trust() {
  local hosts=("$@")
  local success_count=0
  local fail_count=0
  local added_hosts=""

  if [ ${#hosts[@]} -eq 0 ]; then
    echo "${CFAILURE}No hosts specified${CEND}"
    return 1
  fi

  echo "${CMSG}=== Adding SSH Trust (one-way mode) ===${CEND}"
  echo "Hosts to add: ${#hosts[@]}"
  echo ""

  # 询问密码策略
  local password=""
  local per_host_pwd=0

  # 优先使用命令行传入的密码
  if [ -n "${cli_password}" ]; then
    password="${cli_password}"
  elif [ -n "${cli_password_file}" ]; then
    # 密码文件模式：每行一个密码，对应每台主机
    if [ ! -f "${cli_password_file}" ]; then
      echo "${CFAILURE}Password file not found: ${cli_password_file}${CEND}"
      return 1
    fi
    cli_passwords=()
    while IFS= read -r line || [ -n "$line" ]; do
      line=$(echo "${line}" | sed 's/#.*//' | xargs)
      [ -z "${line}" ] && continue
      cli_passwords+=("${line}")
    done < "${cli_password_file}"
    echo "${CMSG}Loaded ${#cli_passwords[@]} passwords from file${CEND}"
    if [ ${#cli_passwords[@]} -ne ${#hosts[@]} ]; then
      echo "${CWARNING}Warning: ${#cli_passwords[@]} passwords for ${#hosts[@]} hosts (mismatch)${CEND}"
    fi
  elif [ "${quiet_mode}" -ne 1 ]; then
    echo "${CMSG}Password options:${CEND}"
    echo "  1) Use same password for all hosts"
    echo "  2) Enter password per host"
    echo ""
    read -e -p "Choice [1-2, default: 1]: " pwd_choice
    pwd_choice=${pwd_choice:-1}
    case "${pwd_choice}" in
      1)
        read -s -e -p "Enter SSH password: " password
        echo ""
        ;;
      2)
        per_host_pwd=1
        ;;
      *)
        echo "${CWARNING}Invalid choice, using same password${CEND}"
        read -s -e -p "Enter SSH password: " password
        echo ""
        ;;
    esac
  else
    echo "${CFAILURE}No password provided. Use --password or --password-file in quiet mode.${CEND}"
    return 1
  fi

  local idx=0
  for host_str in "${hosts[@]}"; do
    [ -z "${host_str}" ] && continue

    if Add_Trust_Single "${host_str}" "${password}" "${per_host_pwd}" "${idx}"; then
      success_count=$((success_count + 1))
      # 添加到 trust_hosts（如果不在列表中）
      if ! Host_In_List "${host_str}"; then
        if [ -n "${trust_hosts}" ]; then
          trust_hosts="${trust_hosts} ${host_str}"
        else
          trust_hosts="${host_str}"
        fi
        added_hosts="${added_hosts} ${host_str}"
      fi
    else
      fail_count=$((fail_count + 1))
    fi
    idx=$((idx + 1))
    echo ""
  done

  # 保存配置
  if [ -n "${added_hosts}" ]; then
    Save_Config
  fi

  # 结果摘要
  echo "${CMSG}=== Summary ===${CEND}"
  echo "  Success: ${CSUCCESS}${success_count}${CEND}"
  echo "  Failed:  ${CFAILURE}${fail_count}${CEND}"
  [ -n "${added_hosts}" ] && echo "  Added:  ${added_hosts}"
  echo "  Total trust hosts: ${trust_hosts}"

  return ${fail_count}
}

# 从文件批量导入主机列表并添加互信
# 参数: $1=文件路径
Add_Trust_From_File() {
  local file=$1

  if [ -z "${file}" ]; then
    echo "${CFAILURE}No file specified${CEND}"
    return 1
  fi

  if [ ! -f "${file}" ]; then
    echo "${CFAILURE}File not found: ${file}${CEND}"
    return 1
  fi

  echo "${CMSG}=== Importing hosts from file: ${file} ===${CEND}"

  local hosts=()
  local line_num=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))
    # 跳过空行和注释行
    line=$(echo "${line}" | sed 's/#.*//' | xargs)
    [ -z "${line}" ] && continue
    hosts+=("${line}")
  done < "${file}"

  if [ ${#hosts[@]} -eq 0 ]; then
    echo "${CWARNING}No valid hosts found in file${CEND}"
    return 1
  fi

  echo "Found ${#hosts[@]} hosts in file"
  echo ""

  Add_Trust "${hosts[@]}"
  return $?
}

# 删除单台主机互信
# 参数: $1=主机字符串
Remove_Trust_Single() {
  local host_str=$1

  Parse_Host "${host_str}"
  local remote_user="${_parse_user}"
  local remote_host="${_parse_host}"
  local remote_port="${_parse_port}"

  echo "${CMSG}--- Removing trust: ${remote_user}@${remote_host}:${remote_port} ---${CEND}"

  local pubkey=$(Get_Local_PubKey)
  [ -z "${pubkey}" ] && return 1

  # 尝试通过已有免密连接移除公钥
  local key_comment=$(echo "${pubkey}" | awk '{print $3}')
  local key_prefix=$(echo "${pubkey}" | awk '{print $1, $2}')

  ssh -p ${remote_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    -o PasswordAuthentication=no -o BatchMode=yes \
    ${remote_user}@${remote_host} \
    "sed -i '/${key_prefix//\//\\/}/d' ~/.ssh/authorized_keys 2>/dev/null" 2>/dev/null

  if [ $? -ne 0 ]; then
    echo "${CWARNING}Cannot connect to ${remote_host} via passwordless SSH${CEND}"
    echo "The host may be unreachable or trust was already removed."
    return 1
  fi

  # 验证免密已失效
  if ssh -p ${remote_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
       -o PasswordAuthentication=no -o BatchMode=yes \
       ${remote_user}@${remote_host} "true" 2>/dev/null; then
    echo "${CWARNING}Trust may still be active: ${remote_user}@${remote_host}${CEND}"
    echo "The remote authorized_keys may contain other entries for this host."
  else
    echo "${CSUCCESS}Trust removed: ${remote_user}@${remote_host}:${remote_port}${CEND}"
  fi

  return 0
}

# 删除多台主机互信
# 参数: $@=主机列表
Remove_Trust() {
  local hosts=("$@")
  local success_count=0
  local fail_count=0
  local removed_hosts=""

  if [ ${#hosts[@]} -eq 0 ]; then
    echo "${CFAILURE}No hosts specified${CEND}"
    return 1
  fi

  echo "${CMSG}=== Removing SSH Trust ===${CEND}"
  echo "Hosts to remove: ${#hosts[@]}"
  echo ""

  for host_str in "${hosts[@]}"; do
    [ -z "${host_str}" ] && continue

    if Remove_Trust_Single "${host_str}"; then
      success_count=$((success_count + 1))
    else
      fail_count=$((fail_count + 1))
    fi

    # 从 trust_hosts 中移除（无论连接是否成功）
    Parse_Host "${host_str}"
    local target_host="${_parse_host}"
    local new_hosts=""
    for h in ${trust_hosts}; do
      Parse_Host "${h}"
      [ "${_parse_host}" != "${target_host}" ] && new_hosts="${new_hosts} ${h}"
    done
    trust_hosts=$(echo "${new_hosts}" | xargs)
    removed_hosts="${removed_hosts} ${host_str}"
    echo ""
  done

  # 保存配置
  Save_Config

  # 结果摘要
  echo "${CMSG}=== Summary ===${CEND}"
  echo "  Success: ${CSUCCESS}${success_count}${CEND}"
  echo "  Failed:  ${CFAILURE}${fail_count}${CEND}"
  [ -n "${removed_hosts}" ] && echo "  Removed: ${removed_hosts}"
  echo "  Remaining trust hosts: ${trust_hosts}"

  return ${fail_count}
}

# 列出当前互信配置
List_Trust() {
  echo "${CMSG}=== SSH Trust Configuration ===${CEND}"
  echo ""
  echo "  Mode:       ${trust_mode}"
  echo "  User:       ${ssh_user}"
  echo "  Port:       ${ssh_port}"
  echo "  Key File:   ${ssh_key_file}"
  echo "  Key Type:   ${ssh_key_type}"
  echo ""

  if [ -z "${trust_hosts}" ]; then
    echo "  Trust Hosts: ${CWARNING}(empty)${CEND}"
    echo ""
    return 0
  fi

  echo "  Trust Hosts:"
  local idx=1
  for h in ${trust_hosts}; do
    Parse_Host "${h}"
    printf "    %d) %s@%s:%s\n" "${idx}" "${_parse_user}" "${_parse_host}" "${_parse_port}"
    idx=$((idx + 1))
  done
  echo ""
}

# 检查互信连通性
Check_Trust() {
  echo "${CMSG}=== Checking SSH Trust Connectivity ===${CEND}"
  echo ""

  if [ -z "${trust_hosts}" ]; then
    echo "${CWARNING}No trust hosts configured${CEND}"
    return 0
  fi

  local total=0
  local ok_count=0
  local fail_count=0

  for h in ${trust_hosts}; do
    Parse_Host "${h}"
    total=$((total + 1))

    printf "  %-30s " "${_parse_user}@${_parse_host}:${_parse_port}"

    if ssh -p ${_parse_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
         -o PasswordAuthentication=no -o BatchMode=yes \
         ${_parse_user}@${_parse_host} "echo ok" 2>/dev/null | grep -q "ok"; then
      echo "${CSUCCESS}[OK]${CEND}"
      ok_count=$((ok_count + 1))
    else
      echo "${CFAILURE}[FAIL]${CEND}"
      fail_count=$((fail_count + 1))
    fi
  done

  echo ""
  echo "${CMSG}=== Summary ===${CEND}"
  echo "  Total:    ${total}"
  echo "  Success:  ${CSUCCESS}${ok_count}${CEND}"
  echo "  Failed:   ${CFAILURE}${fail_count}${CEND}"

  return ${fail_count}
}

# 全互信（mesh 模式）
# 本机 → 所有远程主机 + 所有远程主机之间互相建立互信
Setup_Mesh() {
  echo "${CMSG}=== Setting up Mesh Trust (full mutual trust) ===${CEND}"
  echo ""

  if [ -z "${trust_hosts}" ]; then
    echo "${CFAILURE}No trust hosts configured${CEND}"
    echo "Please add hosts first using --add"
    return 1
  fi

  local all_hosts=()
  # 将本机加入列表
  local local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  if [ -n "${local_ip}" ]; then
    all_hosts+=("${ssh_user}@${local_ip}")
  fi
  for h in ${trust_hosts}; do
    all_hosts+=("${h}")
  done

  local total_hosts=${#all_hosts[@]}
  echo "Total hosts in mesh: ${total_hosts}"
  echo ""

  # 询问密码（用于在远程主机上执行命令）
  local password=""
  if [ "${quiet_mode}" -ne 1 ]; then
    read -s -e -p "Enter SSH password for remote hosts: " password
    echo ""
  fi

  if [ -z "${password}" ]; then
    echo "${CFAILURE}Password is required for mesh setup${CEND}"
    return 1
  fi

  # 阶段1: 本机 → 所有远程主机建立互信
  echo "${CMSG}=== Phase 1: Local → All remote hosts ===${CEND}"
  local phase1_hosts=()
  for h in "${all_hosts[@]}"; do
    Parse_Host "${h}"
    # 跳过本机
    [ "${_parse_host}" == "${local_ip}" ] && continue
    [ "${_parse_host}" == "127.0.0.1" ] && continue
    [ "${_parse_host}" == "localhost" ] && continue
    phase1_hosts+=("${h}")
  done

  if [ ${#phase1_hosts[@]} -gt 0 ]; then
    Add_Trust "${phase1_hosts[@]}" || true
  fi
  echo ""

  # 阶段2: 在每台远程主机上生成密钥对
  echo "${CMSG}=== Phase 2: Generate key pairs on remote hosts ===${CEND}"
  for h in "${all_hosts[@]}"; do
    Parse_Host "${h}"
    [ "${_parse_host}" == "${local_ip}" ] && continue
    [ "${_parse_host}" == "127.0.0.1" ] && continue
    [ "${_parse_host}" == "localhost" ] && continue

    printf "  %-30s " "${_parse_user}@${_parse_host}:${_parse_port}"

    sshpass -p "${password}" ssh -p ${_parse_port} -o StrictHostKeyChecking=no \
      ${_parse_user}@${_parse_host} \
      "[ -f ~/.ssh/id_rsa.pub ] || { mkdir -p ~/.ssh && chmod 700 ~/.ssh && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N '' -q; }" 2>/dev/null

    if [ $? -eq 0 ]; then
      echo "${CSUCCESS}[OK]${CEND}"
    else
      echo "${CFAILURE}[FAIL]${CEND}"
    fi
  done
  echo ""

  # 阶段3: 逐台将所有其他主机的公钥分发到每台机器
  echo "${CMSG}=== Phase 3: Cross-distribute public keys ===${CEND}"

  # 收集所有主机的公钥
  declare -A host_pubkeys
  for h in "${all_hosts[@]}"; do
    Parse_Host "${h}"
    local host_key="${_parse_user}@${_parse_host}:${_parse_port}"

    if [ "${_parse_host}" == "${local_ip}" ] || [ "${_parse_host}" == "127.0.0.1" ] || [ "${_parse_host}" == "localhost" ]; then
      host_pubkeys["${host_key}"]=$(Get_Local_PubKey)
    else
      # 通过免密连接获取远程主机公钥
      host_pubkeys["${host_key}"]=$(ssh -p ${_parse_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -o PasswordAuthentication=no -o BatchMode=yes \
        ${_parse_user}@${_parse_host} "cat ~/.ssh/id_rsa.pub" 2>/dev/null)
    fi
  done

  # 逐台分发
  for target_h in "${all_hosts[@]}"; do
    Parse_Host "${target_h}"
    local target_key="${_parse_user}@${_parse_host}:${_parse_port}"

    # 跳过本机
    [ "${_parse_host}" == "${local_ip}" ] && continue
    [ "${_parse_host}" == "127.0.0.1" ] && continue
    [ "${_parse_host}" == "localhost" ] && continue

    printf "  Distributing to %-30s\n" "${target_key}"

    for source_h in "${all_hosts[@]}"; do
      Parse_Host "${source_h}"
      local source_key="${_parse_user}@${_parse_host}:${_parse_port}"

      # 跳过自身
      [ "${source_key}" == "${target_key}" ] && continue

      local pubkey="${host_pubkeys["${source_key}"]}"
      [ -z "${pubkey}" ] && continue

      # 检查目标是否已有该公钥
      local key_prefix=$(echo "${pubkey}" | awk '{print $1, $2}')
      local escaped_key=$(echo "${key_prefix}" | sed 's/[\/&]/\\&/g')

      ssh -p ${_parse_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -o PasswordAuthentication=no -o BatchMode=yes \
        ${_parse_user}@${_parse_host} \
        "grep -q '${key_prefix}' ~/.ssh/authorized_keys 2>/dev/null || echo '${pubkey}' >> ~/.ssh/authorized_keys" 2>/dev/null

      if [ $? -eq 0 ]; then
        printf "    %-30s %s\n" "${source_key}" "${CSUCCESS}[OK]${CEND}"
      else
        printf "    %-30s %s\n" "${source_key}" "${CFAILURE}[FAIL]${CEND}"
      fi
    done
  done
  echo ""

  # 更新配置
  trust_mode="mesh"
  Save_Config

  # 阶段4: 验证
  echo "${CMSG}=== Phase 4: Verification ===${CEND}"
  echo "Verifying mesh connectivity matrix..."
  echo ""

  local verify_ok=0
  local verify_fail=0

  for src_h in "${all_hosts[@]}"; do
    Parse_Host "${src_h}"
    local src_host="${_parse_host}"
    local src_user="${_parse_user}"
    local src_port="${_parse_port}"

    for dst_h in "${all_hosts[@]}"; do
      Parse_Host "${dst_h}"
      local dst_host="${_parse_host}"
      local dst_user="${_parse_user}"
      local dst_port="${_parse_port}"

      [ "${src_host}" == "${dst_host}" ] && continue

      # 本机直接测试
      if [ "${src_host}" == "${local_ip}" ] || [ "${src_host}" == "127.0.0.1" ] || [ "${src_host}" == "localhost" ]; then
        if ssh -p ${dst_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
             -o PasswordAuthentication=no -o BatchMode=yes \
             ${dst_user}@${dst_host} "true" 2>/dev/null; then
          verify_ok=$((verify_ok + 1))
        else
          verify_fail=$((verify_fail + 1))
          printf "  %s@%s → %s@%s  %s\n" "${src_user}" "${src_host}" "${dst_user}" "${dst_host}" "${CFAILURE}[FAIL]${CEND}"
        fi
      else
        # 远程主机测试到其他主机
        if [ "${dst_host}" == "${local_ip}" ] || [ "${dst_host}" == "127.0.0.1" ] || [ "${dst_host}" == "localhost" ]; then
          # 测试远程→本机
          ssh -p ${src_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -o PasswordAuthentication=no -o BatchMode=yes \
            ${src_user}@${src_host} \
            "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no -o BatchMode=yes ${dst_user}@${local_ip} 'true'" 2>/dev/null
        else
          # 测试远程→远程
          ssh -p ${src_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -o PasswordAuthentication=no -o BatchMode=yes \
            ${src_user}@${src_host} \
            "ssh -p ${dst_port} -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no -o BatchMode=yes ${dst_user}@${dst_host} 'true'" 2>/dev/null
        fi

        if [ $? -eq 0 ]; then
          verify_ok=$((verify_ok + 1))
        else
          verify_fail=$((verify_fail + 1))
          printf "  %s@%s → %s@%s  %s\n" "${src_user}" "${src_host}" "${dst_user}" "${dst_host}" "${CFAILURE}[FAIL]${CEND}"
        fi
      fi
    done
  done

  echo ""
  echo "${CMSG}=== Mesh Setup Summary ===${CEND}"
  echo "  Total hosts:     ${total_hosts}"
  echo "  Pairs verified:  $((verify_ok + verify_fail))"
  echo "  Success:         ${CSUCCESS}${verify_ok}${CEND}"
  echo "  Failed:          ${CFAILURE}${verify_fail}${CEND}"
  echo "  Mode:            ${trust_mode}"

  return ${verify_fail}
}
