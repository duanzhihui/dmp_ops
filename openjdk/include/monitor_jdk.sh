#!/bin/bash
# OpenJDK / JVM 监控模块
# 项目: dmp_ops/openjdk
#
# 说明: OpenJDK 自身无常驻进程，监控对象为运行在该 JDK 上的 JVM 进程

# 日志与告警
Log_Msg() {
  local msg=$1
  mkdir -p "${log_dir}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${msg}" >> "${log_dir}/monitor.log"
}

Send_Alert() {
  local message=$1
  Log_Msg "ALERT: ${message}"

  if [ -n "${alert_email}" ] && command -v mail > /dev/null 2>&1; then
    echo "${message}" | mail -s "[OpenJDK Alert] $(hostname)" "${alert_email}"
  fi
  if [ -n "${webhook_url}" ]; then
    curl -s -X POST "${webhook_url}" \
      -H 'Content-Type: application/json' \
      -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"[$(hostname)] ${message}\"}}" > /dev/null 2>&1
  fi
}

# 1. JDK 可用性自检
Check_JDK_Health() {
  local rc=0
  if [ ! -x "${jdk_link}/bin/java" ]; then
    echo "${CFAILURE}[CRITICAL] JAVA_HOME broken: ${jdk_link}${CEND}"
    Send_Alert "JAVA_HOME ${jdk_link} is broken or not installed"
    return 1
  fi
  if ! ${jdk_link}/bin/java -version > /dev/null 2>&1; then
    echo "${CFAILURE}[CRITICAL] 'java -version' failed on ${jdk_link}${CEND}"
    Send_Alert "java -version failed on $(hostname)"
    return 1
  fi
  echo "${CSUCCESS}[OK] Default JDK: $(${jdk_link}/bin/java -version 2>&1 | head -1)${CEND}"

  # PATH 中的 java 与 JAVA_HOME 是否一致
  local path_java=$(command -v java 2>/dev/null)
  if [ -n "${path_java}" ]; then
    if [ "$(readlink -f ${path_java})" != "$(readlink -f ${jdk_link}/bin/java)" ]; then
      echo "${CWARNING}[WARNING] 'java' in PATH ($(readlink -f ${path_java})) differs from JAVA_HOME${CEND}"
      rc=1
    fi
  else
    echo "${CWARNING}[WARNING] 'java' not found in PATH, source /etc/profile.d/openjdk.sh${CEND}"
    rc=1
  fi
  return ${rc}
}

# 2. JVM 进程清单
Check_JVM_Process() {
  local jps_bin="${jdk_link}/bin/jps"
  [ -x "${jps_bin}" ] || { echo "${CWARNING}jps not available${CEND}"; return 1; }

  local jvms=$(${jps_bin} -l 2>/dev/null | grep -v 'sun.tools.jps\|jdk.jcmd')
  if [ -z "${jvms}" ]; then
    echo "${CMSG}No JVM process running${CEND}"
    return 0
  fi
  echo "${CMSG}Running JVM processes:${CEND}"
  echo "${jvms}" | while read pid mainclass; do
    printf "  %-8s %s\n" "${pid}" "${mainclass}"
  done
  return 0
}

# 获取所有 JVM PID
Get_JVM_Pids() {
  local jps_bin="${jdk_link}/bin/jps"
  [ -x "${jps_bin}" ] || return 1
  ${jps_bin} -l 2>/dev/null | grep -v 'sun.tools.jps\|jdk.jcmd' | awk '{print $1}'
}

# 3. 堆使用率检查
Check_JVM_Heap() {
  local jcmd_bin="${jdk_link}/bin/jcmd"
  [ -x "${jcmd_bin}" ] || { echo "${CWARNING}jcmd not available${CEND}"; return 1; }

  local pid used_kb max_bytes pct name
  for pid in $(Get_JVM_Pids); do
    name=$(${jdk_link}/bin/jps -l 2>/dev/null | awk -v p=${pid} '$1==p{print $2}')
    used_kb=$(${jcmd_bin} ${pid} GC.heap_info 2>/dev/null | grep -oE 'used [0-9]+K' | head -1 | tr -dc '0-9')
    max_bytes=$(${jcmd_bin} ${pid} VM.flags 2>/dev/null | grep -oE 'MaxHeapSize=[0-9]+' | cut -d= -f2)
    [ -z "${used_kb}" -o -z "${max_bytes}" ] && continue
    [ "${max_bytes}" -le 0 ] 2>/dev/null && continue
    pct=$(( used_kb * 1024 * 100 / max_bytes ))
    if [ ${pct} -ge ${jvm_heap_threshold} ]; then
      echo "${CWARNING}[WARNING] PID ${pid} (${name}) heap usage ${pct}%${CEND}"
      Send_Alert "JVM ${pid} ${name} heap usage ${pct}% >= ${jvm_heap_threshold}%"
    else
      echo "${CSUCCESS}[OK] PID ${pid} (${name}) heap usage ${pct}%${CEND}"
    fi
  done
  return 0
}

# 4. GC 检查
Check_JVM_GC() {
  local jstat_bin="${jdk_link}/bin/jstat"
  [ -x "${jstat_bin}" ] || { echo "${CWARNING}jstat not available${CEND}"; return 1; }

  # 不同 JDK 版本的 jstat 列数不同(JDK 11+ 含 CGC/CGCT)，按列名定位而非固定下标
  local pid out hdr line fgc_idx fgct_idx fgc_val fgct_val
  for pid in $(Get_JVM_Pids); do
    out=$(${jstat_bin} -gcutil ${pid} 2>/dev/null)
    [ -z "${out}" ] && continue
    hdr=$(echo "${out}" | head -1)
    line=$(echo "${out}" | tail -1)
    fgc_idx=$(echo "${hdr}" | tr -s ' ' '\n' | grep -n '^FGC$' | cut -d: -f1)
    fgct_idx=$(echo "${hdr}" | tr -s ' ' '\n' | grep -n '^FGCT$' | cut -d: -f1)
    [ -z "${fgc_idx}" ] && continue
    fgc_val=$(echo "${line}" | awk -v i=${fgc_idx} '{print $i}')
    fgct_val=$(echo "${line}" | awk -v i=${fgct_idx} '{print $i}')
    echo "  PID ${pid}: FullGC=${fgc_val} FullGCTime=${fgct_val}s"
    if [ "${fgc_val%%.*}" -ge "${jvm_fullgc_threshold}" ] 2>/dev/null; then
      echo "${CWARNING}[WARNING] PID ${pid} Full GC count ${fgc_val} >= ${jvm_fullgc_threshold}${CEND}"
      Send_Alert "JVM ${pid} Full GC count ${fgc_val} exceeds ${jvm_fullgc_threshold}"
    fi
  done
  return 0
}

# 5. 线程数检查
Check_JVM_Thread() {
  local pid threads name
  for pid in $(Get_JVM_Pids); do
    [ -d "/proc/${pid}/task" ] || continue
    threads=$(ls /proc/${pid}/task 2>/dev/null | wc -l)
    name=$(${jdk_link}/bin/jps -l 2>/dev/null | awk -v p=${pid} '$1==p{print $2}')
    if [ ${threads} -ge ${jvm_thread_threshold} ]; then
      echo "${CWARNING}[WARNING] PID ${pid} (${name}) thread count ${threads}${CEND}"
      Send_Alert "JVM ${pid} ${name} thread count ${threads} >= ${jvm_thread_threshold}"
    else
      echo "${CSUCCESS}[OK] PID ${pid} (${name}) thread count ${threads}${CEND}"
    fi
  done
  return 0
}

# 6. 磁盘检查
Check_Disk() {
  local threshold=${1:-${disk_threshold}}
  local over=$(df -hP 2>/dev/null | awk -v t=${threshold} 'NR>1{gsub(/%/,"",$5); if ($5+0 > t) print $6" "$5"%"}')
  if [ -n "${over}" ]; then
    echo "${over}" | while read mp usage; do
      echo "${CWARNING}[WARNING] Disk usage high: ${mp} ${usage}${CEND}"
      Send_Alert "Disk usage warning: ${mp} ${usage}"
    done
    return 1
  fi
  echo "${CSUCCESS}[OK] Disk usage below ${threshold}%${CEND}"
  return 0
}

# 7. 单个 JVM 详情
Check_JVM_Detail() {
  local pid=$1
  [ -d "/proc/${pid}" ] || { echo "${CFAILURE}PID ${pid} does not exist${CEND}"; return 1; }

  echo "${CMSG}=== JVM Detail: PID ${pid} ===${CEND}"
  echo "Command line:"
  tr '\0' ' ' < /proc/${pid}/cmdline 2>/dev/null | fold -w 120 | sed 's@^@  @'
  echo ""
  echo "Threads: $(ls /proc/${pid}/task 2>/dev/null | wc -l)"
  echo "RSS    : $(awk '/VmRSS/{print $2" "$3}' /proc/${pid}/status 2>/dev/null)"
  echo ""
  if [ -x "${jdk_link}/bin/jcmd" ]; then
    echo "${CMSG}--- VM.version ---${CEND}"
    ${jdk_link}/bin/jcmd ${pid} VM.version 2>/dev/null | sed 's@^@  @'
    echo "${CMSG}--- GC.heap_info ---${CEND}"
    ${jdk_link}/bin/jcmd ${pid} GC.heap_info 2>/dev/null | sed 's@^@  @'
    echo "${CMSG}--- VM.flags ---${CEND}"
    ${jdk_link}/bin/jcmd ${pid} VM.flags 2>/dev/null | fold -w 120 | sed 's@^@  @'
  fi
  if [ -x "${jdk_link}/bin/jstat" ]; then
    echo "${CMSG}--- jstat -gcutil ---${CEND}"
    ${jdk_link}/bin/jstat -gcutil ${pid} 2>/dev/null | sed 's@^@  @'
  fi
  return 0
}

# 8. 状态报告
Monitor_Status() {
  echo "${CMSG}========== OpenJDK Status: $(date '+%Y-%m-%d %H:%M:%S') ==========${CEND}"
  echo "Host              : $(hostname)"
  if [ -x "${jdk_link}/bin/java" ]; then
    echo "Default JAVA_HOME : $(readlink -f ${jdk_link})"
    echo "Default Version   : $(${jdk_link}/bin/java -version 2>&1 | head -1)"
  else
    echo "Default JAVA_HOME : ${CWARNING}not configured${CEND}"
  fi
  echo "Install Method    : ${install_method}"
  echo ""
  echo "${CMSG}Installed JDKs:${CEND}"
  Print_JDK_Table
  echo ""
  Check_JVM_Process
  echo ""
  echo "${CMSG}GC Overview:${CEND}"
  Check_JVM_GC
}

# 9. 健康检查总入口
Monitor_Check() {
  echo "${CMSG}========== OpenJDK Health Check: $(date '+%Y-%m-%d %H:%M:%S') ==========${CEND}"
  local rc=0
  Check_JDK_Health || rc=1
  echo ""
  Check_JVM_Heap
  echo ""
  Check_JVM_GC
  echo ""
  Check_JVM_Thread
  echo ""
  Check_Disk || rc=1
  Log_Msg "health check finished, rc=${rc}"
  return ${rc}
}
