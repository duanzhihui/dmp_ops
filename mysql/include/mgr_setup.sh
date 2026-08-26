#!/bin/bash
# MySQL MGR (Group Replication) 操作模块库
# Author: DMP OPS
#
# 说明: MGR 单主模式（single-primary）的引导/加入/退出/状态/切换操作。
#       单主模式 = 一写多读 + 主挂自动选新主，并非"双写双活"。
#       多主双写需改 group_replication_single_primary_mode=OFF，当前未实现。

# MySQL 客户端封装（统一带密码、socket）
MGR_Mysql() {
  ${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} --socket=/tmp/mysql.sock "$@"
}

# 检测 MySQL 版本，输出 8.0 或 8.4，用于适配 SQL 语法
MGR_Version_Adapt() {
  if [ -z "${db_version_main}" ]; then
    Get_DB_Version
  fi
  echo "${db_version_main}"
}

# 前置条件检查（不执行任何变更）
MGR_Check_Prerequisites() {
  local ok=1

  if [ "${mgr_enable}" != "1" ]; then
    echo "${CFAILURE}[FAIL] mgr_enable != 1 in options.conf${CEND}"
    echo "  修复: 编辑 options.conf 设置 mgr_enable=1，并填好 MGR 配置段后重新安装/重启"
    ok=0
  fi

  if [ -z "${mgr_group_name}" ]; then
    echo "${CFAILURE}[FAIL] mgr_group_name is empty${CEND}"
    echo "  修复: 运行 uuidgen 生成 UUID，填入 options.conf 的 mgr_group_name（全组一致）"
    ok=0
  fi

  if [ -z "${mgr_local_address}" ]; then
    echo "${CFAILURE}[FAIL] mgr_local_address is empty${CEND}"
    echo "  修复: 填入本节点 group 通信地址，如 192.168.1.10:33061"
    ok=0
  fi

  if [ -z "${mgr_group_seeds}" ]; then
    echo "${CFAILURE}[FAIL] mgr_group_seeds is empty${CEND}"
    echo "  修复: 填入种子节点列表，如 192.168.1.10:33061,192.168.1.11:33061,192.168.1.12:33061"
    ok=0
  fi

  # 检查运行时参数
  local gtid_mode=$(MGR_Mysql -N -e "SELECT @@global.gtid_mode;" 2>/dev/null)
  local binlog_format=$(MGR_Mysql -N -e "SELECT @@global.binlog_format;" 2>/dev/null)
  local perf_schema=$(MGR_Mysql -N -e "SELECT @@global.performance_schema;" 2>/dev/null)

  if [ "${gtid_mode}" != "ON" ]; then
    echo "${CFAILURE}[FAIL] gtid_mode is ${gtid_mode:-empty}, must be ON${CEND}"
    ok=0
  fi
  if [ "${binlog_format}" != "ROW" ]; then
    echo "${CFAILURE}[FAIL] binlog_format is ${binlog_format:-empty}, must be ROW${CEND}"
    ok=0
  fi
  if [ "${perf_schema}" != "1" ]; then
    echo "${CFAILURE}[FAIL] performance_schema is ${perf_schema:-empty}, must be 1 (ON)${CEND}"
    ok=0
  fi

  # 检查插件是否安装
  local plugin_installed=$(MGR_Mysql -N -e \
    "SELECT COUNT(*) FROM information_schema.plugins WHERE plugin_name='group_replication';" 2>/dev/null)
  if [ "${plugin_installed}" != "1" ]; then
    echo "${CWARNING}[WARN] group_replication plugin not installed${CEND}"
    echo "  修复: 运行 ./mgr_setup.sh --install-plugin 或手动 INSTALL PLUGIN group_replication SONAME 'group_replication.so'"
    ok=0
  fi

  if [ ${ok} -eq 1 ]; then
    echo "${CSUCCESS}[OK] MGR prerequisites check passed${CEND}"
    return 0
  fi
  return 1
}

# 安装 group_replication 插件（幂等）
MGR_Install_Plugin() {
  local plugin_installed=$(MGR_Mysql -N -e \
    "SELECT COUNT(*) FROM information_schema.plugins WHERE plugin_name='group_replication';" 2>/dev/null)
  if [ "${plugin_installed}" == "1" ]; then
    echo "${CSUCCESS}[OK] group_replication plugin already installed${CEND}"
    return 0
  fi

  echo "${CMSG}Installing group_replication plugin...${CEND}"
  if MGR_Mysql -e "INSTALL PLUGIN group_replication SONAME 'group_replication.so';" 2>/dev/null; then
    echo "${CSUCCESS}group_replication plugin installed${CEND}"
    return 0
  fi
  echo "${CFAILURE}Failed to install group_replication plugin${CEND}"
  echo "  检查 plugin_dir 是否正确: SELECT @@plugin_dir;"
  return 1
}

# 创建/重置复制用户（用于 group_replication_recovery 通道）
# 参数 $1: binlog 控制标志，1=写 binlog（bootstrap 场景，用户需复制给 joiner）
#         0=不写 binlog（join 场景，避免生成本地 GTID 导致分叉）
MGR_Create_Recovery_User() {
  local binlog=${1:-1}

  # 密码留空时自动生成并回写 options.conf
  if [ -z "${mgr_recovery_pwd}" ]; then
    mgr_recovery_pwd=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)
    sed -i "s+^mgr_recovery_pwd.*+mgr_recovery_pwd='${mgr_recovery_pwd}'+" ${mysql_dir}/options.conf
    echo "${CMSG}Generated mgr_recovery_pwd and saved to options.conf${CEND}"
  fi

  echo "${CMSG}Creating/resetting recovery user '${mgr_recovery_user}'...${CEND}"

  # 确保可写: 上次 join 失败/异常退出可能残留 super_read_only=ON
  MGR_Mysql -e "SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;" 2>/dev/null

  local sql_prefix="" sql_suffix=""
  if [ "${binlog}" == "0" ]; then
    # join 场景: 不写 binlog，避免生成本地 GTID 导致与 group 分叉
    # （recovery 用户已由 clone 从 donor 复制过来，本地创建仅为兜底）
    sql_prefix="SET sql_log_bin=0;"
    sql_suffix="SET sql_log_bin=1;"
    echo "  ${CMSG}(join mode: sql_log_bin=0, 不生成本地 GTID)${CEND}"
  fi

  local err
  err=$(MGR_Mysql -e \
    "${sql_prefix} \
     CREATE USER IF NOT EXISTS '${mgr_recovery_user}'@'%' IDENTIFIED BY '${mgr_recovery_pwd}'; \
     ALTER USER '${mgr_recovery_user}'@'%' IDENTIFIED BY '${mgr_recovery_pwd}'; \
     GRANT REPLICATION SLAVE ON *.* TO '${mgr_recovery_user}'@'%'; \
     FLUSH PRIVILEGES; \
     ${sql_suffix}" 2>&1)

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Recovery user '${mgr_recovery_user}' ready${CEND}"
    return 0
  fi
  echo "${CFAILURE}Failed to create recovery user${CEND}"
  echo "  ${CWARNING}${err}${CEND}"
  echo "  排查: SELECT @@global.super_read_only, @@global.read_only; 若为 1 需 SET GLOBAL super_read_only=OFF"
  return 1
}

# 引导启动新 group（仅首个节点执行）
MGR_Bootstrap() {
  MGR_Check_Prerequisites || return 1
  MGR_Install_Plugin || return 1
  MGR_Create_Recovery_User 1 || return 1

  # 检查是否已在 group 中
  local cur_state=$(MGR_Mysql -N -e \
    "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=@@hostname;" 2>/dev/null)
  if [ "${cur_state}" == "ONLINE" ]; then
    echo "${CWARNING}[SKIP] This node is already ONLINE in a group${CEND}"
    return 0
  fi

  echo "${CMSG}Bootstrapping new MGR group...${CEND}"
  echo "  group_name: ${mgr_group_name}"
  echo "  local_addr: ${mgr_local_address}"

  MGR_Mysql -e \
    "SET GLOBAL group_replication_bootstrap_group=ON; \
     START GROUP_REPLICATION; \
     SET GLOBAL group_replication_bootstrap_group=OFF;"

  # 轮询等待节点变为 ONLINE
  local i=0
  local state=""
  while [ ${i} -lt 30 ]; do
    state=$(MGR_Mysql -N -e \
      "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=@@hostname;" 2>/dev/null)
    [ "${state}" == "ONLINE" ] && break
    sleep 1
    i=$((i + 1))
  done

  if [ "${state}" == "ONLINE" ]; then
    echo "${CSUCCESS}MGR group bootstrapped successfully!${CEND}"
    MGR_Status
    # 引导成功后自动改回 0，避免下次重启重复引导
    sed -i 's/^mgr_bootstrap=1/mgr_bootstrap=0/' ${mysql_dir}/options.conf
    echo "${CMSG}mgr_bootstrap has been reset to 0 in options.conf${CEND}"
    return 0
  fi
  echo "${CFAILURE}MGR bootstrap failed! Node state: ${state:-unknown}${CEND}"
  echo "  Check error log: ${db_data_dir}/mysql-error.log"
  return 1
}

# 加入现有 group
MGR_Join() {
  MGR_Check_Prerequisites || return 1
  MGR_Install_Plugin || return 1
  MGR_Create_Recovery_User 0 || return 1

  # 检查是否已在 group 中
  local cur_state=$(MGR_Mysql -N -e \
    "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=@@hostname;" 2>/dev/null)
  if [ "${cur_state}" == "ONLINE" ]; then
    echo "${CWARNING}[SKIP] This node is already ONLINE in a group${CEND}"
    return 0
  fi

  echo "${CMSG}Joining existing MGR group...${CEND}"
  echo "  group_name: ${mgr_group_name}"
  echo "  seeds:      ${mgr_group_seeds}"

  # 配置 recovery 通道凭据（8.0 用 CHANGE MASTER TO，8.4 用 CHANGE REPLICATION SOURCE TO）
  local ver=$(MGR_Version_Adapt)
  if [ "${ver}" == "8.4" ] || [ "${ver}" == "8.3" ] || [ "${ver}" == "8.2" ]; then
    MGR_Mysql -e \
      "CHANGE REPLICATION SOURCE TO SOURCE_USER='${mgr_recovery_user}', SOURCE_PASSWORD='${mgr_recovery_pwd}' FOR CHANNEL 'group_replication_recovery';" 2>/dev/null
  else
    MGR_Mysql -e \
      "CHANGE MASTER TO MASTER_USER='${mgr_recovery_user}', MASTER_PASSWORD='${mgr_recovery_pwd}' FOR CHANNEL 'group_replication_recovery';" 2>/dev/null
  fi

  MGR_Mysql -e "START GROUP_REPLICATION;"

  # 轮询等待节点变为 ONLINE
  local i=0
  local state=""
  while [ ${i} -lt 60 ]; do
    state=$(MGR_Mysql -N -e \
      "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=@@hostname;" 2>/dev/null)
    [ "${state}" == "ONLINE" ] && break
    sleep 1
    i=$((i + 1))
  done

  if [ "${state}" == "ONLINE" ]; then
    echo "${CSUCCESS}Joined MGR group successfully!${CEND}"
    MGR_Status
    return 0
  fi
  echo "${CFAILURE}Failed to join MGR group! Node state: ${state:-unknown}${CEND}"
  echo "  Check error log: ${db_data_dir}/mysql-error.log"
  return 1
}

# 重置本地 GTID 与 binlog（用于分叉节点恢复）
# 场景: 节点因本地存在 group 不认识的 GTID（如 recovery 用户创建产生的本地事务）
#       导致 join 失败，报错 MY-011526 / MY-011522。
# 本函数清空 gtid_executed 和 binlog，随后 --join 会触发 clone 重新全量同步。
MGR_Reset_Gtid() {
  # 若仍在 group 中则先退出
  local cur_state=$(MGR_Mysql -N -e \
    "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=@@hostname;" 2>/dev/null)
  if [ -n "${cur_state}" ]; then
    echo "${CMSG}Stopping group_replication before reset...${CEND}"
    MGR_Mysql -e "STOP GROUP_REPLICATION;" 2>/dev/null
    sleep 2
  fi

  # 展示当前 GTID 状态（便于确认）
  local gtid_executed=$(MGR_Mysql -N -e "SELECT @@global.gtid_executed;" 2>/dev/null)
  local server_uuid=$(MGR_Mysql -N -e "SELECT @@global.server_uuid;" 2>/dev/null)
  echo "${CMSG}Current gtid_executed: ${gtid_executed:-<empty>}${CEND}"
  echo "${CMSG}Local server_uuid:    ${server_uuid}${CEND}"

  # 确保可写: 上次 join 失败/异常退出可能残留 super_read_only=ON
  MGR_Mysql -e "SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;" 2>/dev/null

  # 版本适配: 8.4 用 RESET BINARY LOGS AND GTIDS，8.0 用 RESET MASTER
  local ver=$(MGR_Version_Adapt)
  echo "${CMSG}Resetting binary logs and GTID executed set (MySQL ${ver})...${CEND}"
  local err
  if [ "${ver}" == "8.4" ] || [ "${ver}" == "8.3" ] || [ "${ver}" == "8.2" ]; then
    err=$(MGR_Mysql -e "RESET BINARY LOGS AND GTIDS;" 2>&1)
  else
    err=$(MGR_Mysql -e "RESET MASTER;" 2>&1)
  fi

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}GTID and binary logs reset successfully${CEND}"
    echo "  ${CWARNING}注意: reset-gtid 只清空 GTID 和 binlog，不清空数据表。${CEND}"
    echo "  ${CWARNING}      若本地已有数据，join 时 MGR 会选增量恢复导致 1032 错误。${CEND}"
    echo "  ${CMSG}下一步: 先运行 ./mgr_setup.sh --clone 从 donor 全量克隆，再 ./mgr_setup.sh --join${CEND}"
    return 0
  fi
  echo "${CFAILURE}Failed to reset GTID${CEND}"
  echo "  ${CWARNING}${err}${CEND}"
  echo "  确保 group_replication 已停止、无复制通道运行"
  return 1
}

# 从 donor 全量克隆（用于 join 前的数据同步）
# 参数 $1: donor 地址，格式 host:port，默认取 mgr_group_seeds 第一个节点
MGR_Clone() {
  local donor=${1:-$(echo "${mgr_group_seeds}" | cut -d',' -f1)}
  # donor 格式是 ip:33061（group 通信端口），clone 需要 ip:3306（MySQL 数据端口）
  local donor_host=$(echo "${donor}" | cut -d':' -f1)
  local donor_port=3306

  # 若仍在 group 中则先退出
  local cur_state=$(MGR_Mysql -N -e \
    "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=@@hostname;" 2>/dev/null)
  if [ -n "${cur_state}" ]; then
    echo "${CMSG}Stopping group_replication before clone...${CEND}"
    MGR_Mysql -e "STOP GROUP_REPLICATION;" 2>/dev/null
    sleep 2
  fi

  # 确保可写: clone 要求 super_read_only=OFF
  MGR_Mysql -e "SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;" 2>/dev/null

  # 检查 clone plugin
  local clone_installed=$(MGR_Mysql -N -e \
    "SELECT COUNT(*) FROM information_schema.plugins WHERE plugin_name='clone';" 2>/dev/null)
  if [ "${clone_installed}" != "1" ]; then
    echo "${CFAILURE}[FAIL] clone plugin not installed${CEND}"
    echo "  修复: INSTALL PLUGIN clone SONAME 'mysql_clone.so';"
    return 1
  fi

  echo "${CMSG}Cloning from donor '${mgr_recovery_user}'@'${donor_host}:${donor_port}'...${CEND}"
  echo "  donor:      ${donor_host}:${donor_port}"
  echo "  recovery:   ${mgr_recovery_user}"

  # 密码为空则报错（clone 需要密码）
  if [ -z "${mgr_recovery_pwd}" ]; then
    echo "${CFAILURE}[FAIL] mgr_recovery_pwd is empty in options.conf${CEND}"
    echo "  修复: 先在 donor 节点运行 ./mgr_setup.sh --bootstrap 生成密码，或手动填入 options.conf"
    return 1
  fi

  local err
  MGR_Mysql -e "SET GLOBAL clone_valid_donor_list = '${donor_host}:${donor_port}';" 2>/dev/null
  # 注意 CLONE 语法: 'user'@'host':port，host 在引号内、port 在引号外（不可写成 'host:port'）
  err=$(MGR_Mysql -e "CLONE INSTANCE FROM '${mgr_recovery_user}'@'${donor_host}':${donor_port} IDENTIFIED BY '${mgr_recovery_pwd}';" 2>&1)

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Clone initiated successfully${CEND}"
    echo "  ${CMSG}mysqld 将自动重启，等待恢复...${CEND}"

    # clone 是物理全量复制（含 mysql 系统库），完成后本机 root 密码
    # 会被替换为 donor 的 root 密码。等待时两个密码都试。
    local i=0 ok=0
    sleep 3
    while [ ${i} -lt 120 ]; do
      if MGR_Mysql -e "SELECT 1;" >/dev/null 2>&1; then
        ok=1; break
      fi
      # 本地密码连不上时，尝试 donor 的 recovery 密码（clone 后 root 密码可能已变）
      if ${db_install_dir}/bin/mysql -uroot -p${mgr_recovery_pwd} --socket=/tmp/mysql.sock \
           -e "SELECT 1;" >/dev/null 2>&1; then
        ok=2; break
      fi
      sleep 1
      i=$((i + 1))
    done

    if [ ${ok} -eq 1 ]; then
      echo "${CSUCCESS}mysqld restarted after clone${CEND}"
      local gtid=$(MGR_Mysql -N -e "SELECT @@global.gtid_executed;" 2>/dev/null)
      echo "  ${CMSG}gtid_executed: ${gtid:-<empty>}${CEND}"
      echo "  ${CMSG}下一步: 运行 ./mgr_setup.sh --join 加入 group${CEND}"
      return 0
    fi

    if [ ${ok} -eq 2 ]; then
      echo "${CSUCCESS}mysqld restarted after clone${CEND}"
      echo "${CWARNING}[注意] 本机 root 密码已被 clone 覆盖为 donor 的 root 密码${CEND}"
      echo "  options.conf 中的 dbrootpwd 已失效，需要更新为 donor 的 root 密码："
      echo "    ${CMSG}sed -i \"s+^dbrootpwd.*+dbrootpwd='<donor的root密码>'+\" ${mysql_dir}/options.conf${CEND}"
      echo "  更新后再运行 ./mgr_setup.sh --join"
      return 1
    fi

    echo "${CFAILURE}mysqld did not come back within 120s after clone${CEND}"
    echo "  检查: service mysqld status 或 /data/mysql/mysql-error.log"
    echo "  ${CWARNING}提示: clone 会把本机 root 密码替换为 donor 的 root 密码，${CEND}"
    echo "  ${CWARNING}      若 options.conf 的 dbrootpwd 与 donor 不一致，脚本将无法连接。${CEND}"
    return 1
  fi

  echo "${CFAILURE}Clone failed${CEND}"
  echo "  ${CWARNING}${err}${CEND}"
  echo "  排查:"
  echo "    1. donor 端 mgr_repl 是否有 BACKUP_ADMIN 权限"
  echo "    2. donor 端 clone plugin 是否已安装"
  echo "    3. 网络是否互通（${donor_host}:${donor_port}）"
  echo "    4. super_read_only 是否已关闭"
  return 1
}

# 退出 group
MGR_Remove() {
  local cur_state=$(MGR_Mysql -N -e \
    "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=@@hostname;" 2>/dev/null)
  if [ -z "${cur_state}" ]; then
    echo "${CWARNING}[SKIP] This node is not in any group${CEND}"
    return 0
  fi

  echo "${CMSG}Stopping group_replication on this node...${CEND}"
  MGR_Mysql -e "STOP GROUP_REPLICATION;"
  sleep 2

  cur_state=$(MGR_Mysql -N -e \
    "SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=@@hostname;" 2>/dev/null)
  if [ -z "${cur_state}" ] || [ "${cur_state}" == "OFFLINE" ]; then
    # OFFLINE 也视为已退出: STOP GROUP_REPLICATION 后本地视图可能残留 OFFLINE
    echo "${CSUCCESS}This node has left the MGR group${CEND}"
    echo "${CMSG}提示: 请从其他节点的 options.conf 的 mgr_group_seeds 中移除本节点地址${CEND}"
    return 0
  fi
  echo "${CFAILURE}Failed to leave group, current state: ${cur_state}${CEND}"
  return 1
}

# 查看 group 成员与状态
MGR_Status() {
  echo ""
  echo "========== MGR Group Members =========="
  echo ""

  local members=$(MGR_Mysql -e \
    "SELECT MEMBER_ID, MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE \
     FROM performance_schema.replication_group_members\G" 2>/dev/null)

  if [ -z "${members}" ]; then
    echo "${CWARNING}No MGR group members found (this node may not be in a group)${CEND}"
    return 0
  fi

  echo "${members}"

  # 成员统计
  local total=$(MGR_Mysql -N -e \
    "SELECT COUNT(*) FROM performance_schema.replication_group_members;" 2>/dev/null)
  local online=$(MGR_Mysql -N -e \
    "SELECT COUNT(*) FROM performance_schema.replication_group_members WHERE MEMBER_STATE='ONLINE';" 2>/dev/null)
  local primary=$(MGR_Mysql -N -e \
    "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';" 2>/dev/null)

  echo ""
  echo "Members: ${online}/${total} ONLINE"
  [ -n "${primary}" ] && echo "Primary: ${primary}"
  echo ""
}

# 强制切换主（单主模式）
MGR_Set_Primary() {
  local target_id=$1

  if [ -z "${target_id}" ]; then
    echo "${CFAILURE}Usage: MGR_Set_Primary <member_id>${CEND}"
    echo "  可用 member_id:"
    MGR_Mysql -e \
      "SELECT MEMBER_ID, MEMBER_HOST, MEMBER_ROLE FROM performance_schema.replication_group_members;"
    return 1
  fi

  echo "${CMSG}Setting ${target_id} as new PRIMARY...${CEND}"
  MGR_Mysql -e "SELECT group_replication_set_as_primary('${target_id}');"

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Primary switch initiated${CEND}"
    sleep 2
    MGR_Status
    return 0
  fi
  echo "${CFAILURE}Failed to switch primary${CEND}"
  return 1
}
