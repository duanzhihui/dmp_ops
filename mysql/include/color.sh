#!/bin/bash
# 终端颜色定义
# Author: DMP OPS
#
# 说明: 提供统一的彩色输出变量，兼容不同终端

# 检测 echo 命令
echo=echo
for cmd in echo /bin/echo; do
  $cmd >/dev/null 2>&1 || continue
  if ! $cmd -e "" | grep -qE '^-e'; then
    echo=$cmd
    break
  fi
done

# CSI 转义序列
CSI=$($echo -e "\033[")
CEND="${CSI}0m"
CDGREEN="${CSI}32m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"
CMAGENTA="${CSI}1;35m"
CCYAN="${CSI}1;36m"

# 语义化颜色别名
CSUCCESS="${CDGREEN}"
CFAILURE="${CRED}"
CQUESTION="${CMAGENTA}"
CWARNING="${CYELLOW}"
CMSG="${CCYAN}"
