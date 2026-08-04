#!/bin/bash
# JVM 诊断信息采集
# 项目: dmp_ops/openjdk
# 用法: ./tools/jvm_diag.sh --pid PID [--heapdump]
# 说明: 默认只采集非侵入信息；--heapdump 会触发 STW，请谨慎在生产使用

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

openjdk_dir=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

[ $(id -u) != "0" ] && echo "Warning: non-root may fail to attach to other users' JVM"

. "${openjdk_dir}/options.conf"
. "${openjdk_dir}/versions.txt"
. "${openjdk_dir}/include/color.sh"
. "${openjdk_dir}/include/check_os.sh"
. "${openjdk_dir}/include/check_env.sh"
. "${openjdk_dir}/include/jdk_env.sh"

pid=""
heapdump=n

Show_Help() {
  cat << EOF
Usage: $0 --pid PID [--heapdump]

Collect JVM diagnostic info into a tarball under ${backup_dir}

Options:
  -h, --help        Show this help message
  --pid PID         Target JVM process id (required)
  --heapdump        Also collect heap dump (STW, use with caution)

EOF
}

TEMP=$(getopt -o h --long help,pid:,heapdump -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"
while true; do
  case "$1" in
    -h|--help)  Show_Help; exit 0 ;;
    --pid)      pid=$2; shift 2 ;;
    --heapdump) heapdump=y; shift ;;
    --) shift; break ;;
    *)  break ;;
  esac
done

Check_OS > /dev/null

[ -z "${pid}" ] && { Show_Help; exit 1; }
[ -d "/proc/${pid}" ] || { echo "${CFAILURE}PID ${pid} does not exist${CEND}"; exit 1; }

JCMD="${jdk_link}/bin/jcmd"
JSTAT="${jdk_link}/bin/jstat"
JMAP="${jdk_link}/bin/jmap"
[ -x "${JCMD}" ] || { echo "${CFAILURE}jcmd not found in ${jdk_link}/bin${CEND}"; exit 1; }

stamp=$(date +%Y%m%d_%H%M%S)
out_dir="${backup_dir}/jvmdiag_${pid}_${stamp}"
mkdir -p "${out_dir}"

echo "${CMSG}Collecting JVM diagnostics for PID ${pid} ...${CEND}"

# 基础信息
{
  echo "== host =="; hostname; date
  echo "== cmdline =="; tr '\0' ' ' < /proc/${pid}/cmdline; echo
  echo "== status =="; cat /proc/${pid}/status
  echo "== threads =="; ls /proc/${pid}/task | wc -l
  echo "== limits =="; cat /proc/${pid}/limits
} > "${out_dir}/process_info.txt" 2>&1

${JCMD} ${pid} VM.version       > "${out_dir}/vm_version.txt"    2>&1
${JCMD} ${pid} VM.flags -all    > "${out_dir}/vm_flags.txt"      2>&1
${JCMD} ${pid} VM.system_properties > "${out_dir}/vm_sysprops.txt" 2>&1
${JCMD} ${pid} GC.heap_info     > "${out_dir}/gc_heap_info.txt"  2>&1
${JCMD} ${pid} VM.native_memory summary > "${out_dir}/nmt_summary.txt" 2>&1

# 线程栈: 3 次，间隔 5 秒(便于对比定位卡点)
for i in 1 2 3; do
  echo "${CMSG}  thread dump ${i}/3${CEND}"
  ${JCMD} ${pid} Thread.print -l > "${out_dir}/thread_dump_${i}.txt" 2>&1
  [ ${i} -lt 3 ] && sleep 5
done

# GC 采样: 10 次，间隔 1 秒
if [ -x "${JSTAT}" ]; then
  ${JSTAT} -gcutil ${pid} 1000 10 > "${out_dir}/jstat_gcutil.txt" 2>&1
  ${JSTAT} -gc ${pid} 1000 10     > "${out_dir}/jstat_gc.txt"     2>&1
fi

# 对象分布(会触发一次 GC)
${JCMD} ${pid} GC.class_histogram 2>/dev/null | head -50 > "${out_dir}/class_histogram.txt" 2>&1

# 堆转储(可选，STW)
if [ "${heapdump}" == 'y' ] && [ -x "${JMAP}" ]; then
  echo "${CWARNING}  collecting heap dump (this will pause the JVM)...${CEND}"
  ${JMAP} -dump:live,format=b,file="${out_dir}/heap_${pid}.hprof" ${pid} > "${out_dir}/heapdump.log" 2>&1
fi

# 打包
tarball="${backup_dir}/jvmdiag_${pid}_${stamp}.tgz"
tar czf "${tarball}" -C "${backup_dir}" "jvmdiag_${pid}_${stamp}" 2>/dev/null
if [ -f "${tarball}" ]; then
  rm -rf "${out_dir}"
  echo "${CSUCCESS}Diagnostics collected: ${tarball}${CEND}"
else
  echo "${CWARNING}Failed to create tarball, raw files kept in ${out_dir}${CEND}"
fi
