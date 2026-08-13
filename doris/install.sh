#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Main installation script
#
# Supports: Doris 2.x (LTS), 3.0.x, 4.1.x (see versions.txt)
# Package:  apache-doris-<ver>-bin-<arch>.tar.gz (unified for ALL versions)
#
# Deployment modes:
#   standalone  - FE + BE on single node
#   integrated  - 存算一体集群 (FE cluster + BE cluster)
#   separated   - 存算分离集群 (FDB + MS + FE + BE + Storage Vault, 3.x+ only)
#
# Reference:
#   https://doris.apache.org/zh-CN/docs/4.x/install/deploy-manually/integrated-storage-compute-deploy-manually
#   https://doris.apache.org/zh-CN/docs/4.x/install/deploy-manually/separating-storage-compute-deploy-manually

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
# Non-interactive package installs (this script also runs over ssh without a tty)
export DEBIAN_FRONTEND=noninteractive
[ -t 1 ] && clear
printf "
#######################################################################
#       DorisStack - Apache Doris Cluster Deployment Tool             #
#       Supports: Doris 2.1.x / 3.0.x / 4.1.x                        #
#       Package:  Unified (FE+BE+MS in one tar.gz)                    #
#       Modes:    standalone / integrated / separated                 #
#       For more information: https://doris.apache.org                #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

doris_dir=$(dirname "$(readlink -f $0)")
pushd ${doris_dir} > /dev/null
. ./versions.txt
. ./options.conf
# Runtime context propagated from the deploy node (cluster mode), overrides options.conf
[ -f ./.deploy_env ] && . ./.deploy_env
. ./include/color.sh
. ./include/check_os.sh
. ./include/download.sh
. ./include/check_env.sh
. ./include/doris_fe.sh
. ./include/doris_be.sh
. ./include/doris_ms.sh
. ./include/fdb.sh
. ./include/cluster.sh

version() {
  echo "version: 2.0.0"
  echo "updated date: 2025-06-13"
}

Show_Help() {
  version
  echo "Usage: $0 command ...[parameters]....
  --help, -h                  Show this help message
  --version, -v               Show version info
  --doris_ver [2|3|4]         Doris major version: 2) ${doris_2_ver}  3) ${doris_3_ver}  4) ${doris_4_ver}
                              (a full version string such as ${doris_3_ver} is also accepted)
  --deploy_mode [mode]        Deploy mode: standalone, integrated, separated
  --fe_only                   Install FE node only
  --be_only                   Install BE node only
  --ms_only                   Install Meta Service only (3.x+ separated mode)
  --helper [ip:port]          FE helper node for joining existing cluster
  --download_only             Download packages only, do not install
  --quiet, -q                 Non-interactive mode
  --status                    Show cluster status
  "
}

ARG_NUM=$#
TEMP=$(getopt -o hvVq --long help,version,doris_ver:,deploy_mode:,fe_only,be_only,ms_only,helper:,download_only,quiet,status -- "$@" 2>/dev/null)
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"

quiet_flag=n
fe_only_flag=n
be_only_flag=n
ms_only_flag=n
download_only_flag=n
doris_ver_option=""
helper_node=""
deploy_mode_from_cli=n

while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -v|-V|--version)
      version; exit 0
      ;;
    --doris_ver)
      doris_ver_option=$2; shift 2
      ;;
    --deploy_mode)
      deploy_mode=$2; deploy_mode_from_cli=y; shift 2
      ;;
    --fe_only)
      fe_only_flag=y; shift 1
      ;;
    --be_only)
      be_only_flag=y; shift 1
      ;;
    --ms_only)
      ms_only_flag=y; shift 1
      ;;
    --helper)
      helper_node=$2; shift 2
      ;;
    --download_only)
      download_only_flag=y; shift 1
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    --status)
      Show_Cluster_Status
      exit 0
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

# Interactive version selection
Select_Version() {
  # Support both major version (2/3/4) and full version string (e.g. 2.1.11)
  if [ -n "${doris_ver_option}" ]; then
    case "${doris_ver_option}" in
      2|${doris_2_ver}) doris_ver=${doris_2_ver} ;;
      3|${doris_3_ver}) doris_ver=${doris_3_ver} ;;
      4|${doris_4_ver}) doris_ver=${doris_4_ver} ;;
      *)
        echo "${CWARNING}Invalid doris_ver: ${doris_ver_option}${CEND}"
        echo "Valid: 2(${doris_2_ver}), 3(${doris_3_ver}), 4(${doris_4_ver})"
        exit 1
        ;;
    esac
  else
    while :; do
      echo
      echo 'Please select Apache Doris version:'
      echo -e "\t${CMSG}1${CEND}. Doris ${doris_2_ver} (LTS, 存算一体 only)"
      echo -e "\t${CMSG}2${CEND}. Doris ${doris_3_ver} (存算一体 / 存算分离)"
      echo -e "\t${CMSG}3${CEND}. Doris ${doris_4_ver} (Latest, 存算一体 / 存算分离)"
      read -e -p "Please input a number:(Default 3 press Enter) " doris_ver_option
      doris_ver_option=${doris_ver_option:-3}
      if [[ ! ${doris_ver_option} =~ ^[1-3]$ ]]; then
        echo "${CWARNING}input error! Please only input number 1~3${CEND}"
      else
        break
      fi
    done

    case "${doris_ver_option}" in
      1) doris_ver=${doris_2_ver} ;;
      2) doris_ver=${doris_3_ver} ;;
      3) doris_ver=${doris_4_ver} ;;
    esac
  fi

  doris_major_ver=${doris_ver%%.*}
  echo "${CMSG}Selected Doris version: ${doris_ver}${CEND}"
}

# Interactive deployment mode selection
Select_Deploy_Mode() {
  # If specific component flags are set, use standalone
  if [ "${fe_only_flag}" == "y" ] || [ "${be_only_flag}" == "y" ] || [ "${ms_only_flag}" == "y" ]; then
    deploy_mode=${deploy_mode:-standalone}
    return
  fi

  # If deploy_mode explicitly set via command line
  if [ "${deploy_mode_from_cli}" == "y" ]; then
    case "${deploy_mode}" in
      standalone|integrated|separated) ;;
      *)
        echo "${CFAILURE}Invalid deploy_mode: ${deploy_mode}${CEND}"
        echo "Valid: standalone, integrated, separated"
        exit 1
        ;;
    esac
    # For standalone mode, ensure component flags are set
    if [ "${deploy_mode}" == "standalone" ]; then
      [ "${fe_only_flag}" != "y" ] && [ "${be_only_flag}" != "y" ] && [ "${ms_only_flag}" != "y" ] && { fe_only_flag=y; be_only_flag=y; }
    fi
    return
  fi

  if [ "${quiet_flag}" != "y" ]; then
    local max_option=5
    while :; do
      echo
      echo 'Please select deployment mode:'
      echo -e "\t${CMSG}1${CEND}. Standalone (FE + BE on single node)"
      echo -e "\t${CMSG}2${CEND}. FE only (Frontend node)"
      echo -e "\t${CMSG}3${CEND}. BE only (Backend node)"
      echo -e "\t${CMSG}4${CEND}. 存算一体集群 (Integrated storage-compute cluster)"
      if [ "${doris_major_ver}" -ge 3 ]; then
        echo -e "\t${CMSG}5${CEND}. 存算分离集群 (Separating storage-compute cluster, 3.x+ only)"
      else
        max_option=4
      fi
      read -e -p "Please input a number:(Default 1 press Enter) " deploy_option
      deploy_option=${deploy_option:-1}
      if [[ ! ${deploy_option} =~ ^[1-${max_option}]$ ]]; then
        echo "${CWARNING}input error! Please only input number 1~${max_option}${CEND}"
      else
        break
      fi
    done

    case "${deploy_option}" in
      1) deploy_mode="standalone"; fe_only_flag=y; be_only_flag=y ;;
      2) deploy_mode="standalone"; fe_only_flag=y ;;
      3) deploy_mode="standalone"; be_only_flag=y ;;
      4) deploy_mode="integrated" ;;
      5) deploy_mode="separated" ;;
    esac
  else
    deploy_mode=${deploy_mode:-standalone}
    if [ "${deploy_mode}" == "standalone" ]; then
      [ "${fe_only_flag}" != "y" ] && [ "${be_only_flag}" != "y" ] && { fe_only_flag=y; be_only_flag=y; }
    fi
  fi

  echo "${CMSG}Deployment mode: ${deploy_mode}${CEND}"
}

# Main installation flow
Main() {
  # Select version
  Select_Version

  # Select deployment mode
  Select_Deploy_Mode

  # Validate separated mode version requirement
  if [ "${deploy_mode}" == "separated" ] && [ "${doris_major_ver}" -lt 3 ]; then
    echo "${CFAILURE}Doris ${doris_ver} does not support 存算分离 mode!${CEND}"
    echo "${CFAILURE}Separating storage-compute requires Doris 3.x+ (choose ${doris_3_ver} or ${doris_4_ver})${CEND}"
    exit 1
  fi

  # Check environment
  echo ""
  echo "${CMSG}[1/5] Checking environment...${CEND}"
  Check_Deps
  Create_User
  Detect_Network

  # Check Java
  echo ""
  echo "${CMSG}[2/5] Checking Java environment...${CEND}"
  if ! Check_Java; then
    local jdk_msg="JDK 8"
    [ "${doris_major_ver}" -ge 3 ] && jdk_msg="JDK 17"

    if [ "${quiet_flag}" == "y" ]; then
      Install_Java
    else
      while :; do
        read -e -p "Java not found. Install OpenJDK (${jdk_msg})? [y/n]: " install_java_flag
        if [[ ! ${install_java_flag} =~ ^[y,n]$ ]]; then
          echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
        else
          break
        fi
      done
      [ "${install_java_flag}" == 'y' ] && Install_Java
    fi
    if ! Check_Java; then
      echo "${CFAILURE}Java is required for Doris. Please install ${jdk_msg} manually.${CEND}"
      exit 1
    fi
  fi

  # Download packages
  echo ""
  echo "${CMSG}[3/5] Downloading Doris ${doris_ver} package...${CEND}"
  echo "${CMSG}Package: apache-doris-${doris_ver}-bin-${DORIS_ARCH}.tar.gz${CEND}"
  mkdir -p ${doris_dir}/src
  Download_doris "${doris_ver}"

  if [ "${download_only_flag}" == "y" ]; then
    echo "${CSUCCESS}Download completed! Package saved to ${doris_dir}/src/${CEND}"
    exit 0
  fi

  # Single-node install (standalone, or a single component driven by the deploy node)
  local single_node_install=n
  if [ "${fe_only_flag}" == "y" ] || [ "${be_only_flag}" == "y" ] || [ "${ms_only_flag}" == "y" ]; then
    single_node_install=y
  fi

  # Check ports (for standalone/single-component mode)
  echo ""
  echo "${CMSG}[4/5] Checking ports...${CEND}"
  if [ "${single_node_install}" == "y" ]; then
    if [ "${fe_only_flag}" == "y" ] && [ "${be_only_flag}" == "y" ]; then
      Check_Ports "all" || exit 1
    elif [ "${fe_only_flag}" == "y" ]; then
      Check_Ports "fe" || exit 1
    elif [ "${be_only_flag}" == "y" ]; then
      Check_Ports "be" || exit 1
    elif [ "${ms_only_flag}" == "y" ]; then
      echo "Checking MS port ${ms_brpc_port}..."
    fi
  else
    echo "Cluster mode: ports will be checked on each node during deployment."
  fi

  # Install
  echo ""
  echo "${CMSG}[5/5] Installing Doris ${doris_ver} (mode: ${deploy_mode})...${CEND}"

  # Component flags always mean "install these components on this node only",
  # regardless of the cluster deploy_mode used for configuration generation.
  if [ "${single_node_install}" == "y" ]; then
    # MS first: FE in separated mode needs the meta service endpoint reachable
    if [ "${ms_only_flag}" == "y" ]; then
      Install_MS "${doris_ver}"
      Start_MS || exit 1
    fi

    if [ "${fe_only_flag}" == "y" ]; then
      Install_FE "${doris_ver}"
      Start_FE "${helper_node}" || exit 1
    fi

    if [ "${be_only_flag}" == "y" ]; then
      Install_BE "${doris_ver}"
      Start_BE || exit 1

      # Both FE and BE on the same node: register BE on the local FE
      if [ "${fe_only_flag}" == "y" ]; then
        local_ip=$(hostname -I | awk '{print $1}')
        echo "${CMSG}Waiting for FE to be ready...${CEND}"
        Wait_FE_Ready "${local_ip}" || exit 1
        Register_BE "${local_ip}" "${local_ip}" "${be_heartbeat_service_port}"
      fi
    fi
  else
    case "${deploy_mode}" in
      integrated)
        Deploy_Integrated_Cluster "${doris_ver}" || exit 1
        ;;
      separated)
        Deploy_Separated_Cluster "${doris_ver}" || exit 1
        ;;
      *)
        echo "${CFAILURE}Nothing to install: deploy_mode=${deploy_mode} without component flags.${CEND}"
        exit 1
        ;;
    esac
  fi

  # Print summary for single-node install
  if [ "${single_node_install}" == "y" ]; then
    echo ""
    echo "${CSUCCESS}============================================${CEND}"
    echo "${CSUCCESS}  Installation Completed!${CEND}"
    echo "${CSUCCESS}============================================${CEND}"
    echo ""
    if [ "${fe_only_flag}" == "y" ]; then
      local_ip=$(hostname -I | awk '{print $1}')
      echo "  FE Web UI:  http://${local_ip}:${fe_http_port}"
      echo "  MySQL Port: ${local_ip}:${fe_query_port}"
      echo "  Connect:    mysql -uroot -P${fe_query_port} -h${local_ip}"
    fi
    if [ "${ms_only_flag}" == "y" ]; then
      echo "  MS Status:  systemctl status doris-ms"
    fi
    if [ "${be_only_flag}" == "y" ]; then
      echo "  BE Status:  systemctl status doris-be"
    fi
    echo ""
    echo "  Service Management:"
    [ "${fe_only_flag}" == "y" ] && echo "    systemctl {start|stop|restart|status} doris-fe"
    [ "${be_only_flag}" == "y" ] && echo "    systemctl {start|stop|restart|status} doris-be"
    [ "${ms_only_flag}" == "y" ] && echo "    systemctl {start|stop|restart|status} doris-ms"
    echo ""
  fi
}

Main
popd > /dev/null
