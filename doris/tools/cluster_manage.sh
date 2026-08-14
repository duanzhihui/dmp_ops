#!/bin/bash
# DorisStack - Apache Doris Cluster Deployment Tool
# Cluster management utility

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

doris_dir=$(dirname "$(dirname "$(readlink -f $0)")")
pushd ${doris_dir} > /dev/null
. ./include/ensure_options_conf.sh
Ensure_Options_Conf "${doris_dir}"
. ./options.conf
. ./include/color.sh
. ./include/doris_fe.sh
. ./include/doris_be.sh
. ./include/doris_ms.sh
. ./include/fdb.sh
. ./include/cluster.sh

Show_Help() {
  echo "Usage: $0 command [options]

Commands:
  status                      Show cluster status
  start-fe                    Start FE service
  stop-fe                     Stop FE service
  start-be                    Start BE service
  stop-be                     Stop BE service
  start-ms                    Start Meta Service
  stop-ms                     Stop Meta Service
  restart-fe                  Restart FE service
  restart-be                  Restart BE service
  restart-ms                  Restart Meta Service
  add-fe <ip> [port]          Add FE Follower node
  add-observer <ip> [port]    Add FE Observer node
  add-be <ip> [port]          Add BE node
  drop-be <ip> [port]         Decommission BE node
  show-fe                     Show FE nodes status
  show-be                     Show BE nodes status
  show-vaults                 Show Storage Vaults (separated mode)
  check-health                Run cluster health check
  check-fdb                   Check FoundationDB status
  "
}

case "$1" in
  status)
    Show_Cluster_Status "${2}"
    ;;
  start-fe)
    Start_FE "${2}"
    ;;
  stop-fe)
    Stop_FE
    ;;
  start-be)
    Start_BE
    ;;
  stop-be)
    Stop_BE
    ;;
  restart-fe)
    Stop_FE
    sleep 3
    Start_FE
    ;;
  restart-be)
    Stop_BE
    sleep 3
    Start_BE
    ;;
  start-ms)
    Start_MS
    ;;
  stop-ms)
    Stop_MS
    ;;
  restart-ms)
    Stop_MS
    sleep 3
    Start_MS
    ;;
  add-fe)
    if [ -z "$2" ]; then
      echo "${CFAILURE}Usage: $0 add-fe <ip> [port]${CEND}"
      exit 1
    fi
    local_ip=$(hostname -I | awk '{print $1}')
    Register_FE_Follower "${local_ip}" "$2" "${3:-${fe_edit_log_port}}"
    ;;
  add-observer)
    if [ -z "$2" ]; then
      echo "${CFAILURE}Usage: $0 add-observer <ip> [port]${CEND}"
      exit 1
    fi
    local_ip=$(hostname -I | awk '{print $1}')
    Register_FE_Observer "${local_ip}" "$2" "${3:-${fe_edit_log_port}}"
    ;;
  add-be)
    if [ -z "$2" ]; then
      echo "${CFAILURE}Usage: $0 add-be <ip> [port]${CEND}"
      exit 1
    fi
    local_ip=$(hostname -I | awk '{print $1}')
    Register_BE "${local_ip}" "$2" "${3:-${be_heartbeat_service_port}}"
    ;;
  drop-be)
    if [ -z "$2" ]; then
      echo "${CFAILURE}Usage: $0 drop-be <ip> [port]${CEND}"
      exit 1
    fi
    local_ip=$(hostname -I | awk '{print $1}')
    Decommission_BE "${local_ip}" "$2" "${3:-${be_heartbeat_service_port}}"
    ;;
  show-fe)
    local_ip=$(hostname -I | awk '{print $1}')
    mysql -uroot -P${fe_query_port} -h${local_ip} -e "show frontends\G"
    ;;
  show-be)
    local_ip=$(hostname -I | awk '{print $1}')
    mysql -uroot -P${fe_query_port} -h${local_ip} -e "show backends\G"
    ;;
  show-vaults)
    local_ip=$(hostname -I | awk '{print $1}')
    mysql -uroot -P${fe_query_port} -h${local_ip} -e "SHOW STORAGE VAULTS" 2>/dev/null || echo "${CFAILURE}Cannot query Storage Vaults${CEND}"
    ;;
  check-health)
    local_ip=$(hostname -I | awk '{print $1}')
    echo "${CMSG}Checking cluster health...${CEND}"
    echo ""
    echo "=== FE Status ==="
    Check_FE_Status
    echo ""
    echo "=== BE Status ==="
    Check_BE_Status
    echo ""
    echo "=== MS Status ==="
    Check_MS_Status 2>/dev/null || echo "Meta Service not installed"
    echo ""
    echo "=== FE Nodes ==="
    mysql -uroot -P${fe_query_port} -h${local_ip} -e "show frontends" 2>/dev/null || echo "${CFAILURE}Cannot connect to FE${CEND}"
    echo ""
    echo "=== BE Nodes ==="
    mysql -uroot -P${fe_query_port} -h${local_ip} -e "show backends" 2>/dev/null || echo "${CFAILURE}Cannot connect to FE${CEND}"
    ;;
  check-fdb)
    Check_FDB_Status
    ;;
  *)
    Show_Help
    ;;
esac

popd > /dev/null
