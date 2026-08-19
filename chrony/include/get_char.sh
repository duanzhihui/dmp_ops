#!/bin/bash
# 交互输入辅助函数
# 项目: dmp_ops/chrony

# 读取单个字符（用于"按任意键继续"）
get_char() {
  SAVEDSTTY=$(stty -g)
  stty -echo
  stty cbreak
  dd if=/dev/tty bs=1 count=1 2> /dev/null
  stty -raw
  stty echo
  stty "${SAVEDSTTY}"
}

# 通用 y/n 确认
# 用法: Confirm "提示语" && do_something
Confirm() {
  local prompt="$1"
  local answer
  while :; do
    read -e -p "${prompt} [y/n]: " answer
    [[ "${answer}" =~ ^[yn]$ ]] && break
    echo "${CWARNING}请输入 y 或 n${CEND}"
  done
  [ "${answer}" == 'y' ]
}
