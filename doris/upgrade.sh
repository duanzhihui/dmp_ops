#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Upgrade script
#
# All versions use unified package: apache-doris-<ver>-bin-<arch>.tar.gz
# Supports upgrading: FE, BE, MS (Meta Service)

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear
printf "
#######################################################################
#       DorisStack - Apache Doris Cluster Deployment Tool             #
#                  Upgrade Apache Doris Version                       #
#       Package:  Unified (FE+BE+MS in one tar.gz)                    #
#       For more information: https://doris.apache.org                #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

doris_dir=$(dirname "$(readlink -f $0)")
pushd ${doris_dir} > /dev/null
. ./versions.txt
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${doris_dir}"
. ./options.conf
. ./include/color.sh
. ./include/check_os.sh
. ./include/download.sh
. ./include/check_env.sh
. ./include/doris_fe.sh
. ./include/doris_be.sh
. ./include/doris_ms.sh

Show_Help() {
  echo
  echo "Usage: $0 command ...[parameters]....
  --help, -h                  Show this help message
  --fe [version]              Upgrade FE to specified version
  --be [version]              Upgrade BE to specified version
  --ms [version]              Upgrade Meta Service to specified version
  --all [version]             Upgrade all installed components
  --rolling                   Rolling upgrade (for cluster mode)
  "
  echo "Available versions: ${doris_2_ver}, ${doris_3_ver}, ${doris_4_ver}"
}

ARG_NUM=$#
TEMP=$(getopt -o h --long help,fe:,be:,ms:,all:,rolling -- "$@" 2>/dev/null)
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"

upgrade_fe_flag=n
upgrade_be_flag=n
upgrade_ms_flag=n
rolling_flag=n
new_version=""

while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    --fe)
      upgrade_fe_flag=y; new_version=$2; shift 2
      ;;
    --be)
      upgrade_be_flag=y; new_version=$2; shift 2
      ;;
    --ms)
      upgrade_ms_flag=y; new_version=$2; shift 2
      ;;
    --all)
      upgrade_fe_flag=y; upgrade_be_flag=y; upgrade_ms_flag=y; new_version=$2; shift 2
      ;;
    --rolling)
      rolling_flag=y; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

Validate_Version() {
  local ver=$1
  if [[ ! "${ver}" =~ ^(${doris_2_ver}|${doris_3_ver}|${doris_4_ver})$ ]]; then
    echo "${CFAILURE}Invalid version: ${ver}${CEND}"
    echo "Available versions: ${doris_2_ver}, ${doris_3_ver}, ${doris_4_ver}"
    return 1
  fi
  return 0
}

Get_Current_Version() {
  local node_type=$1
  local current_ver=""

  if [ "${node_type}" == "fe" ] && [ -f "${fe_install_dir}/lib/doris-fe.jar" ]; then
    current_ver=$(ls ${fe_install_dir}/lib/ | grep -oP 'doris-fe-\K[0-9.]+' | head -1)
  elif [ "${node_type}" == "be" ] && [ -d "${be_install_dir}/lib" ]; then
    current_ver=$(cat ${be_install_dir}/bin/be_version 2>/dev/null || echo "unknown")
  elif [ "${node_type}" == "ms" ] && [ -d "${ms_install_dir}" ]; then
    current_ver="installed"
  fi

  echo ${current_ver:-"unknown"}
}

# Upgrade FE using unified package (extract fe/ subdirectory)
Upgrade_FE() {
  local target_ver=$1

  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Upgrading Doris FE to ${target_ver}${CEND}"
  echo "${CMSG}============================================${CEND}"

  local current_ver=$(Get_Current_Version "fe")
  echo "Current FE version: ${current_ver}"
  echo "Target FE version:  ${target_ver}"

  if [ ! -d "${fe_install_dir}" ]; then
    echo "${CFAILURE}FE is not installed at ${fe_install_dir}${CEND}"
    return 1
  fi

  # Download unified package
  echo "${CMSG}Downloading Doris ${target_ver} package...${CEND}"
  Download_doris "${target_ver}"

  # Backup current installation
  local backup_dir="${fe_install_dir}.bak.$(date +%Y%m%d%H%M%S)"
  echo "${CMSG}Backing up current FE to ${backup_dir}...${CEND}"
  cp -rf ${fe_install_dir} ${backup_dir}

  # Stop FE
  Stop_FE

  # Remove old lib/bin/webroot, keep conf and meta
  rm -rf ${fe_install_dir}/lib ${fe_install_dir}/bin ${fe_install_dir}/webroot

  # Extract fe/ from unified package, skip conf
  local doris_pkg=$(Get_Doris_Pkg "${target_ver}")
  local tmp_dir=$(mktemp -d)
  tar xzf ${doris_dir}/src/${doris_pkg} -C ${tmp_dir} --strip-components=1

  if [ -d "${tmp_dir}/fe" ]; then
    cp -rf ${tmp_dir}/fe/lib ${fe_install_dir}/ 2>/dev/null
    cp -rf ${tmp_dir}/fe/bin ${fe_install_dir}/ 2>/dev/null
    [ -d "${tmp_dir}/fe/webroot" ] && cp -rf ${tmp_dir}/fe/webroot ${fe_install_dir}/
  else
    echo "${CFAILURE}fe/ directory not found in package!${CEND}"
    rm -rf ${tmp_dir}
    # Restore from backup
    rm -rf ${fe_install_dir}
    mv ${backup_dir} ${fe_install_dir}
    Start_FE
    return 1
  fi
  rm -rf ${tmp_dir}

  # Restore ownership
  chown -R ${run_user}:${run_group} ${fe_install_dir}

  # Start FE
  Start_FE

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}FE upgraded successfully to ${target_ver}!${CEND}"
    echo "${CMSG}Backup saved at: ${backup_dir}${CEND}"
  else
    echo "${CFAILURE}FE upgrade failed! Restoring from backup...${CEND}"
    rm -rf ${fe_install_dir}
    mv ${backup_dir} ${fe_install_dir}
    Start_FE
    return 1
  fi
}

# Upgrade BE using unified package (extract be/ subdirectory)
Upgrade_BE() {
  local target_ver=$1

  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Upgrading Doris BE to ${target_ver}${CEND}"
  echo "${CMSG}============================================${CEND}"

  local current_ver=$(Get_Current_Version "be")
  echo "Current BE version: ${current_ver}"
  echo "Target BE version:  ${target_ver}"

  if [ ! -d "${be_install_dir}" ]; then
    echo "${CFAILURE}BE is not installed at ${be_install_dir}${CEND}"
    return 1
  fi

  # Download unified package
  echo "${CMSG}Downloading Doris ${target_ver} package...${CEND}"
  Download_doris "${target_ver}"

  # Backup current installation
  local backup_dir="${be_install_dir}.bak.$(date +%Y%m%d%H%M%S)"
  echo "${CMSG}Backing up current BE to ${backup_dir}...${CEND}"
  cp -rf ${be_install_dir} ${backup_dir}

  # Stop BE
  Stop_BE

  # Remove old lib and bin, keep conf and storage
  rm -rf ${be_install_dir}/lib ${be_install_dir}/bin

  # Extract be/ from unified package, skip conf and storage
  local doris_pkg=$(Get_Doris_Pkg "${target_ver}")
  local tmp_dir=$(mktemp -d)
  tar xzf ${doris_dir}/src/${doris_pkg} -C ${tmp_dir} --strip-components=1

  if [ -d "${tmp_dir}/be" ]; then
    cp -rf ${tmp_dir}/be/lib ${be_install_dir}/ 2>/dev/null
    cp -rf ${tmp_dir}/be/bin ${be_install_dir}/ 2>/dev/null
  else
    echo "${CFAILURE}be/ directory not found in package!${CEND}"
    rm -rf ${tmp_dir}
    rm -rf ${be_install_dir}
    mv ${backup_dir} ${be_install_dir}
    Start_BE
    return 1
  fi
  rm -rf ${tmp_dir}

  # Restore ownership
  chown -R ${run_user}:${run_group} ${be_install_dir}

  # Start BE
  Start_BE

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}BE upgraded successfully to ${target_ver}!${CEND}"
    echo "${CMSG}Backup saved at: ${backup_dir}${CEND}"
  else
    echo "${CFAILURE}BE upgrade failed! Restoring from backup...${CEND}"
    rm -rf ${be_install_dir}
    mv ${backup_dir} ${be_install_dir}
    Start_BE
    return 1
  fi
}

# Upgrade Meta Service using unified package (extract ms/ subdirectory)
Upgrade_MS() {
  local target_ver=$1
  local major_ver=${target_ver%%.*}

  echo "${CMSG}============================================${CEND}"
  echo "${CMSG}  Upgrading Doris Meta Service to ${target_ver}${CEND}"
  echo "${CMSG}============================================${CEND}"

  if [ "${major_ver}" -lt 3 ]; then
    echo "${CFAILURE}Meta Service requires Doris 3.x+!${CEND}"
    return 1
  fi

  if [ ! -d "${ms_install_dir}" ]; then
    echo "${CFAILURE}Meta Service is not installed at ${ms_install_dir}${CEND}"
    return 1
  fi

  # Download unified package
  echo "${CMSG}Downloading Doris ${target_ver} package...${CEND}"
  Download_doris "${target_ver}"

  # Backup
  local backup_dir="${ms_install_dir}.bak.$(date +%Y%m%d%H%M%S)"
  echo "${CMSG}Backing up current MS to ${backup_dir}...${CEND}"
  cp -rf ${ms_install_dir} ${backup_dir}

  # Stop MS
  Stop_MS

  # Remove old lib/bin, keep conf
  rm -rf ${ms_install_dir}/lib ${ms_install_dir}/bin

  # Extract ms/ from unified package
  local doris_pkg=$(Get_Doris_Pkg "${target_ver}")
  local tmp_dir=$(mktemp -d)
  tar xzf ${doris_dir}/src/${doris_pkg} -C ${tmp_dir} --strip-components=1

  if [ -d "${tmp_dir}/ms" ]; then
    cp -rf ${tmp_dir}/ms/lib ${ms_install_dir}/ 2>/dev/null
    cp -rf ${tmp_dir}/ms/bin ${ms_install_dir}/ 2>/dev/null
  else
    echo "${CFAILURE}ms/ directory not found in package!${CEND}"
    rm -rf ${tmp_dir}
    rm -rf ${ms_install_dir}
    mv ${backup_dir} ${ms_install_dir}
    Start_MS
    return 1
  fi
  rm -rf ${tmp_dir}

  chown -R ${run_user}:${run_group} ${ms_install_dir}

  Start_MS

  if [ $? -eq 0 ]; then
    echo "${CSUCCESS}Meta Service upgraded successfully to ${target_ver}!${CEND}"
    echo "${CMSG}Backup saved at: ${backup_dir}${CEND}"
  else
    echo "${CFAILURE}MS upgrade failed! Restoring from backup...${CEND}"
    rm -rf ${ms_install_dir}
    mv ${backup_dir} ${ms_install_dir}
    Start_MS
    return 1
  fi
}

# Interactive version selection
if [ ${ARG_NUM} -eq 0 ]; then
  echo ""
  echo 'Please select upgrade target:'
  echo -e "\t${CMSG}1${CEND}. Upgrade FE"
  echo -e "\t${CMSG}2${CEND}. Upgrade BE"
  echo -e "\t${CMSG}3${CEND}. Upgrade Meta Service"
  echo -e "\t${CMSG}4${CEND}. Upgrade All (FE + BE + MS)"
  read -e -p "Please input a number:(Default 4 press Enter) " upgrade_option
  upgrade_option=${upgrade_option:-4}

  case "${upgrade_option}" in
    1) upgrade_fe_flag=y ;;
    2) upgrade_be_flag=y ;;
    3) upgrade_ms_flag=y ;;
    4) upgrade_fe_flag=y; upgrade_be_flag=y; upgrade_ms_flag=y ;;
    *) echo "${CWARNING}input error!${CEND}"; exit 1 ;;
  esac

  echo ""
  echo 'Please select target version:'
  echo -e "\t${CMSG}1${CEND}. Doris ${doris_2_ver}"
  echo -e "\t${CMSG}2${CEND}. Doris ${doris_3_ver}"
  echo -e "\t${CMSG}3${CEND}. Doris ${doris_4_ver}"
  read -e -p "Please input a number: " ver_option

  case "${ver_option}" in
    1) new_version=${doris_2_ver} ;;
    2) new_version=${doris_3_ver} ;;
    3) new_version=${doris_4_ver} ;;
    *) echo "${CWARNING}input error!${CEND}"; exit 1 ;;
  esac
fi

# Validate version
Validate_Version "${new_version}" || exit 1

# Perform upgrade
if [ "${upgrade_fe_flag}" == "y" ]; then
  Upgrade_FE "${new_version}"
fi

if [ "${upgrade_be_flag}" == "y" ]; then
  Upgrade_BE "${new_version}"
fi

if [ "${upgrade_ms_flag}" == "y" ]; then
  # Only upgrade MS if it's installed
  if [ -d "${ms_install_dir}" ]; then
    Upgrade_MS "${new_version}"
  else
    echo "${CMSG}Meta Service not installed, skipping MS upgrade.${CEND}"
  fi
fi

echo ""
echo "${CSUCCESS}Upgrade process completed!${CEND}"

popd > /dev/null
