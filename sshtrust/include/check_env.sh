#!/bin/bash
# 环境检测
# 项目: sshtrust

# 检测 sshpass
Check_Sshpass() {
  if command -v sshpass &> /dev/null; then
    echo "${CSUCCESS}[OK] sshpass is installed${CEND}"
    return 0
  else
    echo "${CWARNING}[WARNING] sshpass is not installed${CEND}"
    echo "Installing sshpass..."

    case "${Family}" in
      rhel)
        ${PM} -y install sshpass 2>/dev/null
        ;;
      debian|ubuntu)
        ${PM} -y install sshpass 2>/dev/null
        ;;
    esac

    if command -v sshpass &> /dev/null; then
      echo "${CSUCCESS}[OK] sshpass installed successfully${CEND}"
      return 0
    else
      echo "${CFAILURE}[ERROR] Failed to install sshpass${CEND}"
      echo "Please install sshpass manually:"
      echo "  RHEL/CentOS: yum install sshpass"
      echo "  Debian/Ubuntu: apt-get install sshpass"
      return 1
    fi
  fi
}

# 检测 SSH 客户端工具
Check_SshClient() {
  local missing=0

  for cmd in ssh ssh-keygen ssh-copy-id; do
    if ! command -v ${cmd} &> /dev/null; then
      echo "${CFAILURE}[ERROR] ${cmd} not found${CEND}"
      missing=1
    fi
  done

  if [ "${missing}" -eq 1 ]; then
    echo "${CFAILURE}SSH client tools are required but not all found${CEND}"
    echo "Please install openssh-client:"
    echo "  RHEL/CentOS: yum install openssh-clients"
    echo "  Debian/Ubuntu: apt-get install openssh-client"
    return 1
  fi

  echo "${CSUCCESS}[OK] SSH client tools are available${CEND}"
  return 0
}

# 检测本机 SSH 密钥对
Check_SshKey() {
  local key_file=$(eval echo "${ssh_key_file}")

  if [ -f "${key_file}" ] && [ -f "${key_file}.pub" ]; then
    echo "${CSUCCESS}[OK] SSH key pair exists: ${key_file}${CEND}"
    return 0
  else
    echo "${CWARNING}[WARNING] SSH key pair not found at ${key_file}${CEND}"
    return 1
  fi
}

# 生成本机 SSH 密钥对
Generate_Key() {
  local key_file=$(eval echo "${ssh_key_file}")
  local key_dir=$(dirname "${key_file}")

  # 确保 .ssh 目录存在
  if [ ! -d "${key_dir}" ]; then
    mkdir -p "${key_dir}"
    chmod 700 "${key_dir}"
  fi

  # 检查是否已存在密钥
  if [ -f "${key_file}" ] && [ -f "${key_file}.pub" ]; then
    echo "${CWARNING}SSH key pair already exists: ${key_file}${CEND}"
    read -e -p "Overwrite existing key pair? [y/n]: " overwrite
    [ "${overwrite}" != "y" ] && {
      echo "Skipped key generation."
      return 0
    }
    rm -f "${key_file}" "${key_file}.pub"
  fi

  echo "${CMSG}Generating SSH key pair (${ssh_key_type}, ${ssh_key_bits} bits)...${CEND}"

  local keygen_opts=""
  case "${ssh_key_type}" in
    rsa)
      keygen_opts="-t rsa -b ${ssh_key_bits}"
      ;;
    ed25519)
      keygen_opts="-t ed25519"
      ;;
    ecdsa)
      keygen_opts="-t ecdsa -b ${ssh_key_bits}"
      ;;
    *)
      echo "${CFAILURE}Unsupported key type: ${ssh_key_type}${CEND}"
      return 1
      ;;
  esac

  ssh-keygen ${keygen_opts} -f "${key_file}" -N "" -C "${ssh_user}@$(hostname)" 2>/dev/null

  if [ $? -eq 0 ] && [ -f "${key_file}.pub" ]; then
    echo "${CSUCCESS}SSH key pair generated: ${key_file}${CEND}"
    return 0
  else
    echo "${CFAILURE}Failed to generate SSH key pair${CEND}"
    return 1
  fi
}

# 检测所有依赖
Check_All() {
  echo "${CMSG}=== Checking Dependencies ===${CEND}"

  Check_SshClient || return 1
  Check_Sshpass || return 1

  if ! Check_SshKey; then
    echo ""
    echo "${CMSG}SSH key pair is required for trust setup.${CEND}"
    read -e -p "Generate key pair now? [y/n]: " gen_key
    [ "${gen_key}" == "y" ] && {
      Generate_Key || return 1
    } || {
      echo "${CFAILURE}SSH key pair is required. Aborting.${CEND}"
      return 1
    }
  fi

  echo "${CSUCCESS}=== All dependencies satisfied ===${CEND}"
  return 0
}
