#!/bin/bash
# 交互输入辅助函数
# Author: DMP OPS
#
# 说明: 提供"按任意键继续"等交互功能

# 读取单个字符
get_char() {
  SAVEDSTTY=$(stty -g)
  stty -echo
  stty cbreak
  dd if=/dev/tty bs=1 count=1 2>/dev/null
  stty -raw
  stty echo
  stty $SAVEDSTTY
}

# 按任意键继续
Press_Any_Key() {
  echo ""
  echo -n "Press any key to continue..."
  get_char
  echo ""
}

# 确认操作 (y/n)
Confirm_Action() {
  local prompt=${1:-"Are you sure?"}
  local default=${2:-"n"}
  
  while :; do
    if [ "${default}" == "y" ]; then
      read -e -p "${prompt} [Y/n]: " answer
      answer=${answer:-y}
    else
      read -e -p "${prompt} [y/N]: " answer
      answer=${answer:-n}
    fi
    
    case "${answer,,}" in
      y|yes)
        return 0
        ;;
      n|no)
        return 1
        ;;
      *)
        echo "Please answer y or n."
        ;;
    esac
  done
}

# 输入密码（带验证）
Input_Password() {
  local prompt=${1:-"Please input password"}
  local min_length=${2:-5}
  
  while :; do
    echo ""
    read -e -p "${prompt}: " password
    
    # 检查特殊字符
    if [ -n "$(echo ${password} | grep '[+|&]')" ]; then
      echo "${CWARNING}Password cannot contain + or &${CEND}"
      continue
    fi
    
    # 检查长度
    if (( ${#password} < ${min_length} )); then
      echo "${CWARNING}Password must be at least ${min_length} characters!${CEND}"
      continue
    fi
    
    echo "${password}"
    return 0
  done
}

# 生成随机密码
Generate_Password() {
  local length=${1:-8}
  < /dev/urandom tr -dc A-Za-z0-9 | head -c${length}
}
