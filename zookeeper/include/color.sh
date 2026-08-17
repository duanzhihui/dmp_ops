#!/bin/bash
# 终端颜色定义
# 项目: oneinstack/zookeeper

# 颜色代码
CSI=$'\033['
CEND="${CSI}0m"
CSUCCESS="${CSI}32m"      # 绿色 — 成功
CFAILURE="${CSI}1;31m"    # 红色 — 失败
CWARNING="${CSI}1;33m"    # 黄色 — 警告
CMSG="${CSI}1;36m"        # 青色 — 信息
CQUESTION="${CSI}1;35m"   # 紫色 — 问题
