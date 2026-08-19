#!/bin/bash
# chrony 监控模块
# 项目: dmp_ops/chrony
# 核心函数: Check_Process / Check_Port / Check_Tracking / Check_Sources / Check_Offset
#           Check_Clients / Check_Disk / Send_Alert / Monitor_Status / Monitor_All

# 全局失败计数
FAIL_COUNT=0

# 告警通知（日志 + 邮件 + Webhook）
Send_Alert() {
  local message="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local host=$(hostname)

  mkdir -p "${log_dir}" 2>/dev/null
  echo "[${timestamp}] ALERT [${host}] ${message}" >> "${log_dir}/monitor.log" 2>/dev/null

  # 邮件通知
  if [ -n "${alert_email}" ] && command -v mail > /dev/null 2>&1; then
    echo "${message}" | mail -s "[Chrony Alert] ${host}" "${alert_email}" 2>/dev/null
  fi

  # Webhook 通知（钉钉/飞书/Slack 等）
  if [ -n "${webhook_url}" ] && command -v curl > /dev/null 2>&1; then
    curl -s -m 5 -X POST "${webhook_url}" \
      -H 'Content-Type: application/json' \
      -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"[Chrony][${host}] ${timestamp} ${message}\"}}" \
      > /dev/null 2>&1
  fi
}

# 1. 进程存活检查（不存在则自动重启并二次确认）
Check_Process() {
  if pgrep -x chronyd > /dev/null 2>&1; then
    echo "${CSUCCESS}[OK] chronyd 进程运行中 (pid=$(pgrep -x chronyd | tr '\n' ' '))${CEND}"
    return 0
  fi

  echo "${CFAILURE}[CRITICAL] chronyd 进程未运行，尝试自动恢复 ...${CEND}"
  systemctl restart "${chrony_service}" > /dev/null 2>&1
  sleep 3

  if pgrep -x chronyd > /dev/null 2>&1; then
    echo "${CSUCCESS}[RECOVERED] chronyd 已自动重启成功${CEND}"
    Send_Alert "chronyd 曾停止运行，已自动恢复"
    return 0
  fi

  echo "${CFAILURE}[CRITICAL] chronyd 自动恢复失败${CEND}"
  Send_Alert "chronyd 停止运行且自动恢复失败"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

# 2. 端口监听检查（仅 Server 角色需要 123/udp）
Check_Port() {
  [ "${chrony_role}" != 'server' ] && return 0

  if ss -unlp 2>/dev/null | grep -q ':123 '; then
    echo "${CSUCCESS}[OK] NTP 服务端口 123/udp 正在监听${CEND}"
    return 0
  fi

  echo "${CFAILURE}[CRITICAL] NTP 服务端口 123/udp 未监听${CEND}"
  Send_Alert "NTP 服务端口 123/udp 未监听"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

# 3. 同步状态检查（Leap status + Reference ID）
Check_Tracking() {
  local out
  out=$(chronyc tracking 2>/dev/null)
  if [ -z "${out}" ]; then
    echo "${CFAILURE}[CRITICAL] chronyc tracking 无响应${CEND}"
    Send_Alert "chronyc tracking 无响应"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  local leap refid stratum
  leap=$(echo "${out}" | awk -F': *' '/Leap status/{print $2}')
  refid=$(echo "${out}" | awk -F': *' '/Reference ID/{print $2}' | awk '{print $1}')
  stratum=$(echo "${out}" | awk -F': *' '/Stratum/{print $2}')

  if [ "${leap}" != "Normal" ]; then
    echo "${CFAILURE}[CRITICAL] 时钟未同步, Leap status=${leap}${CEND}"
    Send_Alert "chrony 未同步: Leap status=${leap}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  if [ "${refid}" == "00000000" ]; then
    echo "${CWARNING}[WARNING] 无有效参考源 (Reference ID=00000000)${CEND}"
    Send_Alert "chrony 无有效参考源"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  # stratum 过高说明距离真实时间源太远
  if [ -n "${stratum}" ] && [ "${stratum}" -gt 10 ] 2>/dev/null; then
    echo "${CWARNING}[WARNING] Stratum=${stratum} 过高，时间源可靠性低${CEND}"
    Send_Alert "chrony stratum=${stratum} 过高"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  echo "${CSUCCESS}[OK] 同步正常 stratum=${stratum} refid=${refid}${CEND}"
  return 0
}

# 4. 可用时间源检查（至少 1 个 ^* 或 ^+）
Check_Sources() {
  local out good
  out=$(chronyc sources 2>/dev/null)
  if [ -z "${out}" ]; then
    echo "${CFAILURE}[CRITICAL] chronyc sources 无响应${CEND}"
    Send_Alert "chronyc sources 无响应"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  good=$(echo "${out}" | grep -cE '^\^\*|^\^\+|^#\*|^#\+')
  if [ "${good}" -eq 0 ]; then
    echo "${CFAILURE}[CRITICAL] 无任何可用时间源（无 ^* / ^+ 状态的源）${CEND}"
    Send_Alert "chrony 无可用时间源"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  echo "${CSUCCESS}[OK] 可用时间源数量: ${good}${CEND}"
  return 0
}

# 5. 时间偏移检查（offset 可能为科学计数法，必须用 awk 做数值比较）
Check_Offset() {
  local offset abs exceed
  offset=$(chronyc tracking 2>/dev/null | awk -F': *' '/Last offset/{print $2}' | awk '{print $1}')
  if [ -z "${offset}" ]; then
    echo "${CWARNING}[WARNING] 无法获取时间偏移${CEND}"
    return 1
  fi

  abs=$(awk -v v="${offset}" 'BEGIN{v=v+0; if(v<0) v=-v; printf "%.9f", v}')
  exceed=$(awk -v a="${abs}" -v t="${offset_threshold}" 'BEGIN{print ((a+0)>(t+0))?1:0}')

  if [ "${exceed}" == "1" ]; then
    echo "${CWARNING}[WARNING] 时间偏移 ${abs}s 超过阈值 ${offset_threshold}s${CEND}"
    Send_Alert "时间偏移 ${abs}s 超过阈值 ${offset_threshold}s"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  echo "${CSUCCESS}[OK] 时间偏移 ${abs}s (阈值 ${offset_threshold}s)${CEND}"
  return 0
}

# 6. 客户端数量检查（仅 Server 角色）
Check_Clients() {
  [ "${chrony_role}" != 'server' ] && return 0

  local count
  count=$(chronyc clients 2>/dev/null | tail -n +3 | grep -cvE '^\s*$')
  if [ -z "${count}" ]; then
    echo "${CWARNING}[WARNING] 无法获取客户端列表（需要 root 权限）${CEND}"
    return 1
  fi

  if [ "${count}" -eq 0 ]; then
    echo "${CWARNING}[WARNING] 当前无客户端连接，请检查 allow 网段与防火墙${CEND}"
    return 1
  fi

  echo "${CSUCCESS}[OK] 当前客户端数量: ${count}${CEND}"
  return 0
}

# 7. 磁盘空间检查
Check_Disk() {
  local threshold=${1:-85}
  local rc=0
  local usage
  for dir in /var/log /var/lib; do
    [ -d "${dir}" ] || continue
    usage=$(df -P "${dir}" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    [ -z "${usage}" ] && continue
    if [ "${usage}" -gt "${threshold}" ]; then
      echo "${CWARNING}[WARNING] ${dir} 磁盘使用率 ${usage}% 超过 ${threshold}%${CEND}"
      Send_Alert "${dir} 磁盘使用率 ${usage}%"
      rc=1
    fi
  done
  [ ${rc} -eq 0 ] && echo "${CSUCCESS}[OK] 磁盘空间正常${CEND}"
  return ${rc}
}

# 完整状态报告
Monitor_Status() {
  echo "${CMSG}================ Chrony Status: $(date '+%F %T') ================${CEND}"
  echo "  主机名    : $(hostname)"
  echo "  版本      : $(chronyd -v 2>/dev/null | head -1)"
  echo "  角色      : ${chrony_role}"
  echo "  部署模式  : ${deploy_mode}"
  echo "  配置文件  : ${chrony_conf}"
  echo "  服务状态  : $(systemctl is-active ${chrony_service} 2>/dev/null) / $(systemctl is-enabled ${chrony_service} 2>/dev/null)"
  echo "  时区      : $(timedatectl show -p Timezone --value 2>/dev/null)"
  echo "  系统时间  : $(date '+%F %T %Z')"
  echo ""
  echo "${CMSG}---- chronyc tracking ----${CEND}"
  chronyc tracking 2>/dev/null || echo "${CFAILURE}无响应${CEND}"
  echo ""
  echo "${CMSG}---- chronyc sources -v ----${CEND}"
  chronyc sources -v 2>/dev/null || echo "${CFAILURE}无响应${CEND}"
  echo ""
  echo "${CMSG}---- chronyc sourcestats ----${CEND}"
  chronyc sourcestats 2>/dev/null
  if [ "${chrony_role}" == 'server' ]; then
    echo ""
    echo "${CMSG}---- chronyc clients ----${CEND}"
    chronyc clients 2>/dev/null || echo "（需要 root 权限）"
  fi
  echo ""
}

# 健康检查主流程（cron 用，异常时返回非 0）
Monitor_All() {
  FAIL_COUNT=0
  echo "${CMSG}========== Chrony Health Check: $(date '+%F %T') ==========${CEND}"
  Check_Process
  Check_Port
  Check_Tracking
  Check_Sources
  Check_Offset
  Check_Clients
  Check_Disk 85
  echo ""
  if [ ${FAIL_COUNT} -eq 0 ]; then
    echo "${CSUCCESS}检查完成: 全部正常${CEND}"
    return 0
  fi
  echo "${CFAILURE}检查完成: ${FAIL_COUNT} 项异常${CEND}"
  return 1
}
