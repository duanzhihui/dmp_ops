#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - JVM/Memory Tuning Module
#
# 根据系统内存大小推荐并应用 JVM / 内存参数：
#   - 堆大小（-Xms/-Xmx）：按系统内存分档比例计算，上限 32g
#   - 堆外内存（-XX:MaxDirectMemorySize）：Zeta 引擎 shuffle 使用，约为堆的 50%
#   - Metaspace：按堆大小分档
#   - GC 并行线程（-XX:ParallelGCThreads）：按 CPU 线程数计算
#   - 大堆（>= 8g）附加 G1 调优参数（MaxGCPauseMillis / IHOP / RegionSize）
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

# 将 512m / 2g / 1024k / 字节数统一换算为 MB
Size_To_MB() {
  local s
  s=$(echo "$1" | tr -d '[:space:]' | tr 'A-Z' 'a-z')
  [ -z "${s}" ] && { echo 0; return; }
  case "${s}" in
    *g) echo $(( ${s%g} * 1024 )) ;;
    *m) echo $(( ${s%m} )) ;;
    *k) echo $(( ${s%k} / 1024 )) ;;
    *) echo $(( ${s} / 1048576 )) ;;
  esac
}

# 将 MB 格式化为 g/m 表示（能整除 1024 用 g，否则用 m）
MB_To_Size() {
  local mb=${1:-0}
  if [ $(( mb % 1024 )) -eq 0 ]; then
    echo "$(( mb / 1024 ))g"
  else
    echo "${mb}m"
  fi
}

# 向上取整到 granularity（默认 512MB）粒度，最小不低于 granularity
Round_MB() {
  local mb=${1:-0}
  local gran=${2:-512}
  [ "${mb}" -lt "${gran}" ] && { echo "${gran}"; return; }
  echo $(( (mb + gran / 2) / gran * gran ))
}

# 按堆大小自动分档 direct memory（Zeta shuffle 堆外内存，约为堆的 50%，上限 4g）
Get_Auto_Direct() {
  local heap_mb
  heap_mb=$(Size_To_MB "${1:-2g}")
  local direct_mb=$(( heap_mb / 2 ))
  [ "${direct_mb}" -gt 4096 ] && direct_mb=4096
  direct_mb=$(Round_MB "${direct_mb}" 512)
  MB_To_Size "${direct_mb}"
}

# 获取系统总内存（MB），优先 /proc/meminfo，失败回退 free
Get_Total_Mem_MB() {
  local mb
  mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
  if [ -z "${mb}" ] || [ "${mb}" -le 0 ] 2>/dev/null; then
    mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}')
  fi
  [ -z "${mb}" ] && mb=4096
  echo "${mb}"
}

# 获取当前节点在调优时对应的角色（用于内存分配比例）
Get_Tune_Role() {
  if [ "${deploy_mode}" == "separated" ]; then
    echo "${node_role:-master}"
  else
    echo "${deploy_mode:-hybrid}"
  fi
}

# 根据系统内存计算推荐 JVM 参数
# 用法: Recommend_JVM_By_Mem <total_mb> [role]
# 结果写入全局变量:
#   REC_HEAP / REC_METASPACE / REC_DIRECT / REC_CLIENT_HEAP / REC_GC_THREADS
#   REC_HEAP_MB / REC_DIRECT_MB / REC_METASPACE_MB
Recommend_JVM_By_Mem() {
  local total_mb=${1:-0}
  local role=${2:-hybrid}

  if ! [ "${total_mb}" -gt 0 ] 2>/dev/null; then
    total_mb=$(Get_Total_Mem_MB)
  fi

  # 堆占比按内存分档：小内存机器给 OS 留更多余量
  local ratio=50
  if [ "${total_mb}" -lt 8192 ]; then
    ratio=40
  fi

  # separated 模式 master 仅负责调度与 REST API，内存占用更小
  if [ "${role}" == "master" ]; then
    ratio=$(( ratio * 6 / 10 ))
  fi

  local heap_mb=$(( total_mb * ratio / 100 ))
  [ "${heap_mb}" -gt 32768 ] && heap_mb=32768
  heap_mb=$(Round_MB "${heap_mb}" 512)

  REC_HEAP_MB=${heap_mb}
  REC_HEAP=$(MB_To_Size "${heap_mb}")

  # Metaspace 按堆大小分档（连接器较多时类加载开销更大）
  if [ "${heap_mb}" -le 2048 ]; then
    REC_METASPACE=256m
  elif [ "${heap_mb}" -le 8192 ]; then
    REC_METASPACE=384m
  else
    REC_METASPACE=512m
  fi
  REC_METASPACE_MB=$(Size_To_MB "${REC_METASPACE}")

  # Zeta 引擎 shuffle 依赖堆外内存，约为堆的 50%，上限 4g
  REC_DIRECT=$(Get_Auto_Direct "${REC_HEAP}")
  REC_DIRECT_MB=$(Size_To_MB "${REC_DIRECT}")

  # 客户端（提交作业进程）堆
  if [ "${total_mb}" -lt 4096 ]; then
    REC_CLIENT_HEAP=256m
  else
    REC_CLIENT_HEAP=512m
  fi

  # GC 并行线程：<=8 核全用，>8 核取 5/8
  local threads=${THREAD:-$(nproc 2>/dev/null || echo 4)}
  if [ "${threads}" -le 8 ] 2>/dev/null; then
    REC_GC_THREADS=${threads}
  else
    REC_GC_THREADS=$(( threads * 5 / 8 ))
  fi
}

# 自动调优入口：留空的 JVM 配置项采用推荐值（显式指定的值优先）
Tune_JVM_Auto() {
  local role
  role=$(Get_Tune_Role)
  Recommend_JVM_By_Mem "${Mem:-0}" "${role}"

  [ -z "${jvm_heap_size}" ] && jvm_heap_size=${REC_HEAP}
  [ -z "${jvm_metaspace_size}" ] && jvm_metaspace_size=${REC_METASPACE}
  [ -z "${jvm_direct_memory_size}" ] && jvm_direct_memory_size=${REC_DIRECT}
  [ -z "${jvm_client_heap_size}" ] && jvm_client_heap_size=${REC_CLIENT_HEAP}
  [ -z "${jvm_gc_threads}" ] && jvm_gc_threads=${REC_GC_THREADS}
}

# 校验 JVM 内存预算：heap + direct + metaspace 不应超过 系统内存 - 系统预留
# 参数均为 MB 数值（调用方先用 Size_To_MB 换算）
# 系统预留：>=16g 机器预留 2g，小内存机器预留 10%（下限 1g）
# 返回 0 = 预算安全，1 = 超出预算
Check_Mem_Budget() {
  local total_mb=${1:-0}
  local heap_mb=${2:-0}
  local direct_mb=${3:-0}
  local meta_mb=${4:-0}
  local reserved_mb=2048

  if [ "${total_mb}" -lt 16384 ]; then
    reserved_mb=$(( total_mb / 10 ))
    [ "${reserved_mb}" -lt 1024 ] && reserved_mb=1024
  fi

  local used_mb=$(( heap_mb + direct_mb + meta_mb ))
  local limit_mb=$(( total_mb - reserved_mb ))
  [ "${limit_mb}" -lt 512 ] && limit_mb=512

  if [ "${used_mb}" -gt "${limit_mb}" ]; then
    return 1
  fi
  return 0
}

# 打印调优报告：系统资源、当前配置 vs 推荐、内存预算、系统级建议
Show_Tune_Report() {
  local total_mb=${1:-0}
  local role=${2:-hybrid}

  if ! [ "${total_mb}" -gt 0 ] 2>/dev/null; then
    total_mb=$(Get_Total_Mem_MB)
  fi

  Recommend_JVM_By_Mem "${total_mb}" "${role}"

  local cur_heap=${jvm_heap_size:-2g}
  local cur_metaspace=${jvm_metaspace_size:-256m}
  local cur_direct=${jvm_direct_memory_size:-}
  local cur_direct_display
  if [ -z "${cur_direct}" ]; then
    # 未配置时显示将自动生效的分档值，预算也按该值计算
    cur_direct=$(Get_Auto_Direct "${cur_heap}")
    cur_direct_display="auto (${cur_direct})"
  else
    cur_direct_display=${cur_direct}
  fi
  local cur_client=${jvm_client_heap_size:-512m}
  local cur_gc=${jvm_gc_threads:-（自动）}

  local cur_heap_mb=$(Size_To_MB "${cur_heap}")
  local cur_direct_mb=$(Size_To_MB "${cur_direct}")
  local cur_metaspace_mb=$(Size_To_MB "${cur_metaspace}")
  local cur_used_mb=$(( cur_heap_mb + cur_direct_mb + cur_metaspace_mb ))

  echo
  echo "=========================================="
  echo "${CMSG}SeaTunnel JVM 调优报告${CEND}"
  echo "=========================================="
  echo "系统内存:      ${total_mb} MB"
  echo "CPU 线程:      ${THREAD:-未知}"
  echo "部署模式/角色: ${deploy_mode:-hybrid} / ${role}"
  echo "------------------------------------------"
  echo "参数              当前值              推荐值"
  echo "------------------------------------------"
  printf "%-18s %-18s %s\n" "JVM 堆" "${cur_heap}" "${REC_HEAP}"
  printf "%-18s %-18s %s\n" "Metaspace" "${cur_metaspace}" "${REC_METASPACE}"
  printf "%-18s %-18s %s\n" "Direct Memory" "${cur_direct_display}" "${REC_DIRECT}"
  printf "%-18s %-18s %s\n" "客户端堆" "${cur_client}" "${REC_CLIENT_HEAP}"
  printf "%-18s %-18s %s\n" "GC 并行线程" "${cur_gc}" "${REC_GC_THREADS}"
  echo "------------------------------------------"
  echo "当前内存占用:  heap ${cur_heap_mb}MB + direct ${cur_direct_mb}MB + metaspace ${cur_metaspace_mb}MB = ${cur_used_mb}MB"
  echo "推荐内存占用:  heap ${REC_HEAP_MB}MB + direct ${REC_DIRECT_MB}MB + metaspace ${REC_METASPACE_MB}MB = $(( REC_HEAP_MB + REC_DIRECT_MB + REC_METASPACE_MB ))MB"
  echo "系统预留:      ${total_mb} - $(( REC_HEAP_MB + REC_DIRECT_MB + REC_METASPACE_MB )) = $(( total_mb - REC_HEAP_MB - REC_DIRECT_MB - REC_METASPACE_MB ))MB（OS / page cache）"

  if ! Check_Mem_Budget "${total_mb}" "${cur_heap_mb}" "${cur_direct_mb}" "${cur_metaspace_mb}"; then
    echo "${CWARNING}警告: 当前配置内存预算超出（系统内存 - 预留），存在被 OOM killer 杀掉的风险！${CEND}"
  fi
  if [ "${total_mb}" -lt 2048 ]; then
    echo "${CWARNING}警告: 系统内存不足 2GB，SeaTunnel 引擎运行可能非常吃力，建议升级内存。${CEND}"
  fi
  echo "=========================================="
}

# 系统级内存参数建议（只读展示，不自动修改）
Show_Memory_Advisory() {
  local total_mb=${1:-0}
  if ! [ "${total_mb}" -gt 0 ] 2>/dev/null; then
    total_mb=$(Get_Total_Mem_MB)
  fi

  local swap_mb
  swap_mb=$(free -m 2>/dev/null | awk '/Swap:/{print $2}')
  [ -z "${swap_mb}" ] && swap_mb=0
  local swappiness
  swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo unknown)
  local thp
  thp=$(awk -F'[][]' '/\[/{print $2}' /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo unknown)

  echo
  echo "${CMSG}系统级内存建议（仅提示，不自动修改）:${CEND}"

  if [ "${swap_mb}" -lt 1024 ]; then
    echo "  - Swap 仅 ${swap_mb}MB，建议 >= 2048MB 以降低内核 OOM killer 直接杀进程的风险"
  else
    echo "  - Swap ${swap_mb}MB，正常"
  fi

  if [ "${swappiness}" != "unknown" ] && [ "${swappiness}" -gt 10 ] 2>/dev/null; then
    echo "  - vm.swappiness=${swappiness}，大内存 JVM 进程建议调低（sysctl vm.swappiness=1~10），减少换页抖动"
  else
    echo "  - vm.swappiness=${swappiness}，正常"
  fi

  if [ "${thp}" == "always" ]; then
    echo "  - 透明大页 THP=always，可能造成 GC 延迟抖动，建议改为 madvise（echo madvise > /sys/kernel/mm/transparent_hugepage/enabled）"
  else
    echo "  - 透明大页 THP=${thp}，正常"
  fi
}

# 更新 options.conf 中的配置项（不存在则追加）
Update_Opt_Conf() {
  local key=$1
  local val=$2
  local conf=${3:-${seatunnel_dir}/options.conf}

  [ -z "${key}" ] && return 1

  if [ -f "${conf}" ] && grep -qE "^${key}=" "${conf}"; then
    sed -i "s@^${key}=.*@${key}=${val}@" "${conf}"
  else
    echo "${key}=${val}" >> "${conf}"
  fi
}
