#!/bin/bash
# 导入企业 CA 证书到 JDK cacerts 证书库
# 项目: dmp_ops/openjdk
# 用法: ./tools/cacerts_import.sh --cert /path/ca.crt --alias mycorp-ca [--jdk_option N] [--storepass PWD]

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

openjdk_dir=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# Root 检查(--help 除外)
if [[ ! "$1" =~ ^-h$|^--help$ ]]; then
  [ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }
fi

. "${openjdk_dir}/options.conf"
. "${openjdk_dir}/versions.txt"
. "${openjdk_dir}/include/color.sh"
. "${openjdk_dir}/include/check_os.sh"
. "${openjdk_dir}/include/check_env.sh"
. "${openjdk_dir}/include/jdk_env.sh"

cert_file=""
alias_name=""
jdk_option=""
storepass="changeit"

Show_Help() {
  cat << EOF
Usage: $0 --cert FILE --alias NAME [OPTIONS]

Import a CA certificate into the JDK trust store (cacerts)

Options:
  -h, --help              Show this help message
  --cert FILE             Certificate file (PEM/DER), required
  --alias NAME            Alias in the keystore, required
  --jdk_option [1-5]      Target JDK (default: current default JDK)
  --storepass PWD         Keystore password (default: changeit)
  --list                  List existing entries matching the alias

Examples:
  $0 --cert /root/mycorp-ca.crt --alias mycorp-ca
  $0 --cert /root/ca.crt --alias ca --jdk_option 3

EOF
}

list_only=n
TEMP=$(getopt -o h --long help,cert:,alias:,jdk_option:,storepass:,list -- "$@" 2>/dev/null)
[ $? -ne 0 ] && { Show_Help; exit 1; }
eval set -- "${TEMP}"
while true; do
  case "$1" in
    -h|--help)   Show_Help; exit 0 ;;
    --cert)      cert_file=$2; shift 2 ;;
    --alias)     alias_name=$2; shift 2 ;;
    --jdk_option) jdk_option=$2; shift 2 ;;
    --storepass) storepass=$2; shift 2 ;;
    --list)      list_only=y; shift ;;
    --) shift; break ;;
    *)  break ;;
  esac
done

Check_OS > /dev/null

# 目标 JDK
if [ -n "${jdk_option}" ]; then
  ver=$(Option_To_Ver ${jdk_option})
  java_home=$(Detect_JAVA_HOME ${ver})
  [ -z "${java_home}" ] && { echo "${CFAILURE}OpenJDK ${ver} is not installed${CEND}"; exit 1; }
else
  java_home=$(readlink -f "${jdk_link}" 2>/dev/null)
  [ -z "${java_home}" -o ! -x "${java_home}/bin/keytool" ] && {
    echo "${CFAILURE}No default JDK found, specify --jdk_option${CEND}"; exit 1; }
fi

KEYTOOL="${java_home}/bin/keytool"
# JDK 8 的 cacerts 在 jre/lib/security 下
if [ -f "${java_home}/lib/security/cacerts" ]; then
  cacerts="${java_home}/lib/security/cacerts"
elif [ -f "${java_home}/jre/lib/security/cacerts" ]; then
  cacerts="${java_home}/jre/lib/security/cacerts"
else
  echo "${CFAILURE}cacerts not found under ${java_home}${CEND}"; exit 1
fi

echo "${CMSG}JDK       : ${java_home}${CEND}"
echo "${CMSG}Keystore  : ${cacerts}${CEND}"

if [ "${list_only}" == 'y' ]; then
  ${KEYTOOL} -list -keystore "${cacerts}" -storepass "${storepass}" 2>/dev/null \
    | grep -i "${alias_name:-.}" | head -20
  exit $?
fi

[ -z "${cert_file}" -o -z "${alias_name}" ] && { Show_Help; exit 1; }
[ -f "${cert_file}" ] || { echo "${CFAILURE}Certificate file not found: ${cert_file}${CEND}"; exit 1; }

# 导入前备份
bak="${cacerts}.bak_$(date +%Y%m%d%H%M%S)"
/bin/cp -a "${cacerts}" "${bak}" && echo "${CMSG}Keystore backup: ${bak}${CEND}"

# 已存在同名 alias 则先删除
if ${KEYTOOL} -list -keystore "${cacerts}" -storepass "${storepass}" -alias "${alias_name}" > /dev/null 2>&1; then
  echo "${CWARNING}Alias '${alias_name}' already exists, replacing...${CEND}"
  ${KEYTOOL} -delete -keystore "${cacerts}" -storepass "${storepass}" -alias "${alias_name}" > /dev/null 2>&1
fi

${KEYTOOL} -importcert -noprompt -trustcacerts \
  -keystore "${cacerts}" -storepass "${storepass}" \
  -alias "${alias_name}" -file "${cert_file}"

if [ $? -eq 0 ]; then
  echo "${CSUCCESS}Certificate imported as '${alias_name}'${CEND}"
  ${KEYTOOL} -list -keystore "${cacerts}" -storepass "${storepass}" -alias "${alias_name}" 2>/dev/null
else
  echo "${CFAILURE}Import failed, restoring keystore from backup${CEND}"
  /bin/cp -af "${bak}" "${cacerts}"
  exit 1
fi
