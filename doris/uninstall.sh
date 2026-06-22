#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Uninstallation script
#
# Supports uninstalling: FE, BE, MS (Meta Service), FDB (FoundationDB)

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear
printf "
#######################################################################
#       DorisStack - Apache Doris Cluster Deployment Tool             #
#                     Uninstall Apache Doris                          #
#       For more information: https://doris.apache.org                #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

doris_dir=$(dirname "$(readlink -f $0)")
pushd ${doris_dir} > /dev/null
. ./options.conf
. ./include/color.sh
. ./include/check_os.sh
. ./include/doris_fe.sh
. ./include/doris_be.sh
. ./include/doris_ms.sh
. ./include/fdb.sh

Show_Help() {
  echo
  echo "Usage: $0 command ...[parameters]....
  --help, -h                  Show this help message
  --quiet, -q                 Quiet operation (no confirmation)
  --all                       Uninstall all components (FE + BE + MS + FDB)
  --fe                        Uninstall FE only
  --be                        Uninstall BE only
  --ms                        Uninstall Meta Service only
  --fdb                       Uninstall FoundationDB only
  "
}

ARG_NUM=$#
TEMP=$(getopt -o hq --long help,quiet,all,fe,be,ms,fdb -- "$@" 2>/dev/null)
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"

quiet_flag=n
all_flag=n
fe_flag=n
be_flag=n
ms_flag=n
fdb_flag=n

while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    --all)
      all_flag=y; fe_flag=y; be_flag=y; ms_flag=y; fdb_flag=y; shift 1
      ;;
    --fe)
      fe_flag=y; shift 1
      ;;
    --be)
      be_flag=y; shift 1
      ;;
    --ms)
      ms_flag=y; shift 1
      ;;
    --fdb)
      fdb_flag=y; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

Confirm_Uninstall() {
  if [ "${quiet_flag}" != "y" ]; then
    echo ""
    echo "${CWARNING}WARNING: This will remove Doris installation and backup data files!${CEND}"
    echo ""

    if [ "${fe_flag}" == "y" ]; then
      echo "  Will uninstall FE:"
      [ -d "${fe_install_dir}" ] && echo "    - ${fe_install_dir}"
      [ -d "${fe_meta_dir}" ] && echo "    - ${fe_meta_dir} (will be backed up)"
      [ -d "${fe_log_dir}" ] && echo "    - ${fe_log_dir}"
      [ -e "/lib/systemd/system/doris-fe.service" ] && echo "    - /lib/systemd/system/doris-fe.service"
    fi

    if [ "${be_flag}" == "y" ]; then
      echo "  Will uninstall BE:"
      [ -d "${be_install_dir}" ] && echo "    - ${be_install_dir}"
      [ -d "${be_data_dir}" ] && echo "    - ${be_data_dir} (will be backed up)"
      [ -d "${be_log_dir}" ] && echo "    - ${be_log_dir}"
      [ -e "/lib/systemd/system/doris-be.service" ] && echo "    - /lib/systemd/system/doris-be.service"
    fi

    if [ "${ms_flag}" == "y" ]; then
      echo "  Will uninstall Meta Service:"
      [ -d "${ms_install_dir}" ] && echo "    - ${ms_install_dir}"
      [ -d "${ms_log_dir}" ] && echo "    - ${ms_log_dir}"
      [ -e "/lib/systemd/system/doris-ms.service" ] && echo "    - /lib/systemd/system/doris-ms.service"
    fi

    if [ "${fdb_flag}" == "y" ]; then
      echo "  Will uninstall FoundationDB:"
      [ -d "${fdb_home}" ] && echo "    - ${fdb_home} (will be backed up)"
      echo "    - FoundationDB packages"
    fi

    echo ""
    while :; do
      read -e -p "Do you want to continue? [y/n]: " confirm
      if [[ ! ${confirm} =~ ^[y,n]$ ]]; then
        echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
      else
        break
      fi
    done

    if [ "${confirm}" != "y" ]; then
      echo "Uninstall cancelled."
      exit 0
    fi
  fi
}

Menu() {
  while :; do
    printf "
What do you want to uninstall?
\t${CMSG}1${CEND}. Uninstall All (FE + BE + MS + FDB)
\t${CMSG}2${CEND}. Uninstall FE + BE (存算一体)
\t${CMSG}3${CEND}. Uninstall FE only
\t${CMSG}4${CEND}. Uninstall BE only
\t${CMSG}5${CEND}. Uninstall Meta Service only
\t${CMSG}6${CEND}. Uninstall FoundationDB only
\t${CMSG}q${CEND}. Exit
"
    echo
    read -e -p "Please input the correct option: " Number
    if [[ ! "${Number}" =~ ^[1-6,q]$ ]]; then
      echo "${CWARNING}input error! Please only input 1~6 or q${CEND}"
    else
      case "$Number" in
        1) fe_flag=y; be_flag=y; ms_flag=y; fdb_flag=y ;;
        2) fe_flag=y; be_flag=y ;;
        3) fe_flag=y ;;
        4) be_flag=y ;;
        5) ms_flag=y ;;
        6) fdb_flag=y ;;
        q) exit 0 ;;
      esac
      break
    fi
  done
}

# Main logic
if [ ${ARG_NUM} -eq 0 ]; then
  Menu
fi

Confirm_Uninstall

if [ "${fe_flag}" == "y" ]; then
  Uninstall_FE
fi

if [ "${be_flag}" == "y" ]; then
  Uninstall_BE
fi

if [ "${ms_flag}" == "y" ]; then
  Uninstall_MS
fi

if [ "${fdb_flag}" == "y" ]; then
  Uninstall_FDB
fi

# Remove user if all components are uninstalled
if ! [ -d "${fe_install_dir}" ] && ! [ -d "${be_install_dir}" ] && ! [ -d "${ms_install_dir}" ]; then
  if id -u ${run_user} > /dev/null 2>&1; then
    userdel ${run_user} 2>/dev/null
    groupdel ${run_group} 2>/dev/null
    echo "${CSUCCESS}User ${run_user} and group ${run_group} removed.${CEND}"
  fi
fi

echo ""
echo "${CSUCCESS}Uninstall completed!${CEND}"

popd > /dev/null
