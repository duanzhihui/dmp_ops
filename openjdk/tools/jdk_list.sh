#!/bin/bash
# 列出本机所有已安装 JDK 及当前默认版本
# 项目: dmp_ops/openjdk
# 用法: ./tools/jdk_list.sh [--all]
#   --all  额外扫描 /usr/lib/jvm 下未被本工具管理的 JDK

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

openjdk_dir=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

. "${openjdk_dir}/include/ensure_options_conf.sh"
Ensure_Options_Conf "${openjdk_dir}"
. "${openjdk_dir}/options.conf"
. "${openjdk_dir}/versions.txt"
. "${openjdk_dir}/include/color.sh"
. "${openjdk_dir}/include/check_os.sh"
. "${openjdk_dir}/include/check_env.sh"
. "${openjdk_dir}/include/jdk_env.sh"

Check_OS > /dev/null

echo ""
echo "${CMSG}=== Managed OpenJDK ===${CEND}"
Print_JDK_Table
echo ""

if [ -x "${jdk_link}/bin/java" ]; then
  echo "${CMSG}Current default:${CEND} $(readlink -f ${jdk_link})"
  echo "${CMSG}                ${CEND} $(${jdk_link}/bin/java -version 2>&1 | head -1)"
else
  echo "${CWARNING}No default JDK configured (${jdk_link} missing)${CEND}"
fi

if [ "$1" == '--all' ]; then
  echo ""
  echo "${CMSG}=== All JDK found under /usr/lib/jvm and ${jdk_base_dir} ===${CEND}"
  for d in $(ls -d /usr/lib/jvm/* ${jdk_base_dir}/jdk* 2>/dev/null); do
    [ -x "${d}/bin/java" ] || continue
    printf "%-50s %s\n" "${d}" "$(${d}/bin/java -version 2>&1 | head -1)"
  done
fi

echo ""
echo "${CMSG}=== alternatives (java) ===${CEND}"
if [ "${Family}" == 'rhel' ]; then
  alternatives --display java 2>/dev/null | grep -E 'link currently|priority' | sed 's@^@  @'
else
  update-alternatives --display java 2>/dev/null | grep -E 'link currently|priority' | sed 's@^@  @'
fi
